#!/usr/bin/env node
// Writes the documentation for AI agents and other tools that read plain
// text: llms.txt (a short index, https://llmstxt.org) and llms-full.txt (one
// compact reference for the whole file format).
//
//   node scripts/llms.mjs          write the files
//   node scripts/llms.mjs check    fail if a committed file is out of date
//
// Nothing in the output is written by hand twice: it is put together from
//   schema/*.schema.json                   file formats, layer types, fields
//   web/src/lib/expr/catalog.ts            functions, names, operators
//   src/cli/main.zig                       the command line help
//   site/content/docs/diagnostics.md       the diagnostic codes
//   site/data/docs-nav.toml + front matter the docs pages
//   scripts/llms-guide.md                  the short hand-written guide
//   examples/forge                         a complete small project
// so `check` in CI fails when one of them changes without the reference.
//
// The files are written to the repository root (for agents working in a
// checkout, and copied into the release bundle) and to site/static (served
// as /llms.txt and /llms-full.txt on the website). No dependencies.
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as nodeModule from 'node:module';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => readFileSync(join(root, file), 'utf8');
const json = (file) => JSON.parse(read(file));

const SITE = /^base_url\s*=\s*"([^"]+)"/m.exec(read('site/config.toml'))[1].replace(/\/$/, '');
const REPO = 'https://github.com/XOYZ69/yoshida';
const OUTPUTS = ['llms.txt', 'llms-full.txt'];
const TARGETS = ['', 'site/static/'];

// --- sources ---------------------------------------------------------------

/** The editor's catalog of the expression language, a TypeScript module without imports. */
async function catalog() {
	const file = 'web/src/lib/expr/catalog.ts';
	if (typeof nodeModule.stripTypeScriptTypes === 'function') {
		const emit = process.emitWarning;
		process.emitWarning = () => {}; // the API is marked experimental
		let js;
		try {
			js = nodeModule.stripTypeScriptTypes(read(file));
		} finally {
			process.emitWarning = emit;
		}
		return import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
	}
	// Older Node: works when started with --experimental-strip-types.
	return import(pathToFileURL(join(root, file)).href);
}

/** The usage text of the CLI: the multiline string `usage` in main.zig. */
function cliUsage() {
	const lines = read('src/cli/main.zig').split('\n');
	const start = lines.findIndex((l) => /^const usage\s*=/.test(l));
	if (start < 0) throw new Error('src/cli/main.zig: no `const usage`');
	const out = [];
	for (const l of lines.slice(start + 1)) {
		const m = /^\s*\\\\(.*)$/.exec(l);
		if (!m) break;
		out.push(m[1]);
	}
	// The first line is "yoshida {s} (format {d})", filled in at run time.
	return out.slice(1).join('\n').trim();
}

/** `| 3002 | error | Unknown name |` rows of the diagnostics page. */
function diagnostics() {
	const rows = [];
	for (const l of read('site/content/docs/diagnostics.md').split('\n')) {
		const m = /^\| (\d{4}) \| (\w+) \| (.*?) \|\s*$/.exec(l);
		if (m) rows.push({ code: m[1], severity: m[2], text: plain(m[3]) });
	}
	if (rows.length < 20) throw new Error('diagnostics.md: the code tables were not found');
	return rows;
}

