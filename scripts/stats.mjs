#!/usr/bin/env node
// Collects the public numbers shown on the website's Stats page from
// GitHub's own data. Nothing is measured in a visitor's browser.
//
//   node scripts/stats.mjs collect --repo OWNER/NAME [--prev stats.json] [--out stats.json]
//
// Environment:
//   GITHUB_TOKEN          optional, raises the API rate limit
//   STATS_TRAFFIC_TOKEN   optional, a token that may read the repository's
//                         traffic (fine-grained: Administration, read-only).
//                         The workflow's own token cannot. GitHub keeps
//                         traffic for 14 days, so every run merges the days
//                         it sees into the history that is already stored.
//   YOSHIDA_STATS_URL     optional, the /api/stats address of a self-hosted
//                         instance; its public stats are copied in as they are.
//
// .github/workflows/stats.yml runs this once a day and keeps the result on
// the `stats` branch. No dependencies.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const VERSION = 1;
/** Days of history that are kept (about three years). */
export const MAX_DAYS = 1100;
/** Largest instance document that is copied in, in bytes of JSON. */
export const MAX_INSTANCE_BYTES = 16384;

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const count = (v) => (Number.isFinite(v) && v >= 0 ? Math.floor(v) : 0);

/** Sorted by date, one entry per date (the later entry wins), newest `max` kept. */
function byDate(entries, max = MAX_DAYS) {
	const days = new Map();
	for (const e of entries) {
		if (e && typeof e === 'object' && DAY.test(e.date)) days.set(e.date, e);
	}
	return [...days.values()].sort((a, b) => (a.date < b.date ? -1 : 1)).slice(-max);
}

/**
 * What a release file is, from its name alone (nothing is measured):
 *   kind    `desktop` (an installer of the desktop app), `bundle` (the release
 *           zip with the CLI, the server and the web editor) or `other`
 *   system  `windows`, `linux` or `macos` for a desktop installer, else null
 *   format  the file type, e.g. `exe`, `appimage`, `deb`, `rpm`, `dmg`, `zip`
 * Signatures and checksums (`.sig`, `.sha256`, `latest.json`) are `meta`: they
 * are fetched by the updater, not by people, so they stay out of the breakdowns.
 */
export function classifyAsset(name) {
	const n = String(name).toLowerCase();
	if (/\.(sig|sha256|sha512|asc|json|yml|yaml|txt)$/.test(n)) return { kind: 'meta', system: null, format: 'meta' };
	if (/\.msi$/.test(n)) return { kind: 'desktop', system: 'windows', format: 'msi' };
	if (/(-setup)?\.exe$/.test(n)) return { kind: 'desktop', system: 'windows', format: 'exe' };
	if (/\.appimage$/.test(n)) return { kind: 'desktop', system: 'linux', format: 'appimage' };
	if (/\.deb$/.test(n)) return { kind: 'desktop', system: 'linux', format: 'deb' };
	if (/\.rpm$/.test(n)) return { kind: 'desktop', system: 'linux', format: 'rpm' };
	if (/\.dmg$/.test(n) || /\.app\.tar\.gz$/.test(n)) return { kind: 'desktop', system: 'macos', format: 'dmg' };
	if (/\.zip$/.test(n)) return { kind: 'bundle', system: null, format: 'zip' };
	return { kind: 'other', system: null, format: 'other' };
}

/**
 * Downloads added up by option, from a list of summarized releases. Only
 * people's downloads count: `meta` files are skipped. `kinds`, `systems` and
 * `formats` are maps of name to count; `systems` covers desktop installers.
 */
export function downloadBreakdown(releases) {
	const out = { kinds: {}, systems: {}, formats: {} };
	const add = (map, key, n) => {
		if (key) map[key] = (map[key] ?? 0) + n;
	};
	for (const r of releases) {
		for (const a of r.assets ?? []) {
			const c = a.kind ? a : { ...a, ...classifyAsset(a.name) };
			if (c.kind === 'meta') continue;
			const n = count(a.downloads);
			add(out.kinds, c.kind, n);
			add(out.systems, c.system, n);
			add(out.formats, c.format, n);
		}
	}
	return out;
}

