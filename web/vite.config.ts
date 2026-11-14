import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

// base './' lets the built site run from any sub-path (static hosting) and
// from the yoshida server.
export default defineConfig({
	base: "./",
	// "dev" for a preview build (the same variable stamps the WASM core). The
	// dev preview is served from the same origin as the release editor, so it
	// keeps its saved projects in a store of its own.
	define: {
		"import.meta.env.VITE_CHANNEL": JSON.stringify(
			process.env.YOSHIDA_CHANNEL ?? "",
		),
	},
	plugins: [svelte()],
	worker: { format: "es" },
	server: {
		proxy: { "/api": "http://localhost:8080" },
	},
});