/** Zola front matter: title and description of a docs page. */
function frontMatter(file) {
	const m = /^\+\+\+\n([\s\S]*?)\n\+\+\+/.exec(read(file));
	const get = (key) => new RegExp(`^${key}\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"`, 'm').exec(m?.[1] ?? '')?.[1]?.replace(/\\"/g, '"');
	return { title: get('title'), description: get('description') };
}

/** Docs pages in sidebar order, by group. */
function docsNav() {
	const groups = [];
	let item = null;
	for (const l of read('site/data/docs-nav.toml').split('\n')) {
		const kv = /^(\w+)\s*=\s*"(.*)"$/.exec(l.trim());
		if (l.startsWith('[[group]]')) groups.push({ title: '', items: [] });
		else if (/^\[\[group\.item(\.child)?\]\]/.test(l)) {
			item = { child: l.includes('.child') };
			groups.at(-1).items.push(item);
		} else if (kv && item) item[kv[1]] = kv[2];
		else if (kv) groups.at(-1)[kv[1]] = kv[2];
		if (l.startsWith('[[group]]')) item = null;
	}
	return groups;
}

const pageUrl = (path) => `${SITE}/${path.replace(/\.md$/, '/').replace(/\/_index\/$/, '/')}`;

// --- formatting ------------------------------------------------------------

/** Docs Markdown as plain reference text: Zola links become their label. */
function plain(text) {
	return text.replace(/\[([^\]]+)\]\(@\/[^)]*\)/g, '$1').replace(/\\\|/g, '|');
}

/** A JSON Schema node as a short type: "number|expr", "'row'|'column'", "{ x, y }". */
function kind(node) {
	if (node === true || node === undefined) return 'any';
	if (node.const !== undefined) return JSON.stringify(node.const);
	if (node.enum) return node.enum.map((v) => JSON.stringify(v)).join(' | ');
	if (node.anyOf || node.oneOf) return [...new Set((node.anyOf ?? node.oneOf).map(kind))].join(' | ');
	if (node.$ref) return node.$ref.split('/').at(-1);
	const types = [].concat(node.type ?? []);
	if (types.includes('object')) {
		if (node.properties) return `{ ${Object.keys(node.properties).join(', ')} }`;
		if (typeof node.additionalProperties === 'object') return `{ name: ${kind(node.additionalProperties)} }`;
		return 'object';
	}
	if (types.includes('array')) return `[${node.items ? kind(node.items) : 'any'}, ...]`;
	// A field that takes a JSON number or a string is a number or an expression.
	if (types.includes('string') && (types.includes('number') || types.includes('boolean')))
		return `${types.filter((t) => t !== 'string').join('|')}|expr`;
	return types.join('|') || 'any';
}

/** One line per field, with nested object fields indented below it. */
function fields(props, required = [], depth = 0, seen = new Set()) {
	const out = [];
	for (const [name, node] of Object.entries(props)) {
		if (node === true) continue;
		const req = required.includes(name) ? ', required' : '';
		// The schema's stock descriptions say what the short type already says.
		let type = kind(node);
		let text = (node.description ?? '').replace(/, see https:\S+/, '');
		if (/^Color literal/.test(text)) [type, text] = ['color|expr', ''];
		else if (/^Text with \{expression\} placeholders$/.test(text)) [type, text] = ['template', ''];
		else if (/^(Number|Boolean) literal or expression$/.test(text)) text = '';
		out.push(`${'  '.repeat(depth)}- \`${name}\` (${type}${req})${text ? `: ${text}` : ''}`);
		const inner = node.properties ?? node.items?.properties;
		if (inner && depth < 2 && !seen.has(node)) {
			seen.add(node);
			out.push(...fields(inner, node.required ?? node.items?.required, depth + 1, seen));
		}
	}
	return out;
}

const signature = (f, args = f.args) =>
	`${f.name}(${args.map((a) => (a.rest ? '…' : a.optional !== undefined ? `[${a.name}]` : a.name)).join(', ')})`;

// --- llms-full.txt ---------------------------------------------------------

