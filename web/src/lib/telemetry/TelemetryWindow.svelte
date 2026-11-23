<script lang="ts">
// Privacy settings: the level, what each level collects, a live view of the
// events this browser sent, and a download of that local log.
import { hostWord } from "../desktop.ts";
import Window from "../ui/Window.svelte";
import { KNOWN_EVENTS, type Level, pingBody } from "./core";
import {
	available,
	clearLog,
	closeSettings,
	currentLevel,
	downloadData,
	lockedLevel,
	setLevel,
	telemetry,
} from "./state.svelte";

const level = $derived(currentLevel());
const locked = $derived(lockedLevel());
const log = $derived([...telemetry.log].reverse().slice(0, 100));
const retention = $derived(
	telemetry.server?.retention_days
		? `${telemetry.server.retention_days} days`
		: "without a time limit",
);

const options: { value: Level; label: string; about: string }[] = [
	{ value: "off", label: "Off", about: "Nothing is sent." },
	{
		value: "basic",
		label: "Basic",
		about:
			`One anonymous ping per session. The server counts visitors per day with a salted hash that changes every UTC day and is never stored. Your address is not stored or logged, and ${hostWord()} keeps no ID.`,
	},
	{
		value: "advanced",
		label: "Advanced",
		about:
			"Basic, plus counts of features used, export formats and error codes. Only a group (feature, export, error) and a short name are sent, never text, file names, cards or numbers from your project.",
	},
];

function time(t: string): string {
	const d = new Date(t);
	return Number.isNaN(d.getTime()) ? t : d.toLocaleTimeString();
}
</script>

<Window key="telemetry" title="Privacy and usage statistics" width={580} height={720} onclose={closeSettings}>
	<div class="tel" data-testid="telemetry-window">
		{#if !available()}
			<p class="banner">
				This editor is not served by a yoshida server that collects usage statistics, so
				nothing is sent, whatever the level. Projects stay in {hostWord()}.
			</p>
		{:else}
			{#if locked}
				<p class="banner" role="status" data-testid="telemetry-locked">
					The server locks the level to <b>{locked}</b>. It can lower what is collected
					but never raise it, so you cannot change the level here.
				</p>
			{/if}
			<p class="lead">
				Statistics are anonymous counts, kept only on the server that hosts this editor
				({retention}). Nothing is uploaded anywhere else, and no project content is
				ever included.
			</p>
			<div class="levels" role="radiogroup" aria-label="Level">
				{#each options as o (o.value)}
					<label class:on={level === o.value} class:disabled={!!locked}>
						<input
							type="radio"
							name="tel-level-settings"
							value={o.value}
							checked={level === o.value}
							disabled={!!locked}
							onchange={() => setLevel(o.value)}
						/>
						<span><b>{o.label}</b> {o.about}</span>
					</label>
				{/each}
			</div>
			{#if !telemetry.prefs.notice}
				<p class="note">Nothing is sent until you have confirmed the notice.</p>
			{/if}
		{/if}

		<h3>What we track</h3>
		<table class="known">
			<tbody>
				{#each KNOWN_EVENTS as e (e.kind + e.name)}
					<tr><td><code>{e.kind}:{e.name}</code></td><td>{e.about}</td></tr>
				{/each}
			</tbody>
		</table>
		<p class="note">
			Sent at the basic level: <code>{pingBody("basic")}</code>. The advanced level adds the
			<code>feature</code>, <code>export</code> and <code>error</code> names above, one count each,
			and nothing else.
		</p>

		<h3>Sent from {hostWord()}</h3>
		<ul class="log" aria-live="polite" data-testid="telemetry-log">
			{#each log as e (e.t + e.kind + e.name)}
				<li>
					<time>{time(e.t)}</time>
					<code>{e.kind === "ping" ? "ping" : `${e.kind}:${e.name}`}</code>
					<span class="st {e.status}">{e.status}</span>
				</li>
			{:else}
				<li class="empty">Nothing yet.</li>
			{/each}
		</ul>
		<div class="row">
			<button onclick={downloadData} data-testid="telemetry-download">Download my data</button>
			<button onclick={clearLog} disabled={!telemetry.log.length}>Clear local log</button>
			{#if available()}
				<!-- Relative, like the API calls: the server answers under the editor's folder too. -->
				<a class="public" href="api/stats/page" target="_blank" rel="noopener noreferrer" data-testid="telemetry-public">Public stats</a>
			{/if}
		</div>
		<p class="note">
			The log lives in {hostWord()} only. The server stores totals per day, not individual
			events, so it cannot tell which of them were yours.
		</p>
	</div>
</Window>

<style>
	.tel {
		display: grid;
		gap: 10px;
		padding: 4px 2px 8px;
		font-size: 13px;
	}
	h3 {
		margin: 8px 0 0;
		font-size: 13px;
	}
	p {
		margin: 0;
	}
	.lead,
	.note {
		color: var(--muted);
	}
	.note {
		font-size: 12px;
	}
	.banner {
		padding: 8px 10px;
		border: 1px solid var(--warn);
		border-radius: 6px;
		background: var(--sel);
	}
	.levels {
		display: grid;
		gap: 4px;
	}
	.levels label {
		display: flex;
		gap: 8px;
		align-items: flex-start;
		padding: 6px 8px;
		border: 1px solid var(--line);
		border-radius: 6px;
		cursor: pointer;
	}
	.levels label.on {
		border-color: var(--accent);
		background: var(--sel);
	}
	.levels label.disabled {
		cursor: default;
		opacity: 0.8;
	}
	.known {
		border-collapse: collapse;
		width: 100%;
	}
	.known td {
		padding: 3px 6px;
		border-bottom: 1px solid var(--line);
		vertical-align: top;
	}
	.known td:first-child {
		white-space: nowrap;
	}
	code {
		font: 12px var(--mono);
	}
	.log {
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 180px;
		overflow: auto;
		border: 1px solid var(--line);
		border-radius: 6px;
	}
	.log li {
		display: grid;
		grid-template-columns: 80px 1fr auto;
		gap: 8px;
		padding: 3px 8px;
		border-bottom: 1px solid var(--line);
	}
	.log li.empty {
		display: block;
		color: var(--muted);
	}
	.st.sent {
		color: var(--muted);
	}
	.st.failed {
		color: var(--err);
	}
	.row {
		display: flex;
		gap: 8px;
		align-items: center;
	}
	.public {
		margin-left: auto;
	}
</style>
