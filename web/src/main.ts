import { mount } from "svelte";
import App from "./App.svelte";
import { loadExprCore } from "./lib/expr/core";
import "./app.css";

// The expression core is needed by every expression field, so it loads
// first. If it fails, the app still starts: expressions are just not
// highlighted or checked.
try {
	await loadExprCore();
} catch (e) {
	console.error(
		"Could not load expr.wasm; expressions will not be highlighted",
		e,
	);
}

export default mount(App, { target: document.getElementById("app")! });
