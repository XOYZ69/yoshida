// Checks the hex colour helper against the core's rules (value.zig parseHex).
//
//   node --experimental-strip-types tests/hexcolor.mjs
import { expandHex, HEX_COLOR, CSS_HEX_COLOR } from "../src/lib/hexcolor.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};

ok("#F80 expands to #FF8800", expandHex("#F80") === "#FF8800");
ok("#F80A expands to #FF8800AA", expandHex("#F80A") === "#FF8800AA");
ok("#abcdef is unchanged", expandHex("#abcdef") === "#abcdef");
ok("text is returned trimmed", expandHex("  red ") === "red");
ok("3 digits match the core form", HEX_COLOR.test("#F80"));
ok("4 digits match the core form", HEX_COLOR.test("#F80A"));
ok("2 digits are not a colour", !HEX_COLOR.test("#FF"));
ok("5 digits are not a colour", !HEX_COLOR.test("#FFF80"));
ok("CSS form excludes 16-bit", !CSS_HEX_COLOR.test("#FFFFFFFFFFFF") && CSS_HEX_COLOR.test("#FFFFFFAA"));

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