async function full() {
	const design = json('schema/design.schema.json');
	const layer = design.$defs.layer;
	const cat = await catalog();
	const version = /\.version\s*=\s*"([^"]*)"/.exec(read('build.zig.zon'))[1];
	const out = [];
	const p = (...lines) => out.push(...lines);

	p(
		'# yoshida reference',
		'',
		`> The whole yoshida file format on one page, for AI agents and other tools: project files, params, layer types and their fields, the expression language with every function, the command line and the diagnostic codes. Generated from the JSON Schemas and the sources of yoshida ${version} by scripts/llms.mjs; do not edit by hand.`,
		'',
		`Website and full docs: ${SITE}/docs/ · Source: ${REPO} · Short index: ${SITE}/llms.txt`,
		'',
		read('scripts/llms-guide.md').trim(),
		'',
	);

	p('## Command line', '', '```txt', cliUsage(), '```', '');

	p('## Project files', '');
	for (const [file, title] of [
		['schema/yoshida.schema.json', '`yoshida.json`, the optional manifest'],
		['schema/cards.schema.json', '`*.cards.json`, card data'],
		['schema/component.schema.json', '`*.component.json`, layers shared through a group\'s `include`'],
	]) {
		const s = json(file);
		p(`### ${title}`, '', ...(s.description ? [s.description, ''] : []), ...fields(s.properties, s.required), '');
	}
	p('### `*.design.json`, a design', '', ...fields(Object.fromEntries(Object.entries(design.properties).filter(([k]) => k !== 'layers')), design.required));
	p('- `layers` ([layer, ...], required): drawn in array order, the first is at the bottom', '');

	p('## Params', '', 'Each entry of a design\'s `params` declares one value a card can set. Card data is checked against it.', '', ...fields(design.$defs.param.properties, design.$defs.param.required), '');

	// Fields every drawable layer type has are listed once; a type lists the rest.
	const types = layer.allOf.map((rule) => ({ type: rule.if.properties.type.const, props: rule.then.properties, required: rule.then.required ?? [] }));
	const resolve = (name, node) => (node === true ? layer.properties[name] : node);
	const drawable = types.filter((t) => !['group', 'divider'].includes(t.type));
	const common = Object.keys(drawable[0].props).filter((name) => drawable.every((t) => name in t.props && kind(resolve(name, t.props[name])) === kind(resolve(name, drawable[0].props[name]))));
	p('## Layers', '', `Layer types: ${types.map((t) => `\`${t.type}\``).join(', ')}. A field marked \`|expr\` takes a JSON value or an expression in a string.`, '');
	p('### Fields of every layer type except `group` and `divider`', '', ...fields(Object.fromEntries(common.map((n) => [n, resolve(n, drawable[0].props[n])])), layer.required), '');
	for (const t of types) {
		const own = Object.entries(t.props).filter(([name]) => !common.includes(name) || ['group', 'divider'].includes(t.type));
		p(`### \`${t.type}\``, '', ...fields(Object.fromEntries(own.map(([n, node]) => [n, resolve(n, node)])), [...layer.required, ...t.required]), '');
		const readable = cat.LAYER_FIELDS[t.type];
		if (readable?.length) p(`Readable as \`@id.<field>\`: ${readable.map((f) => `\`${f.name}\``).join(', ')}.`, '');
	}

	p('## Expressions', '');
	for (const sheet of cat.CHEATSHEET) p(`### ${sheet.title}`, '', ...sheet.rows.map(([a, b]) => `- \`${a}\`: ${b}`), '');
	p('### Keywords', '', ...cat.KEYWORDS.map((k) => `- \`${k.name}\`: ${k.doc}`), '');
	p('### Built-in names', '');
	for (const [name, b] of Object.entries(cat.BUILTINS)) for (const f of b.fields) p(`- \`${name}.${f.name}\` (${f.type}): ${f.doc}`);
	for (const c of cat.CONSTANTS) p(`- \`${c.name}\` (${c.type}): ${c.doc}`);
	p('', '### Text templates', '', 'Fields such as a text layer\'s `text` and an image\'s `src` are templates, not expressions:', '', ...cat.TEMPLATE_HELP.map(([a, b]) => `- \`${a}\`: ${b}`), '');
	p('### Functions', '');
	for (const f of cat.FUNCTIONS) {
		const alt = f.alt ? ` or \`${signature(f, f.alt)}\`` : '';
		p(`- \`${signature(f)}\`${alt} -> ${f.ret}. ${f.doc} Example: \`${f.example}\``);
	}
	p('');

	p('## Diagnostic codes', '', 'Reported as `file:line:column: severity[code]: message`; `yoshida check --format json` gives them as JSON. Codes are stable.', '');
	for (const d of diagnostics()) p(`- ${d.code} ${d.severity}: ${d.text}`);
	p('');

	p('## A complete small project', '', 'The files of `examples/forge` (fonts, icons and art left out). Render it with `yoshida render examples/forge --out out`.', '');
	const forge = ['yoshida.json', 'designs/project.design.json', 'components/effect-row.component.json', 'cards/projects.cards.json'];
	for (const f of forge) p(`\`${f}\`:`, '', '```json', read(`examples/forge/${f}`).trim(), '```', '');

	return `${out.join('\n').trim()}\n`;
}

