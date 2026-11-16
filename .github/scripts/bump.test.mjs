// node --test .github/scripts/bump.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compare, levelOf, parseVersion, plan, summary } from './bump.mjs';

const pr = (number, title, labels = []) => ({ number, title, labels });

test('levelOf reads the conventional title', () => {
	assert.equal(levelOf('feat(web): add a ruler'), 'minor');
	assert.equal(levelOf('fix: keep the selection'), 'patch');
	assert.equal(levelOf('perf(render): faster'), 'patch');
	assert.equal(levelOf('docs: update the landing page'), 'none');
	assert.equal(levelOf('chore: bump deps'), 'none');
	assert.equal(levelOf('feat(core)!: rename a field'), 'breaking');
	assert.equal(levelOf('fix: x', ['breaking-change']), 'breaking');
	assert.equal(levelOf('feat: x', ['skip-changelog']), 'none');
	assert.equal(levelOf('Something without a type'), 'none');
});

test('compare orders versions and puts a pre-release before its release', () => {
	assert.ok(compare(parseVersion('0.8.0'), parseVersion('0.7.9')) > 0);
	assert.ok(compare(parseVersion('0.8.0-rc.1'), parseVersion('0.8.0')) < 0);
	assert.equal(compare(parseVersion('v1.0.0'), parseVersion('1.0.0')), 0);
});

test('one minor bump however many features', () => {
	const p = plan({ base: '0.7.2', current: '0.7.2', prs: [pr(1, 'feat: a'), pr(2, 'feat: b'), pr(3, 'fix: c')] });
	assert.deepEqual([p.changed, p.version], [true, '0.8.0']);
});

test('a fix alone is a patch bump', () => {
	const p = plan({ base: '0.7.2', current: '0.7.2', prs: [pr(1, 'fix: a'), pr(2, 'docs: b')] });
	assert.deepEqual([p.changed, p.version], [true, '0.7.3']);
});

test('docs and chores ask for no release', () => {
	const p = plan({ base: '0.7.2', current: '0.7.2', prs: [pr(1, 'docs: a'), pr(2, 'chore: b')] });
	assert.equal(p.changed, false);
});

test('a version already bumped by hand is left alone', () => {
	const p = plan({ base: '0.7.2', current: '0.8.0', prs: [pr(1, 'feat: a'), pr(2, 'fix: b')] });
	assert.deepEqual([p.changed, p.version], [false, '0.8.0']);
});

test('a patch bump is raised when a feature arrives later', () => {
	const p = plan({ base: '0.7.2', current: '0.7.3', prs: [pr(1, 'fix: a'), pr(2, 'feat: b')] });
	assert.deepEqual([p.changed, p.version], [true, '0.8.0']);
});

test('a major bump by hand stays', () => {
	const p = plan({ base: '0.7.2', current: '1.0.0', prs: [pr(1, 'feat: a')] });
	assert.deepEqual([p.changed, p.version], [false, '1.0.0']);
});

test('a breaking change counts as minor and is reported, never major', () => {
	const p = plan({ base: '1.2.3', current: '1.2.3', prs: [pr(7, 'feat!: new format')] });
	assert.deepEqual([p.changed, p.version, p.breaking], [true, '1.3.0', [7]]);
	assert.match(summary(p, '1.2.3'), /node scripts\/version\.mjs major/);
});

test('a pre-release version is not touched', () => {
	const p = plan({ base: '0.7.2', current: '0.8.0-rc.1', prs: [pr(1, 'feat: a')] });
	assert.equal(p.changed, false);
});
