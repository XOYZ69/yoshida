/// <reference lib="webworker" />
// Runs yoshida.wasm off the main thread. Messages: { id, op, ...args }.

type Exports = {
	memory: WebAssembly.Memory;
	alloc(len: number): number;
	free(ptr: number, len: number): void;
	vfs_put(
		pathPtr: number,
		pathLen: number,
		dataPtr: number,
		dataLen: number,
	): number;
	vfs_remove(pathPtr: number, pathLen: number): void;
	vfs_clear(): void;
	request(ptr: number, len: number): number;
	result_json_ptr(): number;
	result_json_len(): number;
	result_bin_ptr(): number;
	result_bin_len(): number;
};

let wasm: Exports | null = null;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
/** URLs that failed to download, so they are not retried on every render. */
const failedUrls = new Set<string>();

/** What the engine answers; ops add their own fields. */
type Reply = {
	error?: string;
	missing_urls?: string[];
	diagnostics?: unknown[];
	[key: string]: unknown;
};

type Msg = { id: number } & (
	| { op: "init"; url: string }
	| { op: "files"; files: [string, Uint8Array][] }
	| { op: "put"; path: string; data: Uint8Array }
	| { op: "remove"; path: string }
	| { op: "check" }
	| { op: "render"; args: object }
	| { op: "renderAll"; args: object; ids: string[] }
);

function withBytes<T>(bytes: Uint8Array, fn: (ptr: number) => T): T {
	const x = wasm!;
	const ptr = x.alloc(bytes.length);
	if (!ptr) throw new Error("out of memory");
	new Uint8Array(x.memory.buffer, ptr, bytes.length).set(bytes);
	try {
		return fn(ptr);
	} finally {
		x.free(ptr, bytes.length);
	}
}

function put(path: string, data: Uint8Array) {
	const p = encoder.encode(path);
	withBytes(p, (pp) =>
		withBytes(data, (dp) => wasm!.vfs_put(pp, p.length, dp, data.length)),
	);
}

function request(req: object): { json: Reply; bin: Uint8Array } {
	const x = wasm!;
	const body = encoder.encode(JSON.stringify(req));
	const rc = withBytes(body, (ptr) => x.request(ptr, body.length));
	if (rc < 0) throw new Error("the render engine ran out of memory");
	const json: Reply = JSON.parse(
		decoder.decode(
			new Uint8Array(x.memory.buffer, x.result_json_ptr(), x.result_json_len()),
		),
	);
	if (rc > 0) throw new Error(json.error ?? "request failed");
	const bin = new Uint8Array(
		x.memory.buffer,
		x.result_bin_ptr(),
		x.result_bin_len(),
	).slice();
	return { json, bin };
}

async function fetchMissing(urls: string[]): Promise<boolean> {
	let any = false;
	for (const url of urls) {
		if (failedUrls.has(url)) continue;
		try {
			const res = await fetch(url, { mode: "cors" });
			if (!res.ok) throw new Error(String(res.status));
			put(url, new Uint8Array(await res.arrayBuffer()));
			any = true;
		} catch {
			failedUrls.add(url);
		}
	}
	return any;
}

async function render(args: object) {
	let r = request({ op: "render", ...args });
	if (
		r.json.missing_urls?.length &&
		(await fetchMissing(r.json.missing_urls))
	) {
		r = request({ op: "render", ...args });
	}
	return r;
}

async function handle(
	msg: Msg,
): Promise<{ result: unknown; transfer?: Transferable[] }> {
	switch (msg.op) {
		case "init": {
			const { instance } = await WebAssembly.instantiateStreaming(
				fetch(msg.url),
				{},
			);
			wasm = instance.exports as unknown as Exports;
			return { result: request({ op: "info" }).json };
		}
		case "files": {
			wasm!.vfs_clear();
			for (const [path, data] of msg.files) put(path, data);
			return { result: null };
		}
		case "put":
			put(msg.path, msg.data);
			return { result: null };
		case "remove": {
			const p = encoder.encode(msg.path);
			withBytes(p, (pp) => wasm!.vfs_remove(pp, p.length));
			return { result: null };
		}
		case "check":
			return { result: request({ op: "check" }).json };
		case "render": {
			const r = await render(msg.args);
			return { result: { ...r.json, bin: r.bin }, transfer: [r.bin.buffer] };
		}
		case "renderAll": {
			// Renders every card of a set as PNG files for a zip.
			const out: { id: string; png: Uint8Array }[] = [];
			const diagnostics: unknown[] = [];
			for (let i = 0; i < msg.ids.length; i++) {
				const r = await render({ ...msg.args, card: i });
				diagnostics.push(...(r.json.diagnostics ?? []));
				if (r.bin.length) out.push({ id: msg.ids[i], png: r.bin });
				(self as unknown as Worker).postMessage({
					id: msg.id,
					progress: (i + 1) / msg.ids.length,
				});
			}
			return {
				result: { files: out, diagnostics },
				transfer: out.map((f) => f.png.buffer),
			};
		}
		default:
			throw new Error(`unknown op ${(msg as { op: string }).op}`);
	}
}

self.onmessage = async (e: MessageEvent) => {
	const msg: Msg = e.data;
	try {
		const { result, transfer } = await handle(msg);
		(self as unknown as Worker).postMessage(
			{ id: msg.id, ok: true, result },
			transfer ?? [],
		);
	} catch (err) {
		(self as unknown as Worker).postMessage({
			id: msg.id,
			ok: false,
			error: String((err as Error)?.message ?? err),
		});
	}
};
