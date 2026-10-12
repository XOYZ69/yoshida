<script lang="ts">
// Blocking overlay for exports and checks (see progress.svelte.ts): the
// window behind is blurred, so it is clear that work is running.
import Icon from "./Icon.svelte";
import { formatMs, progress } from "./progress.svelte";
import { overall, timeLeft } from "./progressMath";

let now = $state(Date.now());
let logEl: HTMLOListElement | undefined = $state();
let closeBtn: HTMLButtonElement | undefined = $state();

const t = $derived(progress.task);
/** Shown until the user closes it: a failure, or a finished task with a summary. */
const waiting = $derived(
	t?.state === 'error' || (t?.state === 'done' && t.summary !== ''),
);

$effect(() => {
	if (!t) return;
	const timer = setInterval(() => (now = Date.now()), 250);
	return () => clearInterval(timer);
});

// Keep the newest log line in view.
$effect(() => {
	if (t && logEl && t.log.length) logEl.scrollTop = logEl.scrollHeight;
});

$effect(() => {
	if (waiting) closeBtn?.focus();
});

/** 0..1 over all steps, or null while nothing measurable has happened. */
const ratio = $derived.by(() => {
	if (!t) return null;
	if (t.state === "done") return 1;
	return overall(t, now);
});

/** Time left from the pace of the work done so far (or the estimate). */
const left = $derived.by(() => {
	if (!t || t.state !== "running") return "";
	const per =
		t.total > 0 && t.done > 0 && t.perUnitMs
			? ` · ${(t.perUnitMs / 1000).toFixed(2)} s per ${t.unit.replace(/s$/, "")}`
			: "";
	const rest = timeLeft(ratio, t.started, now);
	if (rest !== null && (t.done > 0 || t.total === 0))
		return `About ${formatMs(rest)} left${per}`;
	if (t.estimateMs && t.workStarted) {
		const r = t.estimateMs - (now - t.workStarted);
		return r > 0
			? `About ${formatMs(r)} left (estimated)`
			: "Taking longer than estimated…";
	}
	return t.total > 0 || ratio !== null ? "Working out the time left…" : "";
});

const stamp = (at: number) =>
	t ? `+${((at - t.started) / 1000).toFixed(1)}s` : "";

function close() {
	progress.task = null;
}
</script>

<svelte:window
  onkeydowncapture={(e) => {
    if (!t) return;
    // Esc (and Enter on a finished summary) closes what is waiting for the user.
    if (waiting && (e.key === 'Escape' || (e.key === 'Enter' && t.state === 'done'))) {
      e.preventDefault();
      e.stopPropagation();
      close();
      return;
    }
    // A finished task closes by itself after a moment; keys pass through meanwhile.
    if (t.state === 'done' && !waiting) return;
    // Nothing behind the overlay reacts to keys while it is open.
    if (!(e.target as Element)?.closest?.('.progress')) {
      e.preventDefault();
      e.stopPropagation();
    }
  }} />

