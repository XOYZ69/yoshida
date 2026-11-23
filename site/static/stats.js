// Fills the Stats page (templates/stats.html) from stats.json, the file that
// .github/workflows/stats.yml writes once a day (scripts/stats.mjs describes
// its shape). Everything from the file is put into the page as text, never
// as markup. No dependencies.
(function () {
  var root = document.getElementById("stats");
  if (!root) return;
  var SVG = "http://www.w3.org/2000/svg";
  var num = function (v) { return typeof v === "number" && Number.isFinite(v) ? v.toLocaleString("en") : "–"; };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function svg(tag, attrs) {
    var e = document.createElementNS(SVG, tag);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    return e;
  }
  function day(date) {
    var d = new Date(date + "T00:00:00Z");
    return Number.isNaN(d.getTime()) ? String(date) : d.toLocaleDateString("en", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
  }
  function sum(points) { return points.reduce(function (s, p) { return s + p.value; }, 0); }
  function series(list, key) {
    return (Array.isArray(list) ? list : [])
      .filter(function (d) { return d && typeof d.date === "string" && typeof d[key] === "number"; })
      .map(function (d) { return { date: d.date, value: d[key] }; });
  }

  // A small line over time. Pointing at it shows the day under the pointer
  // in the tile's note line; the table below the tiles has the same values.
  function sparkline(points, note) {
    var W = 200, H = 44, PAD = 5;
    var lo = Math.min.apply(null, points.map(function (p) { return p.value; }));
    var hi = Math.max.apply(null, points.map(function (p) { return p.value; }));
    var x = function (i) { return PAD + (i * (W - 2 * PAD)) / (points.length - 1); };
    var y = function (v) { return hi === lo ? H / 2 : H - PAD - ((v - lo) * (H - 2 * PAD)) / (hi - lo); };
    var line = points.map(function (p, i) { return x(i).toFixed(1) + "," + y(p.value).toFixed(1); }).join(" ");
    var last = points.length - 1;
    var s = svg("svg", { viewBox: "0 0 " + W + " " + H, class: "spark", role: "img", preserveAspectRatio: "none",
      "aria-label": "From " + day(points[0].date) + " (" + num(points[0].value) + ") to " + day(points[last].date) + " (" + num(points[last].value) + ")" });
    s.appendChild(svg("polygon", { class: "spark-area", points: PAD + "," + H + " " + line + " " + (W - PAD) + "," + H }));
    s.appendChild(svg("polyline", { class: "spark-line", points: line, "vector-effect": "non-scaling-stroke" }));
    var wrap = el("div", "spark-wrap");
    var dot = el("span", "spark-dot");
    wrap.appendChild(s);
    wrap.appendChild(dot);
    var rest = note.textContent;
    function show(i) {
      dot.style.left = (x(i) / W) * 100 + "%";
      dot.style.top = (y(points[i].value) / H) * 100 + "%";
    }
    show(last);
    wrap.addEventListener("pointermove", function (ev) {
      var box = wrap.getBoundingClientRect();
      var i = Math.round((((ev.clientX - box.left) / box.width) * W - PAD) / ((W - 2 * PAD) / last));
      i = Math.max(0, Math.min(last, i));
      show(i);
      note.textContent = day(points[i].date) + ": " + num(points[i].value);
    });
    wrap.addEventListener("pointerleave", function () { show(last); note.textContent = rest; });
    return wrap;
  }

  function tile(label, value, note, points) {
    var t = el("div", "stat");
    t.appendChild(el("div", "stat-label", label));
    t.appendChild(el("div", "stat-value", typeof value === "number" ? num(value) : value));
    var n = el("div", "stat-note", note || "");
    if (points && points.length > 1) t.appendChild(sparkline(points, n));
    t.appendChild(n);
    return t;
  }

  // Small numbers without a trend, side by side in one strip.
  function facts(parent, items) {
    var dl = parent.appendChild(el("dl", "facts"));
    items.forEach(function (item) {
      var d = dl.appendChild(el("div"));
      d.appendChild(el("dt", null, item[0]));
      d.appendChild(el("dd", null, typeof item[1] === "number" ? num(item[1]) : item[1]));
    });
  }

  function section(title, lead) {
    var s = el("section", "stats-block");
    s.appendChild(el("h2", null, title));
    if (lead) s.appendChild(el("p", "meta", lead));
    root.appendChild(s);
    return s;
  }

  function table(head, rows) {
    var t = el("table");
    var tr = t.appendChild(el("thead")).appendChild(el("tr"));
    head.forEach(function (h) { tr.appendChild(el("th", null, h)); });
    var body = t.appendChild(el("tbody"));
    rows.forEach(function (r) {
      var row = body.appendChild(el("tr"));
      r.forEach(function (c) { row.appendChild(el("td", null, c)); });
    });
    return t;
  }

  function project(doc) {
    var now = doc.now || {};
    var s = section("Project");
    var grid = s.appendChild(el("div", "stat-grid two"));
    var since = Array.isArray(doc.history) && doc.history.length > 1 ? "since " + day(doc.history[0].date) : "";
    grid.appendChild(tile("Stars", now.stars, since || "on GitHub", series(doc.history, "stars")));
    grid.appendChild(tile("Downloads", now.downloads, since || "of every release", series(doc.history, "downloads")));
    var items = [["Forks", now.forks], ["Contributors", now.contributors], ["Releases", now.releases]];
    var latest = now.latest_release;
    if (latest && typeof latest.tag === "string") {
      items.push(["Latest release", latest.tag + (latest.published_at ? ", " + day(String(latest.published_at).slice(0, 10)) : "")]);
    }
    facts(s, items);
  }

  // Where downloads went, from the file names of the release assets (the
  // collector sorts them: scripts/stats.mjs, classifyAsset). GitHub counts
  // downloads per file only, so a person who fetches two files counts twice,
  // and the web editor, which is opened and not downloaded, is not part of it.
  var KINDS = { desktop: "Desktop app", bundle: "Release zip", other: "Other files" };
  var SYSTEMS = { windows: "Windows", linux: "Linux", macos: "macOS" };
  var FORMATS = { exe: "Windows installer (.exe)", msi: "Windows installer (.msi)", appimage: "AppImage", deb: ".deb package", rpm: ".rpm package", dmg: "macOS disk image (.dmg)", zip: "Release zip (.zip)", other: "Other" };
  function pairs(map, names) {
    return Object.keys(map || {})
      .filter(function (k) { return typeof map[k] === "number" && map[k] > 0; })
      .map(function (k) { return [names[k] || k, map[k]]; })
      .sort(function (a, b) { return b[1] - a[1] || (a[0] < b[0] ? -1 : 1); });
  }
  // Downloads in the last `days` days: the difference of the running total.
  function recent(history, days) {
    var list = (Array.isArray(history) ? history : []).filter(function (h) { return h && typeof h.date === "string" && typeof h.downloads === "number"; });
    if (list.length < 2) return null;
    var last = list[list.length - 1];
    var cut = new Date(last.date + "T00:00:00Z").getTime() - days * 86400000;
    var base = list[0];
    list.forEach(function (h) { if (new Date(h.date + "T00:00:00Z").getTime() <= cut) base = h; });
    return { value: Math.max(0, last.downloads - base.downloads), from: base.date };
  }
  function downloads(doc) {
    var by = doc.now && doc.now.downloads_by;
    if (!by || typeof by !== "object" || !(doc.now.downloads > 0)) return;
    var s = section("Downloads by option", "Which files people fetch from the releases on GitHub, all releases added up. The release zip holds the CLI, the server and the web editor files. The web editor is opened in a browser, not downloaded, so it is not in here.");
    var grid = s.appendChild(el("div", "stat-grid three"));
    [[7, "Last 7 days"], [30, "Last 30 days"]].forEach(function (p) {
      var r = recent(doc.history, p[0]);
      if (r) grid.appendChild(tile(p[1], r.value, "downloads since " + day(r.from)));
    });
    var kinds = pairs(by.kinds, KINDS);
    if (kinds.length) grid.appendChild(tile("Most downloaded", kinds[0][0].replace(/ \(.*/, ""), Math.round((kinds[0][1] / (sum(kinds.map(function (k) { return { value: k[1] }; })) || 1)) * 100) + "% of all downloads"));
    [["Option", pairs(by.kinds, KINDS)], ["Desktop app, by system", pairs(by.systems, SYSTEMS)], ["File type", pairs(by.formats, FORMATS)]].forEach(function (g) {
      if (!g[1].length) return;
      s.appendChild(el("h3", null, g[0]));
      countBars(s, g[1], g[1][0][1] || 1);
    });
    // Each option's running total over time, once there are at least two days.
    var trends = [];
    Object.keys(KINDS).forEach(function (k) {
      var pts = (Array.isArray(doc.history) ? doc.history : [])
        .filter(function (h) { return h && h.kinds && typeof h.kinds[k] === "number"; })
        .map(function (h) { return { date: h.date, value: h.kinds[k] }; });
      if (pts.length > 1 && pts[pts.length - 1].value > 0) trends.push([KINDS[k].replace(/ \(.*/, ""), pts]);
    });
    if (trends.length) {
      s.appendChild(el("h3", null, "Running total per option"));
      var tg = s.appendChild(el("div", "stat-grid two"));
      trends.forEach(function (t) { tg.appendChild(tile(t[0], t[1][t[1].length - 1].value, "since " + day(t[1][0].date), t[1])); });
    }
  }

  // Which releases people choose: the share of the latest one, the most
  // downloaded one and a fair comparison, downloads per week since a release.
  function adoption(doc) {
    var list = (Array.isArray(doc.releases) ? doc.releases : []).filter(function (r) { return r && typeof r.tag === "string" && !r.prerelease; });
    var total = sum(list.map(function (r) { return { value: r.downloads || 0 }; }));
    if (list.length < 2 || !total) return;
    var s = section("Version adoption", "Downloads are counted per release for good, so older releases keep what they got. The weekly rate compares releases of different ages.");
    var now = doc.generated_at ? new Date(doc.generated_at).getTime() : Date.now();
    var rate = function (r) {
      var weeks = Math.max(1, (now - new Date(r.published_at).getTime()) / (7 * 86400000));
      return (r.downloads || 0) / weeks;
    };
    var top = list.slice().sort(function (a, b) { return (b.downloads || 0) - (a.downloads || 0); })[0];
    var fast = list.filter(function (r) { return r.published_at; }).sort(function (a, b) { return rate(b) - rate(a); })[0];
    var items = [["Latest release", list[0].tag + ": " + Math.round(((list[0].downloads || 0) / total) * 100) + "% of downloads"], ["Most downloaded", top.tag + " (" + num(top.downloads || 0) + ")"]];
    if (fast) items.push(["Fastest per week", fast.tag + " (" + (Math.round(rate(fast) * 10) / 10).toLocaleString("en") + " a week)"]);
    facts(s, items);
  }

  // The newest releases as bars; older ones fold away, so the section keeps
  // its size however many releases there are. Every bar uses the same scale.
  var SHOWN = 6;
  function releases(doc) {
    var list = (Array.isArray(doc.releases) ? doc.releases : []).filter(function (r) { return r && typeof r.tag === "string"; });
    if (!list.length) return;
    var s = section("Downloads by release", "The files attached to each release on GitHub, newest release first.");
    var max = Math.max.apply(null, list.map(function (r) { return r.downloads || 0; })) || 1;
    function bars(parent, part) {
      var rows = parent.appendChild(el("ul", "bars"));
      part.forEach(function (r) {
        var li = rows.appendChild(el("li"));
        var name;
        if (typeof r.url === "string" && r.url.indexOf("https://github.com/") === 0) {
          name = el("a", "bar-name", r.tag);
          name.href = r.url;
        } else {
          name = el("span", "bar-name", r.tag);
        }
        if (r.published_at) name.title = day(String(r.published_at).slice(0, 10)) + (r.prerelease ? ", pre-release" : "");
        li.appendChild(name);
        var track = li.appendChild(el("span", "bar-track"));
        var fill = track.appendChild(el("span", "bar-fill"));
        fill.style.width = ((r.downloads || 0) / max) * 100 + "%";
        li.appendChild(el("span", "bar-value", num(r.downloads || 0)));
      });
    }
    bars(s, list.slice(0, SHOWN));
    var older = list.slice(SHOWN);
    var details;
    if (older.length) {
      details = s.appendChild(el("details", "stats-more"));
      details.appendChild(el("summary", null, older.length === 1 ? "Show 1 older release" : "Show " + older.length + " older releases"));
      bars(details, older);
    }
  }

  function traffic(doc) {
    var days = Array.isArray(doc.traffic) ? doc.traffic : [];
    if (!days.length) return;
    var recent = days.slice(-90);
    var s = section("Repository traffic", "Visits to the repository on GitHub and git clones, " + day(recent[0].date) + " to " + day(recent[recent.length - 1].date) + ". Not visits to this website.");
    var grid = s.appendChild(el("div", "stat-grid three"));
    [["Views", "views"], ["Visitors per day", "visitors"], ["Clones", "clones"]].forEach(function (pair) {
      var points = series(recent, pair[1]);
      if (!points.length) return;
      var two = points.slice(-14);
      var value = pair[1] === "visitors" ? Math.round((sum(two) / two.length) * 10) / 10 : sum(two);
      grid.appendChild(tile(pair[0], value, pair[1] === "visitors" ? "average, last 14 days" : "last 14 days", points));
    });
    var details = s.appendChild(el("details", "stats-more stats-table"));
    details.appendChild(el("summary", null, "Show the days as a table"));
    details.appendChild(table(["Day", "Views", "Visitors", "Clones", "Cloners"], recent.slice().reverse().map(function (d) {
      return [day(d.date), num(d.views), num(d.visitors), num(d.clones), num(d.cloners)];
    })));
  }

  // A list of names with a bar each, largest first; all bars share one scale.
  function countBars(parent, rows, max) {
    var list = parent.appendChild(el("ul", "bars"));
    rows.forEach(function (r) {
      var li = list.appendChild(el("li"));
      li.appendChild(el("span", "bar-name", r[0]));
      var fill = li.appendChild(el("span", "bar-track")).appendChild(el("span", "bar-fill"));
      fill.style.width = (r[1] / max) * 100 + "%";
      li.appendChild(el("span", "bar-value", num(r[1])));
    });
  }

  // The public stats of a self-hosted instance. A yoshida server answers
  // GET /api/stats with { retention_days, days: [{ day, sessions?, uniques?,
  // advanced_sessions?, events: { "group:name": count } }] }, holding only what
  // its operator made public. The days are added up here.
  var EVENT_GROUPS = [["feature", "Features used"], ["export", "Exports by format"], ["error", "Problems shown, by code"]];
  var EVENTS_SHOWN = 8;
  function instanceDays(s, days) {
    var totals = {}, events = {};
    days.forEach(function (d) {
      ["sessions", "uniques", "advanced_sessions"].forEach(function (k) {
        if (typeof d[k] === "number" && Number.isFinite(d[k])) totals[k] = (totals[k] || 0) + d[k];
      });
      var ev = d.events && typeof d.events === "object" ? d.events : {};
      Object.keys(ev).forEach(function (k) {
        if (typeof ev[k] === "number" && Number.isFinite(ev[k])) events[k] = (events[k] || 0) + ev[k];
      });
    });
    var items = [];
    if ("sessions" in totals) items.push(["Sessions", totals.sessions]);
    if ("uniques" in totals) items.push(["Visitors, counted per day", totals.uniques]);
    if ("advanced_sessions" in totals) items.push(["Sessions sharing details", totals.advanced_sessions]);
    if (items.length) facts(s, items);
    var shown = items.length > 0;
    EVENT_GROUPS.forEach(function (group) {
      var rows = Object.keys(events)
        .filter(function (k) { return k.indexOf(group[0] + ":") === 0; })
        .map(function (k) { return [k.slice(group[0].length + 1), events[k]]; })
        .sort(function (a, b) { return b[1] - a[1] || (a[0] < b[0] ? -1 : 1); });
      if (!rows.length) return;
      shown = true;
      s.appendChild(el("h3", null, group[1]));
      countBars(s, rows.slice(0, EVENTS_SHOWN), rows[0][1] || 1);
      var more = rows.slice(EVENTS_SHOWN);
      var details;
      if (more.length) {
        details = s.appendChild(el("details", "stats-more"));
        details.appendChild(el("summary", null, "Show " + more.length + " more"));
        countBars(details, more, rows[0][1] || 1);
      }
    });
    return shown;
  }

  function instance(doc) {
    var inst = doc.instance;
    if (!inst || typeof inst.stats !== "object" || !inst.stats) return;
    var host = typeof inst.host === "string" ? inst.host : "a self-hosted instance";
    var days = (Array.isArray(inst.stats.days) ? inst.stats.days : [])
      .filter(function (d) { return d && typeof d === "object" && typeof d.day === "string"; });
    var lead = "Counted by that server and shared by its operator";
    if (days.length) lead += ", " + (days.length === 1 ? day(days[0].day) : day(days[0].day) + " to " + day(days[days.length - 1].day));
    else if (inst.fetched_at) lead += ", as of " + day(String(inst.fetched_at).slice(0, 10));
    var s = el("section", "stats-block");
    s.appendChild(el("h2", null, "Editor at " + host));
    s.appendChild(el("p", "meta", lead + "."));
    var shown = false;
    var rows = [];
    if (days.length) shown = instanceDays(s, days);
    else {
      // Another shape: every number in the answer, named by its place in it.
      (function walk(value, path, depth) {
        if (rows.length >= 24) return;
        if (typeof value === "number" && Number.isFinite(value)) rows.push([path.join(" · ").replace(/[_-]+/g, " "), value]);
        else if (value && typeof value === "object" && !Array.isArray(value) && depth < 3) {
          Object.keys(value).forEach(function (k) { walk(value[k], path.concat(k), depth + 1); });
        }
      })(inst.stats, [], 0);
      if (rows.length) { facts(s, rows); shown = true; }
    }
    if (shown) root.appendChild(s);
  }

  function fail() {
    root.textContent = "";
    var p = root.appendChild(el("p", "stats-status", "The numbers are not available right now. "));
    var a = p.appendChild(el("a", null, "The repository on GitHub"));
    a.href = root.dataset.repo;
    p.appendChild(document.createTextNode(" has the current ones."));
  }

  function load(src) {
    return fetch(src, { credentials: "omit", referrerPolicy: "no-referrer" }).then(function (res) {
      if (!res.ok) throw new Error(String(res.status));
      return res.json();
    });
  }

  // The published file first; a stats.json beside the site stands in when it
  // cannot be loaded, which is the case in a local preview (site/README.md).
  load(root.dataset.src)
    .catch(function (err) {
      if (!root.dataset.local) throw err;
      return load(root.dataset.local);
    })
    .then(function (doc) {
      if (!doc || doc.version !== 1 || typeof doc.now !== "object") throw new Error("unknown format");
      root.textContent = "";
      project(doc);
      downloads(doc);
      releases(doc);
      adoption(doc);
      traffic(doc);
      instance(doc);
      if (doc.generated_at) root.appendChild(el("p", "meta", "Updated " + day(String(doc.generated_at).slice(0, 10)) + "."));
    })
    .catch(fail);
})();
