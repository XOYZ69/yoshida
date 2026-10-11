#!/usr/bin/env node
// The yoshida version lives in build.zig.zon. The Zig build passes it to the
// core (CLI, server, WASM, and so the editor header); this script copies it
// to the few places that cannot read it.
//
//   node scripts/version.mjs                    print the version
//   node scripts/version.mjs 0.5.0              set it everywhere
//   node scripts/version.mjs major|minor|patch  bump it everywhere
//   node scripts/version.mjs check [--tag v0.5.0]
//                                               fail if a copy is out of date
//                                               (or the tag does not match)
//
// No dependencies; runs from any directory.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = 'build.zig.zon';
const SOURCE_RE = /(\.version\s*=\s*")([^"]*)(")/;
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

// Every copy of the version outside build.zig.zon. Each pattern has three
// groups: text before, the version, text after. `count` is how many matches
// the file must have, so a reworded line fails the check instead of being
// skipped silently.
const COPIES = [
	{ file: 'web/package.json', re: /^(\t"version": ")([^"]*)(")/m, count: 1 },
	{
		file: 'web/package-lock.json',
		re: /^(\t(?:\t\t)?"version": ")([^"]*)(")/gm,
		count: 2,
		first: 2, // the root entry and packages[""]; later ones are dependencies
	},
	{ file: 'site/content/docs/_index.md', re: /(covers version )(\S+)( of the tool)/, count: 1 },
	{ file: 'site/content/docs/limits-and-versioning.md', re: /(implemented by yoshida \*\*)([^*]+)(\*\*)/, count: 1 },
	{ file: 'site/content/docs/server-api.md', re: /(\t"version": ")([^"]*)(")/, count: 1 },
	{ file: 'site/content/docs/wasm-interface.md', re: /(\{ "version": ")([^"]*)(", "format")/, count: 1 },
];

const read = (file) => readFileSync(join(root, file), 'utf8');
const write = (file, text) => writeFileSync(join(root, file), text);

function current() {
	const m = SOURCE_RE.exec(read(SOURCE));
	if (!m) throw new Error(`${SOURCE}: no .version field`);
	return m[2];
}

// The versions a copy currently holds, in file order.
function found(copy) {
	const re = new RegExp(copy.re.source, copy.re.flags.includes('g') ? copy.re.flags : `${copy.re.flags}g`);
	return [...read(copy.file).matchAll(re)].slice(0, copy.first ?? Infinity).map((m) => m[2]);
}

function setCopy(copy, version) {
	let n = 0;
	const limit = copy.first ?? 1;
	const text = read(copy.file).replace(copy.re, (all, before, _old, after) =>
		n++ < limit ? before + version + after : all,
	);
	write(copy.file, text);
}

function bump(version, part) {
	const [major, minor, patch] = version.split('-')[0].split('.').map(Number);
	if (part === 'major') return `${major + 1}.0.0`;
	if (part === 'minor') return `${major}.${minor + 1}.0`;
	return `${major}.${minor}.${patch + 1}`;
}

function check(tag) {
	const version = current();
	const problems = [];
	for (const copy of COPIES) {
		const got = found(copy);
		if (got.length !== copy.count)
			problems.push(`${copy.file}: expected ${copy.count} version line(s), found ${got.length}; update COPIES in scripts/version.mjs`);
		for (const v of got) if (v !== version) problems.push(`${copy.file}: ${v}, expected ${version}`);
	}
	if (tag !== undefined && tag.replace(/^v/, '') !== version)
		problems.push(`tag ${tag} does not match version ${version} in ${SOURCE}`);
	if (problems.length) {
		for (const p of problems) console.error(`version drift: ${p}`);
		console.error('Fix with: node scripts/version.mjs <version>');
		process.exit(1);
	}
	console.log(`version ${version}: ${COPIES.length} copies in sync${tag ? `, tag ${tag} matches` : ''}`);
}

function set(arg) {
	const old = current();
	const version = ['major', 'minor', 'patch'].includes(arg) ? bump(old, arg) : arg;
	if (!SEMVER.test(version)) {
		console.error(`not a version: ${arg} (use X.Y.Z, X.Y.Z-pre, major, minor or patch)`);
		process.exit(2);
	}
	write(SOURCE, read(SOURCE).replace(SOURCE_RE, `$1${version}$3`));
	for (const copy of COPIES) setCopy(copy, version);
	console.log(`${old} -> ${version}: ${SOURCE} and ${COPIES.length} copies updated`);

	// Anything else that still names the old version is worth a look, but may
	// be on purpose (release notes, a changelog), so it is only listed.
	if (old !== version) {
		try {
			const rest = execFileSync('git', ['grep', '-nF', old, '--', '.', ':!*package-lock.json'], {
				cwd: root,
				encoding: 'utf8',
			});
			console.log(`\nStill mentions ${old} (left unchanged):\n${rest}`);
		} catch {
			// git grep exits 1 when nothing matches, or git is not available.
		}
	}
	console.log(`Next: commit, merge to master, then publish a GitHub release tagged v${version}.`);
}

const [cmd, ...rest] = process.argv.slice(2);
if (cmd === undefined) console.log(current());
else if (cmd === 'check') {
	const i = rest.indexOf('--tag');
	check(i === -1 ? undefined : rest[i + 1] ?? '');
} else if (cmd === '-h' || cmd === '--help') {
	console.log('usage: version.mjs [X.Y.Z | major | minor | patch | check [--tag vX.Y.Z]]');
} else set(cmd);
