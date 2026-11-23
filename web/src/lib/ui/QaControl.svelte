<script lang="ts">
// Review controls for the current card: approve, mark as needing changes,
// clear, and a list of comments that can be pinned to the card. The state
// lives in qa.json (see ../qa.ts); the keys are handled in App.svelte.
import { type QaComment, type QaEntry, type QaMark, type QaStatus, openComments, statusLabel } from "../qa";
import QaBadge from "./QaBadge.svelte";

let {
	status,
	entry,
	onmark,
	oncomment,
	onedit,
	onremove,
	pinTarget = null,
	onpin,
	active = null,
	onactive,
	onkeys,
	onoverview,
	composer = $bindable(),
}: {
	status: QaStatus;
	entry: QaEntry | undefined;
	/** Records a review of the card as it is now; null removes the mark. */
	onmark: (mark: QaMark | null) => void;
	oncomment: (text: string) => void;
	onedit: (id: string, patch: Partial<Pick<QaComment, "text" | "resolved" | "x" | "y">>) => void;
	onremove: (id: string) => void;
	/** The comment waiting for a click on the card to be pinned. */
	pinTarget?: string | null;
	onpin: (id: string | null) => void;
	active?: string | null;
	onactive: (id: string | null) => void;
	/** Opens the list of keys. */
	onkeys: () => void;
	onoverview: () => void;
	composer?: HTMLInputElement;
} = $props();

const comments = $derived(entry?.comments ?? []);
const open = $derived(openComments(entry).length);
let draft = $state("");

function add() {
	const t = draft.trim();
	if (!t) return;
	oncomment(t);
	draft = "";
}
</script>

<div class="qa-control" role="group" aria-label="Card review">
  <div class="line">
    <QaBadge {status} text />
    {#if open}<span class="open" title="Comments still to address">{open} open</span>{/if}
    <span class="spacer"></span>
    <button class="ok" class:on={status === 'approved'} disabled={open > 0} onclick={() => onmark('approved')} title={open ? 'Resolve the open comments first' : 'Approve the card as it is now (A). A later change to the card or its design shows it as changed since review.'}>Approve</button>
    <button class="bad" class:on={status === 'needs-changes'} onclick={() => onmark('needs-changes')} title="Mark the card as needing changes (N)">Needs changes</button>
    <button disabled={!entry?.status} onclick={() => onmark(null)} title="Remove the mark of this card. Comments stay.">Clear</button>
  </div>
  {#if open && !comments.every((c) => c.resolved)}
    <p class="hint">Resolve the open comments to approve.</p>
  {/if}
  {#if comments.length && !open && entry?.status === 'needs-changes'}
    <p class="hint">All comments are resolved. Approve the card when it is ready.</p>
  {/if}
  {#if status === 'stale'}
    <p class="hint">{statusLabel.stale}: approve it again after looking at it.</p>
  {/if}
  {#if entry?.by || entry?.at}
    <p class="meta">Marked{entry.by ? ` by ${entry.by}` : ''}{entry.at ? ` · ${entry.at.replace('T', ' ')}` : ''}</p>
  {/if}
  {#if comments.length}
    <ol class="comments" aria-label="Comments">
      {#each comments as c, i (c.id)}
        <li class:resolved={c.resolved} class:active={active === c.id}>
          <button class="num" class:pinned={c.x !== undefined} onclick={() => onactive(active === c.id ? null : c.id)} title={c.x !== undefined ? 'Pinned to the card' : 'Not pinned'}>{i + 1}</button>
          <div class="body">
            <textarea
              class="text"
              rows="1"
              value={c.text}
              aria-label="Comment {i + 1}"
              onfocus={() => onactive(c.id)}
              onchange={(e) => onedit(c.id, { text: e.currentTarget.value })}
              onkeydown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  e.currentTarget.blur();
                }
              }}></textarea>
            {#if c.by || c.at}<span class="meta">{c.by ?? ''}{c.by && c.at ? ' · ' : ''}{c.at ? c.at.replace('T', ' ') : ''}</span>{/if}
            <div class="acts">
          <button class:on={pinTarget === c.id} onclick={() => onpin(pinTarget === c.id ? null : c.id)} title={pinTarget === c.id ? 'Click the card to place the pin (Esc cancels)' : c.x !== undefined ? 'Move the pin (P)' : 'Pin to the card (P)'}>{pinTarget === c.id ? 'Click card' : c.x !== undefined ? 'Move' : 'Pin'}</button>
          {#if c.x !== undefined}<button onclick={() => onedit(c.id, { x: undefined, y: undefined })} title="Take the pin off the card">Unpin</button>{/if}
          <button onclick={() => onedit(c.id, { resolved: !c.resolved })} title={c.resolved ? 'Open it again' : 'Mark as addressed'}>{c.resolved ? 'Reopen' : 'Resolve'}</button>
          <button class="x" onclick={() => onremove(c.id)} aria-label="Delete comment {i + 1}" title="Delete the comment">×</button>
            </div>
          </div>
        </li>
      {/each}
    </ol>
  {/if}
  <input
    class="composer"
    type="text"
    placeholder="Add a comment (C), Enter to save"
    aria-label="New comment"
    bind:this={composer}
    bind:value={draft}
    onkeydown={(e) => {
      if (e.key === 'Enter') add();
      else if (e.key === 'Escape') {
        draft = '';
        e.currentTarget.blur();
      }
    }} />
  <div class="line foot">
    <button class="link" onclick={onoverview} title="Every comment and mark of the project (O)">Overview</button>
    <button class="link" onclick={onkeys} title="The review keys (?)">Keys <kbd>?</kbd></button>
  </div>
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
    flex-wrap: wrap;
    gap: 4px;
  }
  .acts {
    display: flex;
    gap: 4px;
  }
  .acts .x {
    margin-left: auto;
  }
  .spacer {
    flex: 1 1 0;
  }
  .line button,
  li button:not(.num) {
    padding: 1px 8px;
    font-size: 12px;
  }
  .ok.on {
    border-color: light-dark(#2a7d3f, #5fd17b);
  }
  .bad.on {
    border-color: var(--err);
  }
  .open {
    color: var(--err);
  }
  .hint {
    margin: 0;
    color: var(--warn-text);
  }
  .meta {
    margin: 0;
    color: var(--muted);
    font-size: 11px;
  }
  .comments {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  li {
    display: flex;
    align-items: flex-start;
    gap: 4px;
    padding: 2px;
    border-radius: 4px;
  }
  li.active {
    background: color-mix(in srgb, var(--err) 12%, transparent);
  }
  li.resolved .text {
    text-decoration: line-through;
    color: var(--muted);
  }
  .num {
    flex: none;
    width: 20px;
    height: 20px;
    padding: 0;
    border-radius: 50%;
    border: 1px dashed var(--muted);
    font-size: 11px;
    line-height: 1;
  }
  .num.pinned {
    border-style: solid;
    border-color: var(--err);
  }
  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .text,
  .composer {
    width: 100%;
    box-sizing: border-box;
  }
  .text {
    resize: none;
    field-sizing: content;
    min-height: 1.6em;
    font: inherit;
  }
  li button.on {
    border-color: var(--err);
  }
  .x {
    padding: 1px 6px;
  }
  .foot {
    justify-content: space-between;
  }
  .link {
    border: none;
    background: none;
    color: var(--muted);
    padding: 0;
  }
  .link:hover {
    color: inherit;
  }
  kbd {
    border: 1px solid var(--muted);
    border-radius: 3px;
    padding: 0 4px;
    font-size: 11px;
  }
</style>