// --- llms.txt --------------------------------------------------------------

function index() {
	const out = [
		'# yoshida',
		'',
		'> yoshida makes cards (playing cards, game cards, labels, boards) from JSON: a design of layers with formulas, filled from card data in JSON or CSV, rendered to PNG, SVG or PDF by a command line tool, a browser editor or a small server.',
		'',
		`To write or change yoshida files, read the reference first: it is one page with every field, function and command line option, generated from the JSON Schemas so it matches the tool. Validate what you write with \`yoshida check <project>\` and tidy it with \`yoshida fmt <project>\`.`,
		'',
		'## Reference',
		'',
		`- [yoshida reference](${SITE}/llms-full.txt): the whole file format, the expression language, the command line and the diagnostic codes on one page`,
		`- [design.schema.json](${REPO}/blob/master/schema/design.schema.json): JSON Schema of a design file`,
		`- [cards.schema.json](${REPO}/blob/master/schema/cards.schema.json): JSON Schema of a card file`,
		`- [component.schema.json](${REPO}/blob/master/schema/component.schema.json): JSON Schema of a shared component`,
		`- [yoshida.schema.json](${REPO}/blob/master/schema/yoshida.schema.json): JSON Schema of the project manifest`,
		'',
	];
	for (const group of docsNav()) {
		// The builder pages describe the visual editor's panels; they are of little use for writing files.
		out.push(`## ${/builder|editor/i.test(group.title) ? 'Optional' : `Docs: ${group.title}`}`, '');
		for (const item of group.items) {
			const fm = frontMatter(`site/content/${item.path}`);
			out.push(`- [${item.title}](${pageUrl(item.path)})${fm.description ? `: ${fm.description}` : ''}`);
		}
		out.push('');
	}
	out.push('## Examples', '');
	for (const name of readdirSync(join(root, 'examples')).sort()) {
		const manifest = `examples/${name}/yoshida.json`;
		const readme = `examples/${name}/README.md`;
		if (!existsSync(join(root, readme))) continue;
		const note = existsSync(join(root, manifest)) ? json(manifest).note : undefined;
		const first = read(readme).split('\n').find((l) => l.trim() && !l.startsWith('#'));
		out.push(`- [${name}](${REPO}/tree/master/examples/${name}): ${note ?? first}`);
	}
	return `${out.join('\n').trim()}\n`;
}

// --- main ------------------------------------------------------------------

const built = { 'llms.txt': index(), 'llms-full.txt': await full() };
const check = process.argv[2] === 'check';
const stale = [];
for (const dir of TARGETS)
	for (const name of OUTPUTS) {
		const file = dir + name;
		if (check) {
			if (!existsSync(join(root, file)) || read(file) !== built[name]) stale.push(file);
		} else writeFileSync(join(root, file), built[name]);
	}
if (stale.length) {
	for (const f of stale) console.error(`out of date: ${f}`);
	console.error('Fix with: node scripts/llms.mjs');
	process.exit(1);
}
const size = (name) => `${name} ${(built[name].length / 1024).toFixed(1)} kB`;
console.log(`${check ? 'up to date' : 'wrote'}: ${OUTPUTS.map(size).join(', ')} (repository root and site/static)`);
