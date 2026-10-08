// Projects saved in this browser (IndexedDB). Nothing here leaves the
// machine: the files of a project, images and fonts included, are stored
// as they are, under a random id.

import type { Files } from './project';

export type ProjectMeta = {
  id: string;
  name: string;
  /** Milliseconds since the epoch. */
  updated: number;
  /** Total size of the files in bytes. */
  size: number;
  count: number;
};

const DB = 'yoshida';
const META = 'meta';
const FILES = 'files';
const LAST = 'yoshida.last-project';

let opening: Promise<IDBDatabase> | null = null;

function db(): Promise<IDBDatabase> {
  opening ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => {
      req.result.createObjectStore(META, { keyPath: 'id' });
      req.result.createObjectStore(FILES);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => {
      opening = null;
      reject(req.error);
    };
  });
  return opening;
}

function done(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error ?? new Error('transaction aborted'));
  });
}

function result<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export function newProjectId(): string {
  return crypto.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

/** Saved projects, most recently changed first. */
export async function listProjects(): Promise<ProjectMeta[]> {
  try {
    const tx = (await db()).transaction(META, 'readonly');
    const all = await result(tx.objectStore(META).getAll() as IDBRequest<ProjectMeta[]>);
    return all.sort((a, b) => b.updated - a.updated);
  } catch {
    return [];
  }
}

export async function loadProject(id: string): Promise<{ meta: ProjectMeta; files: Files } | null> {
  const tx = (await db()).transaction([META, FILES], 'readonly');
  const meta = (await result(tx.objectStore(META).get(id))) as ProjectMeta | undefined;
  const files = (await result(tx.objectStore(FILES).get(id))) as Files | undefined;
  return meta && files ? { meta, files } : null;
}

export async function saveProject(id: string, name: string, files: Files): Promise<ProjectMeta> {
  let size = 0;
  for (const d of files.values()) size += d.byteLength;
  const meta: ProjectMeta = { id, name, updated: Date.now(), size, count: files.size };
  const tx = (await db()).transaction([META, FILES], 'readwrite');
  tx.objectStore(META).put(meta);
  tx.objectStore(FILES).put(files, id);
  await done(tx);
  return meta;
}

export async function deleteProject(id: string) {
  const tx = (await db()).transaction([META, FILES], 'readwrite');
  tx.objectStore(META).delete(id);
  tx.objectStore(FILES).delete(id);
  await done(tx);
  if (lastProject() === id) setLastProject(null);
}

/** The project to reopen on the next visit. */
export function lastProject(): string | null {
  try {
    return localStorage.getItem(LAST);
  } catch {
    return null;
  }
}

export function setLastProject(id: string | null) {
  try {
    if (id) localStorage.setItem(LAST, id);
    else localStorage.removeItem(LAST);
  } catch {
    // Storage blocked (private mode): the project is still saved, just not reopened.
  }
}

/** Asks the browser not to evict saved projects when space runs low. */
export async function persistStorage() {
  try {
    if (navigator.storage?.persisted && !(await navigator.storage.persisted())) await navigator.storage.persist?.();
  } catch {
    // Not supported: projects are kept until the browser needs the space.
  }
}

export function formatSize(n: number) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export function formatAge(t: number) {
  const s = Math.round((Date.now() - t) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return new Date(t).toLocaleDateString();
}
