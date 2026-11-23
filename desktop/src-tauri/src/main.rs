// The yoshida desktop app: the web editor in a native window, with
// yoshida-server as a sidecar (for "Render on server") and a native folder
// backend. The commands below are the other half of
// web/src/lib/folder/native.ts.
//
// A folder can only be used after the user picked it in the dialog: picked
// folders are remembered in the app's config folder, and every path is
// checked to stay inside its folder (no "..", no absolute paths, no symlink
// that leads out).

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::net::{TcpListener, TcpStream};
use std::path::{Component, Path, PathBuf};
use std::process::{Child, Command};
use std::sync::Mutex;
use std::time::{Duration, UNIX_EPOCH};

use percent_encoding::percent_decode_str;
use serde::Serialize;
use tauri::ipc::{InvokeBody, Request, Response};
use tauri::{Manager, RunEvent, State};
use tauri_plugin_dialog::DialogExt;

/// Folders a project never contains (`skipDirs` in web/src/lib/project.ts).
const SKIP_DIRS: [&str; 4] = [".git", ".yoshida", "node_modules", "out"];

/// The port the sidecar tries first. It is fixed because the editor keeps its
/// projects in the browser storage of its origin, which includes the port.
const PORT: u16 = 47_810;

// ------------------------------------------------------------------ errors

fn io_err(e: io::Error) -> String {
    if e.kind() == io::ErrorKind::NotFound {
        format!("NotFound: {e}")
    } else {
        e.to_string()
    }
}

fn forbidden(what: impl std::fmt::Display) -> String {
    format!("Forbidden: {what}")
}

// ------------------------------------------------------------------ picked folders

struct Roots {
    file: PathBuf,
    set: Mutex<BTreeSet<PathBuf>>,
}

impl Roots {
    fn load(file: PathBuf) -> Self {
        let set = fs::read_to_string(&file)
            .ok()
            .and_then(|s| serde_json::from_str::<Vec<PathBuf>>(&s).ok())
            .unwrap_or_default()
            .into_iter()
            .collect();
        Roots {
            file,
            set: Mutex::new(set),
        }
    }

    fn add(&self, root: PathBuf) {
        let mut set = self.set.lock().unwrap();
        if set.insert(root) {
            if let Some(dir) = self.file.parent() {
                let _ = fs::create_dir_all(dir);
            }
            let list: Vec<_> = set.iter().collect();
            let _ = fs::write(&self.file, serde_json::to_string_pretty(&list).unwrap());
        }
    }

    /// The folder for `root`, if the user picked it.
    fn get(&self, root: &str) -> Result<PathBuf, String> {
        let p = PathBuf::from(root);
        if self.set.lock().unwrap().contains(&p) {
            Ok(p)
        } else {
            Err(forbidden(format!("{root} was not opened in this app")))
        }
    }
}

/// `rel` (a project path like `designs/a.design.json`) inside `root`.
fn inside(root: &Path, rel: &str) -> Result<PathBuf, String> {
    let r = Path::new(rel);
    let plain = !rel.is_empty() && r.components().all(|c| matches!(c, Component::Normal(_)));
    if !plain {
        return Err(forbidden(format!("{rel} is outside the folder")));
    }
    let full = root.join(r);
    // A symlink inside the folder may still point out of it: check the
    // nearest part of the path that exists.
    let base = root.canonicalize().map_err(io_err)?;
    let mut p = full.as_path();
    loop {
        if let Ok(real) = p.canonicalize() {
            return if real.starts_with(&base) {
                Ok(full)
            } else {
                Err(forbidden(format!("{rel} leads outside the folder")))
            };
        }
        p = p.parent().ok_or_else(|| forbidden(rel))?;
    }
}

// ------------------------------------------------------------------ commands

#[derive(Serialize)]
struct Picked {
    root: String,
    name: String,
}

#[derive(Serialize)]
struct Stat {
    size: u64,
    /// Milliseconds since 1970, like `File.lastModified`.
    modified: u64,
}

