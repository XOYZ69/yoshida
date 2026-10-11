// Colour scheme switch. The editor (web/src/lib/theme.ts) uses the same
// storage key and data-theme attribute, so the choice is shared between the
// site and the editor (same origin). The <head> applies the stored choice
// before rendering; this script wires up the header button.
(function () {
  var KEY = "yoshida.theme";
  var LABELS = { system: "Theme: follows your system", light: "Theme: light", dark: "Theme: dark" };
  var NEXT = { system: "light", light: "dark", dark: "system" };

  function load() {
    try {
      var v = localStorage.getItem(KEY);
      return v === "light" || v === "dark" ? v : "system";
    } catch (e) {
      return "system";
    }
  }

  function apply(pref) {
    var root = document.documentElement;
    if (pref === "system") delete root.dataset.theme;
    else root.dataset.theme = pref;
    // Code highlighting comes as two stylesheets; point their media at the choice.
    document.querySelectorAll("link[data-scheme]").forEach(function (link) {
      var scheme = link.getAttribute("data-scheme");
      link.media = pref === "system" ? "(prefers-color-scheme: " + scheme + ")" : pref === scheme ? "all" : "not all";
    });
    document.querySelectorAll(".theme-toggle").forEach(function (btn) {
      btn.dataset.pref = pref;
      btn.setAttribute("aria-label", LABELS[pref]);
      btn.title = LABELS[pref] + " (click to change)";
    });
  }

  function save(pref) {
    try {
      if (pref === "system") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, pref);
    } catch (e) {}
  }

  apply(load());
  document.addEventListener("click", function (e) {
    var btn = e.target.closest && e.target.closest(".theme-toggle");
    if (!btn) return;
    var pref = NEXT[load()] || "system";
    save(pref);
    apply(pref);
  });
  // Keep other open tabs (site or editor) in step.
  window.addEventListener("storage", function (e) {
    if (e.key === KEY || e.key === null) apply(load());
  });
})();
