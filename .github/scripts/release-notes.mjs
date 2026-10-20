#!/usr/bin/env node
// Release notes. GitHub finds the merged PRs between two tags; this script
// sorts them into the sections of .github/release.yml by their conventional
// title ("feat(web): add a ruler"), falling back to labels, and writes one
// readable line per PR. A "Highlights" section comes from the ```release-note
// blocks in PR bodies, and an optional intro from .github/release-intro/<version>.md.
//
//   release-notes.mjs title      check the title of PR $PR_NUMBER and set its type label
//   release-notes.mjs preview    comment on PR $PR_NUMBER with the notes it will produce
//   release-notes.mjs release    write the notes for $TAG to $OUT (default release-notes.md)
//
// Env: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER (title, preview), TAG, PREVIOUS_TAG,
// INTRO, OUT (release). DRY_RUN=1 prints instead of writing to GitHub.
// No dependencies. PR titles, bodies and labels are only ever treated as data.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const repo = process.env.GITHUB_REPOSITORY;
const api = `${process.env.GITHUB_API_URL || 'https://api.github.com'}/repos/${repo}`;
const MARKER = '<!-- release-notes-preview -->';
const BASE = 'master';

async function gh(path, { method = 'GET', body } = {}) {
	const res = await fetch(path.startsWith('http') ? path : api + path, {
		method,
		headers: {
			authorization: `Bearer ${process.env.GH_TOKEN}`,
			accept: 'application/vnd.github+json',
			'x-github-api-version': '2022-11-28',
			'content-type': 'application/json',
		},
		body: body ? JSON.stringify(body) : undefined,
	});
	if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${await res.text()}`);
	return res.status === 204 ? null : res.json();
}

// --- .github/release.yml (inline label lists only) ---------------------------

function loadConfig() {
	const lines = readFileSync('.github/release.yml', 'utf8').split('\n');
	const list = (s) =>
		s
			.replace(/^.*\[/, '')
			.replace(/\].*$/, '')
			.split(',')
			.map((x) => x.trim().replace(/^['"]|['"]$/g, ''))
			.filter(Boolean);
	const cfg = { exclude: [], categories: [] };
	let inExclude = false;
	for (const raw of lines) {
		const line = raw.replace(/#.*$/, '');
		if (/^\s*exclude:/.test(line)) inExclude = true;
		else if (/^\s*categories:/.test(line)) inExclude = false;
		else if (inExclude && /^\s*labels:/.test(line)) cfg.exclude = list(line);
		else if (/^\s*- title:/.test(line))
			cfg.categories.push({ title: line.replace(/^\s*- title:\s*/, '').trim(), labels: [] });
		else if (!inExclude && /^\s*labels:/.test(line) && cfg.categories.length)
			cfg.categories.at(-1).labels = list(line);
	}
	return cfg;
}

// --- PR helpers ----------------------------------------------------------------

function releaseNote(body) {
	const m = /```release-note[^\n]*\n([\s\S]*?)```/.exec(body || '');
	const text = m ? m[1].trim() : '';
	return !text || /^none$/i.test(text) ? null : text;
}

// Conventional commit types and the label each one stands for. The label
// decides the section through .github/release.yml.
const TYPES = {
	feat: 'enhancement',
	fix: 'bug',
	perf: 'performance',
	docs: 'documentation',
	refactor: 'maintenance',
	chore: 'maintenance',
	ci: 'maintenance',
	build: 'maintenance',
	test: 'maintenance',
	style: 'maintenance',
	revert: 'maintenance',
};
const TYPE_LABELS = [...new Set(Object.values(TYPES))];

// "feat(web)!: add a ruler" -> { type, scope, breaking, desc }. Branch-style
// titles from before the title check ("Feat/font explorer") still sort
// correctly; they are marked legacy and only fail the title check.
function parseTitle(title) {
	const t = title.trim();
	let m = /^(\w+)(?:\(([^)]*)\))?(!)?:\s*(\S.*)$/.exec(t);
	if (m && TYPES[m[1].toLowerCase()])
		return { type: m[1].toLowerCase(), scope: m[2] || '', breaking: !!m[3], desc: m[4], legacy: false };
	m = /^(\w+)\/\s*(\S.*)$/.exec(t);
	if (m && TYPES[m[1].toLowerCase()])
		return { type: m[1].toLowerCase(), scope: '', breaking: false, desc: m[2], legacy: true };
	return null;
}

// The section for a PR: the title decides, a hand-set breaking-change label
// always wins, and labels alone are used when the title has no type.
function category(cfg, title, labels) {
	const t = parseTitle(title);
	const named = (l) => cfg.categories.find((c) => c.labels.includes(l));
	const other = cfg.categories.find((c) => c.labels.includes('*'));
	if (t?.breaking || labels.includes('breaking-change')) return named('breaking-change') || other;
	if (t) return named(TYPES[t.type]) || other;
	return cfg.categories.find((c) => !c.labels.includes('*') && c.labels.some((l) => labels.includes(l))) || other;
}

// Prevents @mentions written in a PR title from pinging anyone, and keeps
// its text from being read as HTML.
const esc = (s) => s.replace(/@/g, '@​').replace(/</g, '&lt;');

function oneLine(text) {
	return text.split('\n').map((l) => l.trim()).filter(Boolean).join(' ');
}

// Bare GitHub URLs and @names in generated text become Markdown links, so the
// notes read the same on GitHub and on the website.
function linkify(s) {
	return s
		.replace(/(?<![\]("<])https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/(\d+)/g, (u, n) => `[#${n}](${u})`)
		.replace(/(?<![\]("<])https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/compare\/(\S+?)(?=\s|$|\))/g, (u, c) => `[${c}](${u})`)
		.replace(/(?<![\w[/])@([A-Za-z0-9-]+)(?![\w\]/-])/g, (m, u) => `[@${u}](https://github.com/${u})`);
}

const upperFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

// One line per PR: "- **web:** Add a ruler ([#41](url) by [@user](url))".
function line(pr) {
	const t = parseTitle(pr.title);
	const scope = t?.scope ? `**${esc(t.scope)}:** ` : '';
	const text = upperFirst(esc(t ? t.desc : pr.title));
	const who = pr.user.login;
	return `- ${scope}${text} ([#${pr.number}](${pr.html_url}) by [@${who}](https://github.com/${who}))`;
}

// --- notes -----------------------------------------------------------------------

async function generated(tag, previous) {
	const body = { tag_name: tag, target_commitish: BASE };
	if (previous) body.previous_tag_name = previous;
	return (await gh('/releases/generate-notes', { method: 'POST', body })).body;
}

async function lastRelease() {
	try {
		return (await gh('/releases/latest')).tag_name;
	} catch {
		return null;
	}
}

function render({ intro, items, sections, rest }) {
	const parts = [];
	if (intro?.trim()) parts.push(intro.trim());
	if (items.length) parts.push('## Highlights\n' + items.map((i) => `- ${i.text} ([#${i.n}](${i.url}))`).join('\n'));
	if (sections.length)
		parts.push("## What's changed\n\n" + sections.map((s) => `### ${s.title}\n${s.lines.join('\n')}`).join('\n\n'));
	if (rest.trim()) parts.push(rest.trim());
	return parts.join('\n\n') + '\n';
}

// The part of GitHub's generated notes that is not the PR list: new
// contributors and the compare link.
function tailOf(body) {
	const contrib = /\n## New Contributors\n[\s\S]*?(?=\n\*\*Full Changelog\*\*|$)/.exec(body);
	const full = /\*\*Full Changelog\*\*:[^\n]*/.exec(body);
	const parts = [];
	if (contrib) parts.push(contrib[0].trim().replace('## New Contributors', '## New contributors'));
	if (full) parts.push(full[0]);
	return linkify(parts.join('\n\n'));
}

// The PRs GitHub found in generatedBody, sorted into sections.
// extra: PRs that are not merged yet (preview).
async function collect(cfg, generatedBody, extra = []) {
	const nums = [...new Set([...generatedBody.matchAll(/\/pull\/(\d+)/g)].map((m) => Number(m[1])))];
	const prs = [];
	for (const n of nums) prs.push(await gh(`/pulls/${n}`));
	for (const pr of extra) if (!prs.some((p) => p.number === pr.number)) prs.push(pr);
	const kept = prs
		.filter((pr) => !pr.labels.some((l) => cfg.exclude.includes(l.name)))
		.sort((a, b) => a.number - b.number);

	const sections = [];
	for (const c of cfg.categories) {
		const lines = kept.filter((pr) => category(cfg, pr.title, pr.labels.map((l) => l.name)) === c).map(line);
		if (lines.length) sections.push({ title: c.title, lines });
	}
	const items = [];
	for (const pr of kept) {
		const note = releaseNote(pr.body);
		if (note) items.push({ n: pr.number, url: pr.html_url, text: esc(oneLine(note)) });
	}
	return { sections, items };
}

// --- modes -------------------------------------------------------------------------

const TITLE_HELP =
	'Use a conventional title: `type(scope): short description`, for example `feat(web): add a ruler` ' +
	'or `fix: keep the selection after undo`. Types: ' +
	Object.keys(TYPES).join(', ') +
	'. Add `!` before the colon for a breaking change. The title becomes the release note line.';

// Fails when the title is not conventional; otherwise makes the type label
// (and breaking-change) match the title, so labels never disagree with it.
async function title() {
	const n = Number(process.env.PR_NUMBER);
	const pr = await gh(`/pulls/${n}`);
	const t = parseTitle(pr.title);
	if (!t || t.legacy) {
		console.log(`::error title=PR title::"${pr.title}" is not a conventional title. ${TITLE_HELP.replace(/`/g, '')}`);
		process.exitCode = 1;
		return;
	}
	const labels = pr.labels.map((l) => l.name);
	const want = [TYPES[t.type], ...(t.breaking ? ['breaking-change'] : [])];
	const stale = TYPE_LABELS.filter((l) => labels.includes(l) && !want.includes(l));
	const missing = want.filter((l) => !labels.includes(l));
	console.log(`labels: add [${missing}], remove [${stale}]`);
	if (process.env.DRY_RUN) return;
	for (const l of stale) await gh(`/issues/${n}/labels/${encodeURIComponent(l)}`, { method: 'DELETE' });
	if (missing.length) await gh(`/issues/${n}/labels`, { method: 'POST', body: { labels: missing } });
}

async function preview() {
	const n = Number(process.env.PR_NUMBER);
	const cfg = loadConfig();
	const pr = await gh(`/pulls/${n}`);
	const labels = pr.labels.map((l) => l.name);
	const hints = [];

	const t = parseTitle(pr.title);
	const excluded = labels.find((l) => cfg.exclude.includes(l));
	if (excluded) hints.push(`Left out of the notes because of the \`${excluded}\` label.`);
	else if (!t) hints.push(`The title has no type, so this is listed under "Other changes". ${TITLE_HELP}`);
	else if (t.legacy) hints.push(`Branch-style title, sorted by its prefix this time. ${TITLE_HELP}`);
	if (!excluded && !releaseNote(pr.body))
		hints.push('No release note: only the list entry appears. Add text in the `release-note` block for a Highlights line.');

	const previous = await lastRelease();
	const base = (await generated('next', previous)).replace(/\.\.\.next\b/, `...${BASE}`);
	const { sections, items } = await collect(cfg, base, [pr]);
	const notes = render({ items, sections, rest: tailOf(base) });

	const comment = [
		MARKER,
		`### Release notes preview`,
		`What the notes would contain if everything merged now (last release: \`${previous ?? 'none'}\`). Updates when the PR title, body or labels change.`,
		...(hints.length ? ['', ...hints.map((h) => `> ${h}`)] : []),
		'',
		notes,
		'<details><summary>Raw markdown</summary>',
		'',
		'`````markdown',
		notes.replace(/`````/g, "'''''"),
		'`````',
		'</details>',
	].join('\n');

	if (process.env.DRY_RUN) return console.log(comment);
	const comments = await gh(`/issues/${n}/comments?per_page=100`);
	const mine = comments.find((c) => c.body?.startsWith(MARKER) && c.user?.type === 'Bot');
	if (mine) await gh(`/issues/comments/${mine.id}`, { method: 'PATCH', body: { body: comment } });
	else await gh(`/issues/${n}/comments`, { method: 'POST', body: { body: comment } });
	console.log(notes);
}

// A hand-written intro for a version: .github/release-intro/<version>.md.
function introFor(tag) {
	if (process.env.INTRO) return process.env.INTRO;
	const file = `.github/release-intro/${tag.replace(/^v/, '')}.md`;
	return existsSync(file) ? readFileSync(file, 'utf8') : '';
}

async function release() {
	const tag = process.env.TAG;
	if (!tag) throw new Error('TAG is required');
	const cfg = loadConfig();
	const previous = process.env.PREVIOUS_TAG || (await lastRelease());
	const base = await generated(tag, previous);
	const { sections, items } = await collect(cfg, base);
	const notes = render({ intro: introFor(tag), items, sections, rest: tailOf(base) });
	writeFileSync(process.env.OUT || 'release-notes.md', notes);
	console.log(notes);
}

const mode = process.argv[2];
if (mode === 'title') await title();
else if (mode === 'preview') await preview();
else if (mode === 'release') await release();
else {
	console.error('usage: release-notes.mjs title|preview|release');
	process.exit(2);
}
