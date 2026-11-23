// Whether the editor runs inside the desktop app (Tauri), and the words that
// follow from it: the app has no "browser", and its server is the renderer
// it started itself, so there is nothing to switch.

import { tauriBridge } from "./folder/native.ts";

/** True in the desktop app, false in a browser tab. */
export const isDesktop = (): boolean => tauriBridge() !== null;

/** "this app" in the desktop app, "this browser" on the web. */
export const hostWord = (): string =>
	isDesktop() ? "this app" : "this browser";

/** What renders on the server side: "the built-in renderer" in the app, "the server" on the web. */
export const rendererWord = (): string =>
	isDesktop() ? "the built-in renderer" : "the server";
