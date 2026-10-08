// Main-thread client for the render worker, plus the shapes the core returns.

import type { Placed } from './design';

export type Severity = 'error' | 'warning' | 'hint';

export type Diagnostic = {
  severity: Severity;
  code: number;
  file: string;
  path: string;
  line: number;
  col: number;
  span: [number, number];
  message: string;
  hint: string | null;
  card: string | null;
};

export type ParamType = 'number' | 'integer' | 'text' | 'bool' | 'color' | 'enum' | 'image' | 'list';

export type Param = {
  name: string;
  type: ParamType;
  required: boolean;
  default?: unknown;
  min?: number;
  max?: number;
  max_length?: number;
  label?: string;
  note?: string;
  /** Editor section (FORMAT.md section 4). */
  group?: string;
  options?: string[];
  item?: Record<string, string>;
};

export type CardInfo = { id: string; values: Record<string, unknown> };

export type SetInfo = {
  name: string;
  design: string;
  design_name: string;
  cards_file: string | null;
  ok: boolean;
  params: Param[];
  cards: CardInfo[];
};

export type ProjectInfo = { name: string; sets: SetInfo[] };

export type CheckResult = { diagnostics: Diagnostic[]; project: ProjectInfo };

export type RenderResult = {
  width: number;
  height: number;
  diagnostics: Diagnostic[];
  missing_urls: string[];
  /** Layer bounds, when the request asked for `layout`. */
  layout?: Placed[];
  bin: Uint8Array;
};

export type RenderArgs = {
  set: string;
  card: number;
  date: string;
  preview: boolean;
  format: 'rgba' | 'png' | 'png16';
  layout?: boolean;
};

export class Engine {
  private worker: Worker;
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void; progress?: (p: number) => void }>();
  version = '';

  constructor() {
    this.worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' });
    this.worker.onmessage = (e) => {
      const { id, ok, result, error, progress } = e.data;
      const p = this.pending.get(id);
      if (!p) return;
      if (progress !== undefined) {
        p.progress?.(progress);
        return;
      }
      this.pending.delete(id);
      if (ok) p.resolve(result);
      else p.reject(new Error(error));
    };
  }

  private call<T>(msg: object, transfer: Transferable[] = [], progress?: (p: number) => void): Promise<T> {
    const id = this.nextId++;
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, { resolve, reject, progress });
      this.worker.postMessage({ id, ...msg }, transfer);
    });
  }

  async init(): Promise<void> {
    const info = await this.call<{ version: string }>({ op: 'init', url: new URL('yoshida.wasm', document.baseURI).href });
    this.version = info.version;
  }

  setFiles(files: Map<string, Uint8Array>) {
    // Copies, so the caller keeps its buffers.
    return this.call<null>({ op: 'files', files: [...files].map(([p, d]) => [p, d.slice()]) });
  }

  put(path: string, data: Uint8Array) {
    return this.call<null>({ op: 'put', path, data: data.slice() });
  }

  remove(path: string) {
    return this.call<null>({ op: 'remove', path });
  }

  check() {
    return this.call<CheckResult>({ op: 'check' });
  }

  render(args: RenderArgs) {
    return this.call<RenderResult>({ op: 'render', args });
  }

  renderAll(args: Omit<RenderArgs, 'card'>, ids: string[], progress?: (p: number) => void) {
    return this.call<{ files: { id: string; png: Uint8Array }[]; diagnostics: Diagnostic[] }>({ op: 'renderAll', args, ids }, [], progress);
  }
}
