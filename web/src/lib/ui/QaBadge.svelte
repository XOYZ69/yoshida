<script lang="ts">
// A small status mark for a card's review state (see ../qa.ts).
import { type QaStatus, statusLabel } from "../qa";

let { status, text = false }: { status: QaStatus; text?: boolean } = $props();
const glyph: Record<QaStatus, string> = {
	unreviewed: "○",
	approved: "✓",
	"needs-changes": "✗",
	stale: "↻",
};
</script>

<span class="qa {status}" title={statusLabel[status]} role="img" aria-label={statusLabel[status]}>{glyph[status]}{#if text}&nbsp;{statusLabel[status]}{/if}</span>

<style>
  .qa {
    flex: none;
    font-size: 12px;
    line-height: 1;
    white-space: nowrap;
  }
  .unreviewed {
    color: var(--muted);
  }
  .approved {
    color: light-dark(#2a7d3f, #5fd17b);
  }
  .needs-changes {
    color: var(--err);
  }
  .stale {
    color: var(--warn-text);
  }
</style>