{#if t}
  <div class="backdrop" class:running={t.state === 'running'} class:done={t.state === 'done' && !t.summary} role="presentation">
    <div class="progress" role="alertdialog" aria-modal="true" aria-labelledby="progress-title" aria-busy={t.state === 'running'}>
      <div class="head">
        <h2 id="progress-title">{t.title}</h2>
        <span class="elapsed">{formatMs(now - t.started)}</span>
      </div>

      <div class="bar" class:indeterminate={ratio === null && t.state === 'running'} class:error={t.state === 'error'} role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={ratio === null ? undefined : Math.round(ratio * 100)}>
        <span style:width={ratio === null ? null : `${ratio * 100}%`}></span>
      </div>
      <div class="numbers">
        <span class="count">
          {#if t.state === 'error'}Failed{:else if t.state === 'done'}Done{:else if t.total > 0}{t.done} of {t.total} {t.unit}{#if ratio !== null} · {Math.floor(ratio * 100)}%{/if}{:else if ratio !== null}{Math.floor(ratio * 100)}%{:else}Working…{/if}
        </span>
        <span class="left">{left}</span>
      </div>

      {#if t.summary}<p class="summary">{t.summary}</p>{/if}

      {#if t.steps.length > 1}
        <ol class="steps">
          {#each t.steps as s, i}
            <li class={s.state}>
              <span class="mark" aria-hidden="true">
                {#if s.state === 'done'}<Icon name="check" />{:else if s.state === 'error'}<Icon name="close" />{:else if s.state === 'active'}<span class="spin"></span>{:else}{i + 1}{/if}
              </span>
              <span class="label">{s.label}</span>
              {#if s.detail}<span class="detail">{s.detail}</span>{/if}
            </li>
          {/each}
        </ol>
      {/if}

      {#if t.error}<p class="err">{t.error}</p>{/if}

      {#if t.log.length}
        <details class="log" open={t.state === 'error' || t.steps.length > 1}>
          <summary>Activity ({t.log.length})</summary>
          <ol bind:this={logEl}>
            {#each t.log as l}
              <li class:error={l.kind === 'error'}><span class="at">{stamp(l.at)}</span>{l.text}</li>
            {/each}
          </ol>
        </details>
      {/if}

      <div class="actions">
        {#if waiting}
          <button bind:this={closeBtn} onclick={close}>Close</button>
        {:else if t.cancel && t.state === 'running'}
          <button onclick={() => t.cancel?.()}>Cancel</button>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 980;
    display: grid;
    place-items: center;
    padding: 16px;
    background: color-mix(in srgb, var(--bg) 45%, transparent);
    backdrop-filter: blur(5px) saturate(0.8);
    cursor: default;
  }
  .backdrop.running {
    cursor: progress;
  }
  /* Finished: shown a moment longer, but no longer in the way. The dialog
     itself is never faded: only the backdrop could be made see-through. */
  .backdrop.done {
    pointer-events: none;
  }
  .progress {
    box-sizing: border-box;
    width: min(460px, 100%);
    max-height: calc(100vh - 32px);
    overflow: auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 18px 20px 16px;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgb(0 0 0 / 0.3);
    cursor: default;
  }
  .head {
    display: flex;
    align-items: baseline;
    gap: 12px;
  }
  h2 {
    flex: 1;
    margin: 0;
    font-size: 15px;
    font-weight: 600;
  }
  .elapsed {
    font-size: 12px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .bar {
    height: 8px;
    border-radius: 4px;
    background: var(--hover);
    overflow: hidden;
    position: relative;
  }
  .bar span {
    position: absolute;
    inset: 0 auto 0 0;
    border-radius: 4px;
    background: var(--accent-strong);
    transition: width 0.25s ease-out;
  }
  .bar.error span {
    background: var(--err);
  }
  .bar.indeterminate span {
    width: 35%;
    animation: slide 1.2s ease-in-out infinite;
  }
  @keyframes slide {
    from {
      left: -35%;
    }
    to {
      left: 100%;
    }
  }
  .numbers {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
  }
  .count {
    font-weight: 600;
  }
  .summary {
    margin: 0;
    font-size: 13px;
  }
  .left {
    color: var(--muted);
    text-align: right;
  }
  .steps {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 13px;
  }
  .steps li {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--muted);
  }
  .steps li.active,
  .steps li.done {
    color: var(--fg);
  }
  .steps li.error {
    color: var(--err);
  }
  .mark {
    flex: none;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    font-size: 11px;
    border: 1px solid var(--line);
  }
  .done .mark {
    border-color: transparent;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    color: var(--accent);
  }
  .error .mark {
    border-color: var(--err);
  }
  .active .mark {
    border-color: var(--accent);
  }
  .spin {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    border: 2px solid var(--accent);
    border-right-color: transparent;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  .label {
    flex: 1;
  }
  .detail {
    font-size: 12px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .err {
    margin: 0;
    color: var(--err);
    font-size: 13px;
  }
  .log summary {
    font-size: 12px;
    color: var(--muted);
    cursor: pointer;
  }
  .log ol {
    list-style: none;
    margin: 6px 0 0;
    padding: 6px 8px;
    max-height: 130px;
    overflow: auto;
    background: var(--bg-code);
    border: 1px solid var(--line);
    border-radius: 6px;
    font: 11px/1.5 var(--mono);
  }
  .log li.error {
    color: var(--err);
  }
  .at {
    display: inline-block;
    min-width: 48px;
    color: var(--muted);
  }
  .actions {
    display: flex;
    justify-content: flex-end;
  }
  .actions:empty {
    display: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .bar.indeterminate span,
    .spin {
      animation-duration: 3s;
    }
  }
</style>
