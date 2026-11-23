fn main() {
    // Commands of the app itself need permissions too (allow-<command>),
    // which the capability grants, also to the editor served from 127.0.0.1.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "pick_folder",
            "read_folder",
            "read_file",
            "write_file",
            "remove_file",
        ]),
    ))
    .expect("could not build the app manifest");
}
