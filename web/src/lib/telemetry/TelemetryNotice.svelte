<script lang="ts">
// The start-up notice. It is shown before anything is sent and explains, in
// a few lines, what each level means. The server's default is preselected;
// nothing leaves the browser until a button here is pressed. When the
// server locks the level, this is a banner without a choice.
import Icon from "../ui/Icon.svelte";
import {
	confirmNotice,
	defaultLevel,
	lockedLevel,
	openSettings,
	telemetry,
} from "./state.svelte";
import type { Level } from "./core";

const locked = $derived(lockedLevel());
let pick: Level = $state(defaultLevel());

const retention = $derived(
	telemetry.server?.retention_days
		? `${telemetry.server.retention_days} days`
		: "without a time limit",
);

function accept() {
	confirmNotice(pick);
}

function details() {
	confirmNotice(pick);
	openSettings();
}
</script>

<section class="notice" aria-label="Usage statistics" data-testid="telemetry-notice">
	<div class="head">
		<span class="ico"><Icon name="info" /></span>
		<strong>{locked ? "This server limits usage statistics" : "Help improve yoshida?"}</strong>
	</div>
	{#if locked === "off"}
		<p>
			The server that hosts this editor has turned usage statistics <b>off</b>. Nothing is
			sent, and you cannot change that here.
		</p>
	{:else if locked === "basic"}
		<p>
			The server that hosts this editor counts <b>anonymous visits</b> (one ping per
			session, no ID in your browser, no address stored). Extra statistics are
			turned off, and you cannot change that here.
		</p>
	{:else}
		<p>
			Your projects, cards and images never leave your browser. This server can count
			how the editor is used. Counts stay on the server that hosts this editor, are
			kept {retention}, and go nowhere else.
		</p>
		<div class="levels" role="radiogroup" aria-label="Level">
			<label class:on={pick === "off"}>
				<input type="radio" name="tel-level" value="off" bind:group={pick} />
				<span><b>Off</b> Nothing is sent.</span>
			</label>
			<label class:on={pick === "basic"}>
				<input type="radio" name="tel-level" value="basic" bind:group={pick} />
				<span><b>Basic</b> One anonymous ping per session. Counts visitors per day with a hash that changes daily and is never stored.</span>
			</label>
			<label class:on={pick === "advanced"}>
				<input type="radio" name="tel-level" value="advanced" bind:group={pick} />
				<span><b>Advanced</b> Also counts which features and export formats are used and which error codes appear. No content, no text, no file names.</span>
			</label>
		</div>
	{/if}
	<div class="row">
		<button class="primary" onclick={accept} data-testid="telemetry-accept">
			{locked ? "Got it" : pick === "off" ? "Keep it off" : `Use ${pick}`}
		</button>
		<button onclick={details}>See what is tracked</button>
		<span class="muted">You can change this any time in Privacy (top bar).</span>
	</div>
</section>

<style>
	.notice {
		position: fixed;
		right: 16px;
		bottom: 16px;
		z-index: 60;
		width: min(440px, calc(100vw - 32px));
		display: grid;
		gap: 8px;
		padding: 12px 14px;
		background: var(--bg);
		border: 1px solid var(--line-strong);
		border-radius: 10px;
		box-shadow: 0 8px 28px rgb(0 0 0 / 0.22);
		font-size: 13px;
	}
	.head {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.ico {
		flex: none;
		display: inline-flex;
		width: 16px;
		height: 16px;
	}
	p {
		margin: 0;
		color: var(--muted);
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
	.levels b {
		margin-right: 4px;
	}
	.row {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
		align-items: center;
	}
	.primary {
		background: var(--accent-strong);
		border-color: var(--accent-strong);
		color: var(--on-accent);
	}
	.muted {
		color: var(--muted);
		font-size: 12px;
	}
</style>
