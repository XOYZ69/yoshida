#!/usr/bin/env node
// The version bot: works out the version the next release should have from
// the pull requests merged since the last release, so minor and patch bumps
// need no hand work. Major stays manual.
//
//   bump.mjs      print the decision and write it to $GITHUB_OUTPUT
//                 (changed, version, level, breaking) and the step summary
//
// Rules (levelOf, plan):
//   - each merged PR counts by its conventional title: feat -> minor,
//     fix and perf -> patch; docs, chore, ci, build, test, style, refactor and
//     revert -> nothing. PRs with the skip-changelog label do not count.
//   - the target is the last release plus the highest level: one minor bump
//     however many features, so the version does not run away.
//   - the version only ever goes up: if build.zig.zon already holds the target
//     or more (a hand-set 0.8.0, a major bump), nothing changes.
//   - a breaking change ("!" or the breaking-change label) is never turned
//     into a major bump. It counts as a minor one and is reported, so the
//     major bump (node scripts/version.mjs major) stays a decision.
//   - a pre-release version (0.9.0-rc.1) is left alone.
//
// Env: GH_TOKEN, GITHUB_REPOSITORY, BASE_REF (default dev).
import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { generated, lastRelease, mergedPRs, parseTitle } from './release-notes.mjs';

export function parseVersion(v) {
	const m = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/.exec(v);
	if (!m) throw new Error(`not a version: ${v}`);
	return { major: +m[1], minor: +m[2], patch: +m[3], pre: m[4] ?? '' };
}

const core = (v) => `${v.major}.${v.minor}.${v.patch}`;

// Negative, zero or positive; a pre-release sorts before its release.
export function compare(a, b) {
	for (const k of ['major', 'minor', 'patch']) if (a[k] !== b[k]) return a[k] - b[k];
	if (a.pre === b.pre) return 0;
	return a.pre ? -1 : b.pre ? 1 : 0;
}

const RANK = { none: 0, patch: 1, minor: 2, breaking: 2 };

// What one PR asks for: 'breaking' | 'minor' | 'patch' | 'none'.
export function levelOf(title, labels = []) {
	if (labels.includes('skip-changelog')) return 'none';
	const t = parseTitle(title);
	if (t?.breaking || labels.includes('breaking-change')) return 'breaking';
	if (!t) return 'none';
	if (t.type === 'feat') return 'minor';
	if (t.type === 'fix' || t.type === 'perf') return 'patch';
	return 'none';
}

// base: version of the last release, current: version in build.zig.zon,
// prs: [{ number, title, labels: [name] }] merged since that release.
export function plan({ base, current, prs }) {
	const b = parseVersion(base);
	const c = parseVersion(current);
	let level = 'none';
	const breaking = [];
	for (const pr of prs) {
		const l = levelOf(pr.title, pr.labels);
		if (l === 'breaking') breaking.push(pr.number);
		if (RANK[l] > RANK[level]) level = l;
	}
	const unchanged = (reason) => ({ changed: false, version: current, level, breaking, reason });
	if (c.pre) return unchanged(`${current} is a pre-release, set by hand`);
	const target = { ...b, pre: '' };
	if (RANK[level] === 2) Object.assign(target, { minor: b.minor + 1, patch: 0 });
	else if (level === 'patch') target.patch = b.patch + 1;
	if (compare(target, c) <= 0)
		return unchanged(
			level === 'none' ? `nothing since ${base} asks for a release` : `${current} already covers a ${level} change on ${base}`,
		);
	return { changed: true, version: core(target), level, breaking, reason: `${level} change on ${base}` };
}

export function summary(p, current) {
	const lines = [p.changed ? `Version ${current} -> **${p.version}** (${p.reason}).` : `Version stays ${current}: ${p.reason}.`];
	if (p.breaking.length)
		lines.push(
			`Breaking change in ${p.breaking.map((n) => `#${n}`).join(', ')}: counted as minor. For a major release run \`node scripts/version.mjs major\` yourself.`,
		);
	return lines.join('\n\n');
}

export async function decide(extra = []) {
	const previous = await lastRelease();
	if (!previous) return null;
	const base = process.env.BASE_REF || 'dev';
	const body = (await generated('next', previous)).replace(/\.\.\.next\b/, `...${base}`);
	const prs = (await mergedPRs(body, extra)).map((pr) => ({
		number: pr.number,
		title: pr.title,
		labels: pr.labels.map((l) => l.name),
	}));
	const current = execFileSync(process.execPath, ['scripts/version.mjs'], { encoding: 'utf8' }).trim();
	return { previous, current, plan: plan({ base: previous.replace(/^v/, ''), current, prs }) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const d = await decide();
	if (!d) {
		console.log('no release yet, nothing to bump');
		process.exit(0);
	}
	const text = summary(d.plan, d.current);
	console.log(text);
	if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${text}\n`);
	if (process.env.GITHUB_OUTPUT) {
		const out = { changed: d.plan.changed, version: d.plan.version, level: d.plan.level, breaking: d.plan.breaking.join(',') };
		appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(out).map(([k, v]) => `${k}=${v}`).join('\n') + '\n');
	}
}
