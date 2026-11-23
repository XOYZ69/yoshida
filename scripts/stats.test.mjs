// Tests for scripts/stats.mjs: node --test scripts/stats.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MAX_DAYS, VERSION, classifyAsset, downloadBreakdown, lastPage, mergeStats, summarizeReleases, totalDownloads, trafficDays } from './stats.mjs';

const snapshot = (over = {}) => ({
	repo: 'o/r',
	now: { stars: 5, forks: 1, watchers: 2, contributors: 3, releases: 1, downloads: 40, latest_release: null },
	releases: [],
	...over,
});

test('first run starts the history with today', () => {
	const doc = mergeStats(null, snapshot(), new Date('2026-11-15T05:17:00Z'));
	assert.equal(doc.version, VERSION);
	assert.equal(doc.generated_at, '2026-11-15T05:17:00.000Z');
	assert.deepEqual(doc.history, [{ date: '2026-11-15', stars: 5, forks: 1, downloads: 40 }]);
	assert.equal('traffic' in doc, false);
	assert.equal('instance' in doc, false);
});

test('a second run on the same day replaces that day', () => {
	const first = mergeStats(null, snapshot(), new Date('2026-11-15T05:00:00Z'));
	const again = mergeStats(first, snapshot({ now: { ...snapshot().now, stars: 9 } }), new Date('2026-11-15T20:00:00Z'));
	assert.equal(again.history.length, 1);
	assert.equal(again.history[0].stars, 9);
});

test('history is sorted, keeps old days and is capped', () => {
	const prev = {
		version: VERSION,
		history: [
			{ date: '2026-11-14', stars: 4, forks: 1, downloads: 30 },
			{ date: '2026-11-12', stars: 3, forks: 0, downloads: 10 },
			{ date: 'nonsense', stars: 1 },
			null,
		],
	};
	const doc = mergeStats(prev, snapshot(), new Date('2026-11-15T00:00:00Z'));
	assert.deepEqual(doc.history.map((h) => h.date), ['2026-11-12', '2026-11-14', '2026-11-15']);

	const many = [];
	for (let i = 0; i < MAX_DAYS + 50; i++) {
		many.push({ date: new Date(Date.UTC(2020, 0, 1 + i)).toISOString().slice(0, 10), stars: i, forks: 0, downloads: 0 });
	}
	const capped = mergeStats({ version: VERSION, history: many }, snapshot(), new Date('2026-11-15T00:00:00Z'));
	assert.equal(capped.history.length, MAX_DAYS);
	assert.equal(capped.history.at(-1).date, '2026-11-15');
});

test('a document of another version is not merged', () => {
	const doc = mergeStats({ version: 99, history: [{ date: '2020-01-01', stars: 1 }] }, snapshot(), new Date('2026-11-15T00:00:00Z'));
	assert.equal(doc.history.length, 1);
});

test('traffic days accumulate past the 14 days GitHub keeps', () => {
	const prev = {
		version: VERSION,
		history: [],
		traffic: [
			{ date: '2026-10-01', views: 7, visitors: 3, clones: 1, cloners: 1 },
			{ date: '2026-11-14', views: 2, visitors: 1, clones: 0, cloners: 0 },
		],
	};
	const fresh = [
		{ date: '2026-11-14', views: 12, visitors: 5, clones: 2, cloners: 2 },
		{ date: '2026-11-15', views: 1, visitors: 1, clones: 0, cloners: 0 },
	];
	const doc = mergeStats(prev, snapshot({ traffic: fresh }), new Date('2026-11-15T00:00:00Z'));
	assert.deepEqual(doc.traffic.map((d) => [d.date, d.views]), [['2026-10-01', 7], ['2026-11-14', 12], ['2026-11-15', 1]]);

	// A run without the traffic token keeps what is stored.
	const kept = mergeStats(prev, snapshot(), new Date('2026-11-16T00:00:00Z'));
	assert.equal(kept.traffic.length, 2);
});

test('an unreachable instance keeps its last answer', () => {
	const instance = { host: 'cards.example', fetched_at: '2026-11-14T00:00:00Z', stats: { sessions: 4 } };
	const doc = mergeStats({ version: VERSION, history: [], instance }, snapshot(), new Date('2026-11-15T00:00:00Z'));
	assert.deepEqual(doc.instance, instance);
	const newer = { ...instance, stats: { sessions: 6 } };
	assert.deepEqual(mergeStats(doc, snapshot({ instance: newer })).instance, newer);
});

