<script lang="ts">
// Review controls for the current card: approve, mark as needing changes,
// clear, and a note. The state lives in qa.json (see ../qa.ts).
import { type QaEntry, type QaMark, type QaStatus, statusLabel } from "../qa";
import QaBadge from "./QaBadge.svelte";

let {
	status,
	entry,
	onmark,
	onnote,
}: {
	status: QaStatus;
	entry: QaEntry | undefined;
	/** Records a review of the card as it is now; null clears it. */
	onmark: (mark: QaMark | null) => void;
	onnote: (note: string) => void;
} = $props();
</script>

<div class="qa-control" role="group" aria-label="Card review">
  <div class="line">
    <QaBadge {status} text />
    <span class="spacer"></span>
    <button class="ok" class:on={status === 'approved'} onclick={() => onmark('approved')} title="Approve the card as it is now. A later change to the card or its design shows it as changed since review.">Approve</button>
    <button class="bad" class:on={status === 'needs-changes'} onclick={() => onmark('needs-changes')} title="Mark the card as needing changes">Needs changes</button>
    <button disabled={status === 'unreviewed'} onclick={() => onmark(null)} title="Remove the review of this card">Clear</button>
  </div>
  {#if status === 'stale'}
    <p class="hint">{statusLabel.stale}: approve it again after looking at it.</p>
  {/if}
  {#if entry}
    <input
      class="note"
      type="text"
      placeholder="Note"
      aria-label="Review note"
      value={entry.note ?? ''}
      onchange={(e) => onnote(e.currentTarget.value)}
      onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()} />
  {/if}
</div>

<style>
  .qa-control {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 6px;
    font-size: 12px;
  }
  .line {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .spacer {
    flex: 1;
  }
  .line button {
    padding: 1px 8px;
    font-size: 12px;
  }
  .ok.on {
    border-color: light-dark(#2a7d3f, #5fd17b);
  }
  .bad.on {
    border-color: var(--err);
  }
  .hint {
    margin: 0;
    color: var(--warn-text);
  }
  .note {
    width: 100%;
    box-sizing: border-box;
  }
</style>
