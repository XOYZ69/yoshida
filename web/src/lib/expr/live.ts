// What the formula panel needs from the editor, through the `yoshida-live`
// context: live values (an expression evaluated in place of one design
// field, for the card shown on the stage, with the value of every syntax tree
// node, ids as in core.ts `Node.id`), the field's scope, and design edits for
// the extract actions.

import type { ScopeResult } from "../engine";
import type { Problem } from "./core";

/** A value as the core writes it: colors are `#RRGGBBAA`, list items arrays. */
export type LiveValue = number | string | boolean | LiveValue[];

export type EvalResult = {
	/** How often the card evaluated the field: 0 when it never did (hidden layer, unused constant). */
	hits: number;
	/** The value of the whole expression, on the first evaluation. */
	value: LiveValue | null;
	/** Its type name (`number`, `text`, `color`, ...). */
	type: string | null;
	/** Parse and check problems of the source, spans in UTF-16. */
	problems: Problem[];
	/** Value per node id; null for nodes that were not evaluated (the branch not taken). */
	trace: (LiveValue | null)[];
};

export type LiveContext = {
	/** Label of the card the values are for, e.g. "Dare (3/12)"; null when there is none. */
	card(): string | null;
	/**
	 * Evaluates `src` in place of the design field at JSON pointer `path`
	 * (e.g. `/layers/3/fill`). Null when the field is unknown or nothing can
	 * be rendered.
	 */
	eval(path: string, src: string): Promise<EvalResult | null>;
	/** The names the field at `path` can use; null when unknown. */
	scope(path: string): Promise<ScopeResult | null>;
	/** The design being edited, as parsed JSON; null when there is none. */
	design(): Record<string, unknown> | null;
	/**
	 * Replaces the design's `consts` and `functions` with those of `next` and
	 * sets the field at `path` to `text`, as one undo step.
	 */
	extract(next: Record<string, unknown>, path: string, text: string): void;
};

export const LIVE_CONTEXT = "yoshida-live";