/** Total downloads of every asset of every release. */
export function totalDownloads(releases) {
	return releases.reduce((sum, r) => sum + count(r.downloads), 0);
}

/** GitHub's release objects, reduced to what the page shows. Drafts are left out. */
export function summarizeReleases(raw) {
	return (Array.isArray(raw) ? raw : [])
		.filter((r) => r && !r.draft && typeof r.tag_name === 'string')
		.map((r) => {
			const assets = (r.assets ?? []).map((a) => {
				const { kind, system, format } = classifyAsset(a.name);
				const asset = { name: String(a.name), downloads: count(a.download_count), kind, format };
				if (system) asset.system = system;
				return asset;
			});
			return {
				tag: r.tag_name,
				published_at: r.published_at ?? null,
				prerelease: Boolean(r.prerelease),
				url: r.html_url ?? null,
				downloads: assets.reduce((sum, a) => sum + a.downloads, 0),
				assets,
			};
		});
}

/** The two traffic answers (views and clones, per day) as one list of days. */
export function trafficDays(views, clones) {
	const days = new Map();
	const day = (timestamp) => {
		const date = String(timestamp).slice(0, 10);
		if (!DAY.test(date)) return null;
		if (!days.has(date)) days.set(date, { date, views: 0, visitors: 0, clones: 0, cloners: 0 });
		return days.get(date);
	};
	for (const v of views?.views ?? []) {
		const d = day(v.timestamp);
		if (d) Object.assign(d, { views: count(v.count), visitors: count(v.uniques) });
	}
	for (const c of clones?.clones ?? []) {
		const d = day(c.timestamp);
		if (d) Object.assign(d, { clones: count(c.count), cloners: count(c.uniques) });
	}
	return byDate([...days.values()]);
}

/**
 * The next stats document: today's numbers plus the stored history.
 *
 * `prev` is the stored document (or anything else, for the first run).
 * `snapshot` is what was fetched now: { repo, now, releases, traffic?, instance? }.
 * A day that is fetched again replaces the stored one, because the current
 * day is still growing; days GitHub no longer reports are kept.
 */
export function mergeStats(prev, snapshot, at = new Date()) {
	const old = prev && typeof prev === 'object' && prev.version === VERSION ? prev : {};
	const today = at.toISOString().slice(0, 10);
	const now = snapshot.now;
	const history = byDate([
		...(Array.isArray(old.history) ? old.history : []),
		{ date: today, stars: now.stars, forks: now.forks, downloads: now.downloads, ...(now.downloads_by && { kinds: now.downloads_by.kinds, systems: now.downloads_by.systems }) },
	]);
	const doc = {
		version: VERSION,
		repo: snapshot.repo,
		generated_at: at.toISOString(),
		now,
		releases: snapshot.releases,
		history,
	};
	// Without a traffic token the stored days stay as they are.
	const traffic = byDate([...(Array.isArray(old.traffic) ? old.traffic : []), ...(snapshot.traffic ?? [])]);
	if (traffic.length) doc.traffic = traffic;
	// An instance that could not be reached keeps its last answer.
	const instance = snapshot.instance ?? old.instance;
	if (instance) doc.instance = instance;
	return doc;
}

/** The number of the last page in a Link header, for counting with per_page=1. */
export function lastPage(link) {
	const m = /[?&]page=(\d+)[^>]*>;\s*rel="last"/.exec(link ?? '');
	return m ? Number(m[1]) : null;
}

// --- fetching ----------------------------------------------------------------

const API = 'https://api.github.com';