#[derive(Serialize)]
struct Entry {
    path: String,
    size: u64,
    modified: u64,
}

fn stat_of(m: &fs::Metadata) -> Stat {
    let modified = m
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_millis() as u64);
    Stat {
        size: m.len(),
        modified,
    }
}

#[tauri::command]
async fn pick_folder(
    app: tauri::AppHandle,
    roots: State<'_, Roots>,
) -> Result<Option<Picked>, String> {
    let Some(picked) = app.dialog().file().blocking_pick_folder() else {
        return Ok(None);
    };
    let path = picked.into_path().map_err(|e| e.to_string())?;
    let root = path.canonicalize().map_err(io_err)?;
    let name = root.file_name().map_or_else(
        || root.display().to_string(),
        |n| n.to_string_lossy().into(),
    );
    roots.add(root.clone());
    Ok(Some(Picked {
        root: root.to_string_lossy().into(),
        name,
    }))
}

#[tauri::command]
async fn read_folder(root: String, roots: State<'_, Roots>) -> Result<Vec<Entry>, String> {
    fn walk(dir: &Path, prefix: &str, out: &mut Vec<Entry>) -> io::Result<()> {
        for e in fs::read_dir(dir)? {
            let e = e?;
            let name = e.file_name().to_string_lossy().into_owned();
            let kind = e.file_type()?;
            if kind.is_dir() {
                if !SKIP_DIRS.contains(&name.as_str()) {
                    walk(&e.path(), &format!("{prefix}{name}/"), out)?;
                }
            } else {
                // Follows a symlink to a file; a symlink to a folder is skipped
                // (it could lead out of the folder or round in a loop).
                let Ok(m) = fs::metadata(e.path()) else {
                    continue;
                };
                if m.is_file() {
                    let s = stat_of(&m);
                    out.push(Entry {
                        path: format!("{prefix}{name}"),
                        size: s.size,
                        modified: s.modified,
                    });
                }
            }
        }
        Ok(())
    }
    let dir = roots.get(&root)?;
    let mut out = Vec::new();
    walk(&dir, "", &mut out).map_err(io_err)?;
    Ok(out)
}

#[tauri::command]
async fn read_file(
    root: String,
    path: String,
    roots: State<'_, Roots>,
) -> Result<Response, String> {
    let full = inside(&roots.get(&root)?, &path)?;
    Ok(Response::new(fs::read(full).map_err(io_err)?))
}

/// The file's bytes are the raw request body; root and path are in the
/// `x-root` and `x-path` headers, percent-encoded.
#[tauri::command]
async fn write_file(request: Request<'_>, roots: State<'_, Roots>) -> Result<Stat, String> {
    let header = |name: &str| -> Result<String, String> {
        let v = request
            .headers()
            .get(name)
            .ok_or_else(|| format!("missing {name}"))?;
        let v = v.to_str().map_err(|e| e.to_string())?;
        Ok(percent_decode_str(v)
            .decode_utf8()
            .map_err(|e| e.to_string())?
            .into_owned())
    };
    let InvokeBody::Raw(data) = request.body() else {
        return Err("write_file needs the file's bytes as the body".into());
    };
    let full = inside(&roots.get(&header("x-root")?)?, &header("x-path")?)?;
    if let Some(dir) = full.parent() {
        fs::create_dir_all(dir).map_err(io_err)?;
    }
    // Write next to the file and rename, so nobody sees half a file.
    let name = full.file_name().unwrap().to_string_lossy();
    let tmp = full.with_file_name(format!(".{name}.yoshida-tmp"));
    fs::write(&tmp, data).map_err(io_err)?;
    fs::rename(&tmp, &full).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        io_err(e)
    })?;
    Ok(stat_of(&fs::metadata(&full).map_err(io_err)?))
}