test('releases: drafts are dropped and downloads are summed', () => {
	const releases = summarizeReleases([
		{ tag_name: 'v0.2.0', published_at: '2026-11-01T00:00:00Z', html_url: 'u2', assets: [{ name: 'a.zip', download_count: 4 }, { name: 'b.zip', download_count: 6 }] },
		{ tag_name: 'v0.3.0-dev', draft: true, assets: [{ name: 'c.zip', download_count: 100 }] },
		{ tag_name: 'v0.1.0', prerelease: true, assets: [{ name: 'a.zip', download_count: -3 }] },
	]);
	assert.deepEqual(releases.map((r) => [r.tag, r.downloads, r.prerelease]), [['v0.2.0', 10, false], ['v0.1.0', 0, true]]);
	assert.equal(totalDownloads(releases), 10);
	assert.deepEqual(summarizeReleases(null), []);
});

test('traffic answers are joined by day', () => {
	const days = trafficDays(
		{ views: [{ timestamp: '2026-11-14T00:00:00Z', count: 9, uniques: 4 }, { timestamp: '2026-11-13T00:00:00Z', count: 1, uniques: 1 }] },
		{ clones: [{ timestamp: '2026-11-14T00:00:00Z', count: 3, uniques: 2 }] },
	);
	assert.deepEqual(days, [
		{ date: '2026-11-13', views: 1, visitors: 1, clones: 0, cloners: 0 },
		{ date: '2026-11-14', views: 9, visitors: 4, clones: 3, cloners: 2 },
	]);
	assert.deepEqual(trafficDays(undefined, undefined), []);
});

test('the last page of a Link header is the count', () => {
	const link = '<https://api.github.com/repositories/1/contributors?per_page=1&anon=1&page=2>; rel="next", <https://api.github.com/repositories/1/contributors?per_page=1&anon=1&page=17>; rel="last"';
	assert.equal(lastPage(link), 17);
	assert.equal(lastPage(null), null);
});

test('release files are sorted into download options by name', () => {
	const c = (n) => [classifyAsset(n).kind, classifyAsset(n).system, classifyAsset(n).format];
	assert.deepEqual(c('yoshida-0.8.0.zip'), ['bundle', null, 'zip']);
	assert.deepEqual(c('yoshida-beta_0.8.0_x64-setup.exe'), ['desktop', 'windows', 'exe']);
	assert.deepEqual(c('yoshida-beta_0.8.0_amd64.AppImage'), ['desktop', 'linux', 'appimage']);
	assert.deepEqual(c('yoshida-beta_0.8.0_amd64.deb'), ['desktop', 'linux', 'deb']);
	assert.deepEqual(c('yoshida-beta-0.8.0-1.x86_64.rpm'), ['desktop', 'linux', 'rpm']);
	assert.deepEqual(c('yoshida-beta_0.8.0_aarch64.dmg'), ['desktop', 'macos', 'dmg']);
	assert.deepEqual(c('yoshida-beta_0.8.0_amd64.AppImage.sig'), ['meta', null, 'meta']);
	assert.deepEqual(c('mystery.bin'), ['other', null, 'other']);
});

test('downloads are added up by kind, system and format; meta files are skipped', () => {
	const releases = summarizeReleases([
		{ tag_name: 'v0.8.0', assets: [
			{ name: 'yoshida-0.8.0.zip', download_count: 5 },
			{ name: 'yoshida-beta_0.8.0_x64-setup.exe', download_count: 3 },
			{ name: 'yoshida-beta_0.8.0_amd64.deb', download_count: 2 },
			{ name: 'yoshida-beta_0.8.0_amd64.AppImage', download_count: 1 },
			{ name: 'latest.json', download_count: 40 },
		] },
	]);
	assert.deepEqual(downloadBreakdown(releases), {
		kinds: { bundle: 5, desktop: 6 },
		systems: { windows: 3, linux: 3 },
		formats: { zip: 5, exe: 3, deb: 2, appimage: 1 },
	});
	// Releases stored by an older run have no tags on their files: they are classified on the fly.
	assert.deepEqual(downloadBreakdown([{ assets: [{ name: 'yoshida-0.7.0.zip', downloads: 2 }] }]).kinds, { bundle: 2 });
});

test('the history keeps a per-day split of the downloads', () => {
	const now = { ...snapshot().now, downloads_by: { kinds: { desktop: 2 }, systems: { linux: 2 }, formats: { deb: 2 } } };
	const doc = mergeStats(null, snapshot({ now }), new Date('2026-11-15T00:00:00Z'));
	assert.deepEqual(doc.history[0].kinds, { desktop: 2 });
	assert.deepEqual(doc.history[0].systems, { linux: 2 });
});