async function github(path, token) {
	const headers = { accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'user-agent': 'yoshida-stats' };
	if (token) headers.authorization = `Bearer ${token}`;
	const res = await fetch(API + path, { headers });
	if (!res.ok) throw new Error(`GET ${path}: ${res.status} ${res.statusText}`);
	return { body: await res.json(), link: res.headers.get('link') };
}

async function collect(repo, env) {
	const token = env.GITHUB_TOKEN || env.GH_TOKEN || '';
	const base = `/repos/${repo}`;
	const info = (await github(base, token)).body;

	const rawReleases = [];
	for (let page = 1; page <= 10; page++) {
		const { body } = await github(`${base}/releases?per_page=100&page=${page}`, token);
		rawReleases.push(...body);
		if (body.length < 100) break;
	}
	const releases = summarizeReleases(rawReleases);

	// One contributor per page: the last page number is the count.
	const people = await github(`${base}/contributors?per_page=1&anon=1`, token);
	const contributors = lastPage(people.link) ?? people.body.length;

	const latest = releases.find((r) => !r.prerelease) ?? releases[0] ?? null;
	const snapshot = {
		repo,
		now: {
			stars: count(info.stargazers_count),
			forks: count(info.forks_count),
			watchers: count(info.subscribers_count),
			contributors: count(contributors),
			releases: releases.length,
			downloads: totalDownloads(releases),
			downloads_by: downloadBreakdown(releases),
			latest_release: latest && { tag: latest.tag, published_at: latest.published_at, url: latest.url },
		},
		releases,
	};

	// Traffic and the instance are extras: a failure is reported and the rest is kept.
	if (env.STATS_TRAFFIC_TOKEN) {
		try {
			const [views, clones] = await Promise.all([
				github(`${base}/traffic/views?per=day`, env.STATS_TRAFFIC_TOKEN),
				github(`${base}/traffic/clones?per=day`, env.STATS_TRAFFIC_TOKEN),
			]);
			snapshot.traffic = trafficDays(views.body, clones.body);
		} catch (err) {
			console.warn(`traffic skipped: ${err.message}`);
		}
	}
	if (env.YOSHIDA_STATS_URL) {
		try {
			const res = await fetch(env.YOSHIDA_STATS_URL, { headers: { accept: 'application/json' } });
			if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
			const text = await res.text();
			if (text.length > MAX_INSTANCE_BYTES) throw new Error('answer is too large');
			const stats = JSON.parse(text);
			if (!stats || typeof stats !== 'object' || Array.isArray(stats)) throw new Error('answer is not a JSON object');
			snapshot.instance = { host: new URL(env.YOSHIDA_STATS_URL).host, fetched_at: new Date().toISOString(), stats };
		} catch (err) {
			console.warn(`instance stats skipped: ${err.message}`);
		}
	}
	return snapshot;
}

function option(args, name) {
	const i = args.indexOf(name);
	return i >= 0 ? args[i + 1] : undefined;
}

async function main(args) {
	const repo = option(args, '--repo') ?? process.env.GITHUB_REPOSITORY;
	if (args[0] !== 'collect' || !repo || !/^[\w.-]+\/[\w.-]+$/.test(repo)) {
		console.error('usage: node scripts/stats.mjs collect --repo OWNER/NAME [--prev stats.json] [--out stats.json]');
		process.exit(2);
	}
	const prevFile = option(args, '--prev');
	let prev = null;
	if (prevFile && existsSync(prevFile)) {
		try {
			prev = JSON.parse(readFileSync(prevFile, 'utf8'));
		} catch (err) {
			// Starting over silently would drop years of history.
			console.error(`${prevFile} is not valid JSON (${err.message}); fix or remove it`);
			process.exit(1);
		}
	}
	const doc = mergeStats(prev, await collect(repo, process.env));
	const text = `${JSON.stringify(doc, null, '\t')}\n`;
	const out = option(args, '--out');
	if (out) writeFileSync(out, text);
	else process.stdout.write(text);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
	main(process.argv.slice(2)).catch((err) => {
		console.error(err.message);
		process.exit(1);
	});
}
