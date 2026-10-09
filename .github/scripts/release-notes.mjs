#!/usr/bin/env node
// Release notes: GitHub's generated notes (categories from .github/release.yml)
// plus a "Highlights" section built from the ```release-note blocks in PR bodies.
//
//   release-notes.mjs preview    comment on PR $PR_NUMBER with the notes it will produce
//   release-notes.mjs release    write the notes for $TAG to $OUT (default release-notes.md)
//
// Env: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER (preview), TAG, PREVIOUS_TAG, INTRO, OUT (release).
// No dependencies. PR titles, bodies and labels are only ever treated as data.
import { readFileSync, writeFileSync } from 'node:fs';

const repo = process.env.GITHUB_REPOSITORY;
const api = `https://api.github.com/repos/${repo}`;
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

// A PR title like "feat(web): x" gets a label when it has no category label yet.
const TITLE_LABELS = { feat: 'enhancement', fix: 'bug', docs: 'documentation' };

function titleLabel(title) {
	const m = /^(\w+)(\([^)]*\))?(!)?:/.exec(title);
	if (!m) return null;
	if (m[3]) return 'breaking-change';
	return TITLE_LABELS[m[1]] || null;
}

function category(cfg, labels) {
	return cfg.categories.find((c) => c.labels.includes('*') || c.labels.some((l) => labels.includes(l)));
}

// Prevents @mentions and issue refs written in a PR from pinging anyone from the preview.
const defang = (s) => s.replace(/@/g, '@​');

function oneLine(text) {
	return text.split('\n').map((l) => l.trim()).filter(Boolean).join(' ');
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

async function highlights(generatedBody, extra = []) {
	const nums = [...new Set([...generatedBody.matchAll(/\/pull\/(\d+)/g)].map((m) => Number(m[1])))];
	const out = [];
	for (const n of nums) {
		const pr = await gh(`/pulls/${n}`);
		const note = releaseNote(pr.body);
		if (note) out.push({ n, text: oneLine(note) });
	}
	return [...out, ...extra];
}

function render({ intro, items, body }) {
	const parts = [];
	if (intro?.trim()) parts.push(intro.trim());
	if (items.length) parts.push('## Highlights\n' + items.map((i) => `- ${i.text} (#${i.n})`).join('\n'));
	parts.push(body.trim());
	return parts.join('\n\n') + '\n';
}

// Insert one entry (a PR that is not merged yet) into the generated notes, in
// the category's section, keeping the sections in the order of release.yml.
function insertEntry(body, cfg, cat, entry) {
	const tail = /\n\*\*Full Changelog\*\*[\s\S]*$/.exec(body);
	const main = tail ? body.slice(0, tail.index) : body;
	const contrib = main.indexOf('\n## New Contributors');
	const changes = contrib >= 0 ? main.slice(0, contrib) : main;
	const rest = (contrib >= 0 ? main.slice(contrib) : '') + (tail ? tail[0] : '');

	const sections = new Map();
	let current = null;
	for (const line of changes.split('\n')) {
		if (/^## /.test(line)) continue;
		if (/^### /.test(line)) {
			current = line.slice(4).trim();
			sections.set(current, []);
		} else if (line.trim()) {
			current ??= cat.title;
			if (!sections.has(current)) sections.set(current, []);
			sections.get(current).push(line);
		}
	}
	if (!sections.has(cat.title)) sections.set(cat.title, []);
	sections.get(cat.title).push(entry);

	const order = cfg.categories.map((c) => c.title);
	const titles = [...sections.keys()].sort((a, b) => order.indexOf(a) - order.indexOf(b));
	const md = titles.map((t) => `### ${t}\n${sections.get(t).join('\n')}`).join('\n\n');
	return `## What's Changed\n${md}\n${rest}`;
}

// --- modes -------------------------------------------------------------------------

async function preview() {
	const n = Number(process.env.PR_NUMBER);
	const cfg = loadConfig();
	const pr = await gh(`/pulls/${n}`);
	let labels = pr.labels.map((l) => l.name);
	const hints = [];

	if (!labels.some((l) => cfg.categories.some((c) => !c.labels.includes('*') && c.labels.includes(l)))) {
		const want = titleLabel(pr.title);
		if (want && !labels.includes(want) && !labels.includes('skip-changelog')) {
			try {
				if (process.env.DRY_RUN) throw new Error('dry run');
				await gh(`/issues/${n}/labels`, { method: 'POST', body: { labels: [want] } });
				labels.push(want);
				hints.push(`Added the \`${want}\` label from the title prefix.`);
			} catch (e) {
				console.log(`could not add label ${want}: ${e.message}`);
			}
		}
	}

	const previous = await lastRelease();
	const base = (await generated('next', previous)).replace(/\.\.\.next\b/, `...${BASE}`);

	let body = base;
	let included = false;
	const excluded = labels.find((l) => cfg.exclude.includes(l));
	if (excluded) {
		hints.push(`Left out of the notes because of the \`${excluded}\` label.`);
	} else if (new RegExp(`/pull/${n}\\b`).test(base)) {
		included = true;
	} else {
		const cat = category(cfg, labels);
		const entry = `* ${defang(pr.title)} by @${pr.user.login} in ${pr.html_url}`;
		body = insertEntry(base, cfg, cat, entry);
		included = true;
		if (cat.labels.includes('*')) hints.push('No category label: listed under "Other changes".');
	}

	const extra = [];
	const own = releaseNote(pr.body);
	if (own && included) extra.push({ n, text: defang(oneLine(own)) });
	else if (included) hints.push('No release note: only the generated list entry appears. Add text in the `release-note` block for a Highlights line.');
	const items = await highlights(base, extra);
	const notes = render({ items, body });

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

async function release() {
	const tag = process.env.TAG;
	if (!tag) throw new Error('TAG is required');
	const previous = process.env.PREVIOUS_TAG || (await lastRelease());
	const base = await generated(tag, previous);
	const items = await highlights(base);
	const notes = render({ intro: process.env.INTRO, items, body: base });
	writeFileSync(process.env.OUT || 'release-notes.md', notes);
	console.log(notes);
}

const mode = process.argv[2];
if (mode === 'preview') await preview();
else if (mode === 'release') await release();
else {
	console.error('usage: release-notes.mjs preview|release');
	process.exit(2);
}