#[tauri::command]
async fn remove_file(root: String, path: String, roots: State<'_, Roots>) -> Result<(), String> {
    let full = inside(&roots.get(&root)?, &path)?;
    match fs::remove_file(full) {
        Err(e) if e.kind() != io::ErrorKind::NotFound => Err(io_err(e)),
        _ => Ok(()),
    }
}

// ------------------------------------------------------------------ sidecar

struct Server(Mutex<Option<Child>>);

fn free_port() -> Option<u16> {
    if TcpListener::bind(("127.0.0.1", PORT)).is_ok() {
        return Some(PORT);
    }
    TcpListener::bind(("127.0.0.1", 0))
        .ok()?
        .local_addr()
        .ok()
        .map(|a| a.port())
}

/// Starts yoshida-server (bundled next to the app) on 127.0.0.1 with the
/// bundled editor, then points the window at it. Without the sidecar the
/// window keeps the editor from the bundle and renders in the webview.
fn start_server(app: &tauri::App) -> Option<Child> {
    let exe = std::env::current_exe()
        .ok()?
        .with_file_name(if cfg!(windows) {
            "yoshida-server.exe"
        } else {
            "yoshida-server"
        });
    let web = app.path().resource_dir().ok()?.join("web");
    if !exe.is_file() || !web.is_dir() {
        return None;
    }
    let port = free_port()?;
    let child = Command::new(exe)
        .args([
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--no-telemetry",
        ])
        .arg("--web")
        .arg(&web)
        .spawn()
        .ok()?;
    let window = app.get_webview_window("main")?;
    std::thread::spawn(move || {
        for _ in 0..200 {
            if TcpStream::connect(("127.0.0.1", port)).is_ok() {
                if let Ok(url) = format!("http://127.0.0.1:{port}/").parse() {
                    let _ = window.navigate(url);
                }
                return;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    });
    Some(child)
}

fn main() {
    // WebKitGTK copies every frame through system memory when this is set
    // (often set globally to work around blank windows on some NVIDIA
    // setups), which makes dragging and resizing in the editor choppy. The
    // app turns it off; set YOSHIDA_KEEP_WEBKIT_ENV=1 to keep it.
    #[cfg(target_os = "linux")]
    if std::env::var_os("YOSHIDA_KEEP_WEBKIT_ENV").is_none() {
        std::env::remove_var("WEBKIT_DISABLE_DMABUF_RENDERER");
    }
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let config = app.path().app_config_dir()?;
            app.manage(Roots::load(config.join("folders.json")));
            // In development the window shows the Vite dev server instead.
            let child = if tauri::is_dev() {
                None
            } else {
                start_server(app)
            };
            app.manage(Server(Mutex::new(child)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            pick_folder,
            read_folder,
            read_file,
            write_file,
            remove_file
        ])
        .build(tauri::generate_context!())
        .expect("could not start yoshida");
    app.run(|app, event| {
        if let RunEvent::Exit = event {
            if let Some(mut child) = app.state::<Server>().0.lock().unwrap().take() {
                let _ = child.kill();
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::inside;
    use std::fs;

    #[test]
    fn paths_stay_inside_the_folder() {
        let tmp = std::env::temp_dir().join(format!("yoshida-desktop-{}", std::process::id()));
        let root = tmp.join("cards");
        fs::create_dir_all(root.join("designs")).unwrap();
        let root = root.canonicalize().unwrap();
        assert!(inside(&root, "yoshida.json").is_ok());
        assert!(inside(&root, "designs/a.design.json").is_ok());
        assert!(inside(&root, "new/folder/b.json").is_ok());
        for bad in [
            "",
            "../x.json",
            "designs/../../x.json",
            "/etc/passwd",
            "./a.json",
        ] {
            assert!(inside(&root, bad).is_err(), "{bad} should be refused");
        }
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&tmp, root.join("out-link")).unwrap();
            assert!(inside(&root, "out-link/x.json").is_err());
        }
        fs::remove_dir_all(&tmp).unwrap();
    }
}
