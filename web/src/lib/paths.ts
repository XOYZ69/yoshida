// Project paths: the folder tree for the file browser, and finding or
// rewriting the places that refer to a file when it is renamed, moved or
// deleted. Every path in a project file is relative to the project root
// (FORMAT.md section 1), so a reference is a JSON string (or CSV cell) equal
// to the path. Path templates such as "cards/{card_type}.png" cannot be
// rewritten; they are reported so the user can fix them.

import { parseCsv, writeCsv, formatJson, textOf, bytesOf, type Files } from './project';

/** Marker file that keeps an otherwise empty folder in the project. */
export const keepName = '.keep';

export function isKeep(path: string) {
  return path === keepName || path.endsWith(`/${keepName}`);
}

export function dirOf(path: string) {
  const i = path.lastIndexOf('/');
  return i < 0 ? '' : path.slice(0, i);
}

export function baseOf(path: string) {
  return path.slice(path.lastIndexOf('/') + 1);
}

export function join(dir: string, name: string) {
  return dir ? `${dir}/${name}` : name;
}

/** A file or folder name: no slashes, not empty, not "." or "..". */
export function nameError(name: string) {
  if (!name.trim()) return 'Enter a name.';
  if (/[\\/]/.test(name)) return 'A name cannot contain / or \\.';
  if (name === '.' || name === '..') return 'Choose another name.';
  if (name === keepName) return `'${keepName}' is reserved.`;
  return '';
}

export type TreeNode = { name: string; path: string; dir: boolean; children: TreeNode[]; size: number };

/** Folders first, then files, each A to Z; `.keep` markers only make their folder exist. */
export function buildTree(files: Files): TreeNode {
  const root: TreeNode = { name: '', path: '', dir: true, children: [], size: 0 };
  const dirs = new Map<string, TreeNode>([['', root]]);
  const ensure = (path: string): TreeNode => {
    const have = dirs.get(path);
    if (have) return have;
    const parent = ensure(dirOf(path));
    const node: TreeNode = { name: baseOf(path), path, dir: true, children: [], size: 0 };
    parent.children.push(node);
    dirs.set(path, node);
    return node;
  };
  for (const [p, d] of files) {
    const parent = ensure(dirOf(p));
    if (isKeep(p)) continue;
    parent.children.push({ name: baseOf(p), path: p, dir: false, children: [], size: d.length });
  }
  const sort = (n: TreeNode) => {
    n.children.sort((a, b) => (a.dir !== b.dir ? (a.dir ? -1 : 1) : a.name.localeCompare(b.name, undefined, { numeric: true })));
    for (const c of n.children) {
      if (c.dir) sort(c);
      n.size += c.size;
    }
  };
  sort(root);
  return root;
}

/** Every file path under a folder (or the path itself for a file). */
export function pathsUnder(files: Files, path: string): string[] {
  if (files.has(path)) return [path];
  const prefix = `${path}/`;
  return [...files.keys()].filter((p) => p.startsWith(prefix));
}

const refFile = (p: string) => /\.(json|csv)$/i.test(p);

/** Static parts of a path template, as a regex, or null when it has no static part. */
function templateRegex(t: string): RegExp | null {
  const parts = t.split(/\{[^{}]*\}/);
  if (parts.join('').trim() === '') return null;
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^${parts.map(esc).join('.+')}$`);
}

export type Refs = {
  /** Files with a string equal to the path, and how many. */
  files: Map<string, number>;
  /** Path templates whose fixed parts match the path. */
  templates: { file: string; template: string }[];
};

function walkStrings(v: unknown, fn: (s: string) => void) {
  if (typeof v === 'string') fn(v);
  else if (Array.isArray(v)) v.forEach((x) => walkStrings(x, fn));
  else if (v && typeof v === 'object') Object.values(v).forEach((x) => walkStrings(x, fn));
}

/** Where each of `paths` is referred to in the project's JSON and CSV files. */
export function findRefs(files: Files, paths: string[]): Map<string, Refs> {
  const want = new Set(paths);
  const out = new Map<string, Refs>(paths.map((p) => [p, { files: new Map(), templates: [] }]));
  for (const [f, d] of files) {
    if (!refFile(f)) continue;
    const strings: string[] = [];
    try {
      const text = textOf(d);
      if (f.toLowerCase().endsWith('.csv')) parseCsv(text).forEach((r) => strings.push(...r));
      else walkStrings(JSON.parse(text), (s) => strings.push(s));
    } catch {
      continue;
    }
    for (const s of strings) {
      if (want.has(s)) {
        const r = out.get(s)!;
        r.files.set(f, (r.files.get(f) ?? 0) + 1);
      } else if (s.includes('{')) {
        const re = templateRegex(s);
        if (!re) continue;
        for (const p of paths) {
          const r = out.get(p)!;
          if (re.test(p) && !r.templates.some((t) => t.file === f && t.template === s)) r.templates.push({ file: f, template: s });
        }
      }
    }
  }
  return out;
}

/** How many files refer to each path (0 for unused), for the whole project. */
export function useCounts(files: Files): Map<string, number> {
  const paths = [...files.keys()].filter((p) => !isKeep(p));
  const refs = findRefs(files, paths);
  return new Map(paths.map((p) => [p, refs.get(p)!.files.size]));
}

function mapStrings(v: unknown, fn: (s: string) => string): unknown {
  if (typeof v === 'string') return fn(v);
  if (Array.isArray(v)) return v.map((x) => mapStrings(x, fn));
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, mapStrings(x, fn)]));
  return v;
}

/**
 * New texts for the JSON and CSV files that refer to a renamed path,
 * keyed by their current path. Files with syntax errors are left alone.
 */
export function rewriteRefs(files: Files, renames: Map<string, string>): Map<string, Uint8Array> {
  const out = new Map<string, Uint8Array>();
  for (const [f, d] of files) {
    if (!refFile(f)) continue;
    const text = textOf(d);
    let next = text;
    try {
      if (f.toLowerCase().endsWith('.csv')) {
        const rows = parseCsv(text);
        let changed = false;
        const mapped = rows.map((r) =>
          r.map((c) => {
            const to = renames.get(c);
            if (to === undefined) return c;
            changed = true;
            return to;
          }),
        );
        if (changed) next = writeCsv(mapped);
      } else {
        let changed = false;
        const v = mapStrings(JSON.parse(text), (s) => {
          const to = renames.get(s);
          if (to === undefined) return s;
          changed = true;
          return to;
        });
        if (changed) next = formatJson(v);
      }
    } catch {
      continue;
    }
    if (next !== text) out.set(f, bytesOf(next));
  }
  return out;
}

/** `name (2).ext`, `name (3).ext`, ... until it is free. */
export function freePath(files: Files, path: string): string {
  if (!files.has(path)) return path;
  const dir = dirOf(path);
  const base = baseOf(path);
  const m = /^(.*?)((?:\.[A-Za-z0-9]+)*)$/.exec(base)!;
  const stem = m[1] || base;
  const ext = m[1] ? m[2] : '';
  for (let n = 2; ; n++) {
    const p = join(dir, `${stem} (${n})${ext}`);
    if (!files.has(p)) return p;
  }
}
