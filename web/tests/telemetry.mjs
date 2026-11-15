// Rules of the optional telemetry (src/lib/telemetry/core.ts): which level is
// in force, that a server can only lower it, that nothing is sent before the
// notice, which events are valid, and the shape of the request bodies.
//
//   node --experimental-strip-types tests/telemetry.mjs
import {
	effectiveLevel,
	eventsBody,
	forcedLevel,
	needsNotice,
	NOTICE_VERSION,
	parseLog,
	parsePrefs,
	pingBody,
	sendLevel,
	suggestedLevel,
	trimLog,
	validEvent,
} from "../src/lib/telemetry/core.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const on = (extra = {}) => ({ enabled: true, default: "basic", force: null, retention_days: 90, ...extra });
const none = { level: null, notice: 0 };
const seen = (level = null) => ({ level, notice: NOTICE_VERSION });

ok("no server telemetry: off", effectiveLevel(null, seen("advanced")) === "off");
ok("disabled server: off", effectiveLevel({ enabled: false }, seen("advanced")) === "off");
ok("default applies without a choice", effectiveLevel(on({ default: "advanced" }), none) === "advanced");
ok("default falls back to basic", effectiveLevel({ enabled: true }, none) === "basic");
ok("a choice beats the default", effectiveLevel(on(), seen("off")) === "off");
ok("force off wins over advanced", effectiveLevel(on({ force: "off" }), seen("advanced")) === "off");
ok("force basic caps advanced", effectiveLevel(on({ force: "basic" }), seen("advanced")) === "basic");
ok("force basic raises off", effectiveLevel(on({ force: "basic" }), seen("off")) === "basic");
ok("force advanced is ignored (never adds)", forcedLevel(on({ force: "advanced" })) === null);
ok("force advanced leaves the choice", effectiveLevel(on({ force: "advanced" }), seen("off")) === "off");
ok("suggested level: server default", suggestedLevel(on({ default: "off" })) === "off");
ok("suggested level: forced", suggestedLevel(on({ force: "basic", default: "off" })) === "basic");

ok("notice due when never confirmed", needsNotice(on(), none));
ok("notice not due when the server is off", !needsNotice(null, none) && !needsNotice({ enabled: false }, none));
ok("notice due again for a new version", needsNotice(on(), { level: "basic", notice: NOTICE_VERSION - 1 }));
ok("notice not due once confirmed", !needsNotice(on(), seen()));
ok("nothing is sent before the notice", sendLevel(on({ default: "advanced" }), { level: "advanced", notice: 0 }) === "off");
ok("after the notice the level is used", sendLevel(on(), seen("advanced")) === "advanced");
ok("forced level is also held back until the notice", sendLevel(on({ force: "basic" }), none) === "off");

ok("valid feature", validEvent("feature", "layer.add.rect"));
ok("valid export", validEvent("export", "png"));
ok("valid error code", validEvent("error", "4001"));
ok("error name must be a 4 digit code", !validEvent("error", "400") && !validEvent("error", "my-card"));
ok("unknown kind", !validEvent("secret", "x"));
ok("capitals and spaces rejected", !validEvent("feature", "My Card") && !validEvent("feature", "A"));
ok("empty and long names rejected", !validEvent("feature", "") && !validEvent("feature", "a".repeat(41)));

ok("ping body holds only the level", pingBody("basic") === '{"level":"basic"}');
ok(
	"events body holds only kind and name",
	eventsBody([{ kind: "export", name: "pdf", t: "2026-01-01", extra: 1 }]) === '{"events":[{"k":"export","n":"pdf"}]}',
);

const entry = (i) => ({ t: String(i), kind: "feature", name: "x", level: "advanced", status: "sent" });
ok("log is trimmed to the newest", trimLog([1, 2, 3, 4].map(entry), 2).map((e) => e.t).join() === "3,4");
ok(
	"stored log drops bad entries",
	parseLog([entry(1), { t: "x" }, null, { ...entry(2), kind: "nope" }, { ...entry(3), level: "x" }, { ...entry(4), status: "?" }]).length === 1,
);
ok("stored log must be an array", parseLog({}).length === 0);
ok("stored prefs are sanitised", JSON.stringify(parsePrefs({ level: "ultra", notice: "1" })) === JSON.stringify(none));
ok("stored prefs keep a valid choice", parsePrefs({ level: "off", notice: 1 }).level === "off");

process.exit(failed ? 1 : 0);
