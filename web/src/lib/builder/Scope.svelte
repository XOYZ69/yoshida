<script lang="ts">
// Gives the expression fields inside it their own names in scope, in place
// of the inspector's (for example a design function's body, which sees its
// arguments but not layers or repeat names).
import { type Snippet, setContext } from "svelte";
import type { CompletionContext } from "./complete";

let {
	context,
	children,
}: { context: () => CompletionContext; children: Snippet } = $props();

setContext("yoshida-complete", () => context());
</script>

{@render children()}
