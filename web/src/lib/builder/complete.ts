// Suggestions for expression fields: params, functions, built-ins, repeat
// names, @layer references and their fields, list item fields.
//
// The data (functions, built-ins, layer fields) lives in ../expr/catalog.ts;
// the code editor input (ExprInput) uses ../expr/completion.ts, which builds
// richer CodeMirror completions from the same context. `complete()` stays
// as a small plain-text helper.

import { BUILTINS, FUNCTIONS, LAYER_FIELDS, fnSignature } from '../expr/catalog';
export type { Expect } from '../expr/catalog';

export type Completion = { label: string; insert: string; detail: string };

export type CompletionContext = {
  /**
   * `item`: field name → type, for list params. `keys`: the key values seen
   * in the cards, for `list.Key` lookups. `label`/`note` are shown as docs.
   */
  params: { name: string; type: string; item?: Record<string, string>; keys?: string[]; label?: string; note?: string }[];
  /** `type` is the layer kind (`rect`, `text`, ..., `group`). */
  layers: { id: string; type: string }[];
  /** Repeat names in scope: index name, and item name with its list param. */
  locals: { name: string; detail: string; fields?: Record<string, string> }[];
};

const functions: [string, string][] = FUNCTIONS.map((f) => [f.name, fnSignature(f).text.slice(f.name.length)]);
const builtins: Record<string, [string, string][]> = Object.fromEntries(
  Object.entries(BUILTINS).map(([k, b]) => [k, b.fields.map((f) => [f.name, f.doc] as [string, string])]),
);
const layerFieldNames: Record<string, string[]> = Object.fromEntries(Object.entries(LAYER_FIELDS).map(([k, fs]) => [k, fs.map((f) => f.name)]));

/**
 * Suggestions for the word that ends at the caret. `before` is the text up
 * to the caret; for templates only the part inside `{...}` counts.
 */
export function complete(ctx: CompletionContext, before: string, template: boolean): { from: number; items: Completion[] } | null {
  if (template) {
    const open = before.lastIndexOf('{');
    if (open < 0 || before.lastIndexOf('}') > open) return null;
  }
  // Inside a string literal: nothing to suggest.
  const quotes = (before.match(/'/g) ?? []).length;
  if (quotes % 2 === 1) return null;
  const m = /(@?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\.?|@)$/.exec(before);
  if (!m) return null;
  const word = m[1];
  const from = before.length - word.length;
  const items: Completion[] = [];
  const dot = word.lastIndexOf('.');

  if (word.startsWith('@')) {
    if (dot < 0) {
      const prefix = word.slice(1);
      for (const l of ctx.layers) if (l.id.startsWith(prefix)) items.push({ label: '@' + l.id, insert: '@' + l.id + '.', detail: `${l.type} layer` });
    } else {
      const id = word.slice(1, word.indexOf('.'));
      const field = word.slice(word.indexOf('.') + 1);
      const l = ctx.layers.find((x) => x.id === id);
      for (const f of layerFieldNames[l?.type ?? 'rect'] ?? []) if (f.startsWith(field)) items.push({ label: f, insert: `@${id}.${f}`, detail: `${id}` });
    }
  } else if (dot >= 0) {
    const head = word.slice(0, dot);
    const tail = word.slice(dot + 1);
    if (builtins[head]) for (const [f, d] of builtins[head]) if (f.startsWith(tail)) items.push({ label: f, insert: `${head}.${f}`, detail: d });
    const local = ctx.locals.find((l) => l.name === head);
    for (const [f, t] of Object.entries(local?.fields ?? {})) if (f.startsWith(tail)) items.push({ label: f, insert: `${head}.${f}`, detail: t });
  } else {
    for (const l of ctx.locals) if (l.name.startsWith(word)) items.push({ label: l.name, insert: l.name, detail: l.detail });
    for (const p of ctx.params) if (p.name.startsWith(word)) items.push({ label: p.name, insert: p.name, detail: `param, ${p.type}` });
    for (const [f, d] of functions) if (f.startsWith(word)) items.push({ label: f + '()', insert: f + '(', detail: d });
    for (const b of Object.keys(builtins)) if (b.startsWith(word)) items.push({ label: b + '.', insert: b + '.', detail: 'built-in' });
  }
  const exact = items.length === 1 && items[0].insert === word;
  return items.length && !exact ? { from, items: items.slice(0, 40) } : null;
}
