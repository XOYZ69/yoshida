// Fills the Stats page (templates/stats.html) from stats.json, the file that
// .github/workflows/stats.yml writes once a day (scripts/stats.mjs describes
// its shape). Everything from the file is put into the page as text, never
// as markup. No dependencies.
(function () {
  var root = document.getElementById("stats");
  if (!root) return;
  var SVG = "http://www.w3.org/2000/svg";
  var num = function (v) { return typeof v === "number" && isFinite(v) ? v.toLocaleString("en") : "–"; };

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
    return isNaN(d) ? String(date) : d.toLocaleDateString("en", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
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
    if (older.length) {
      var details = s.appendChild(el("details", "stats-more"));
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

  // The public stats of a self-hosted instance, as that server reports them:
  // every number in the answer, named by its place in it.
  function instance(doc) {
    var inst = doc.instance;
    if (!inst || typeof inst.stats !== "object" || !inst.stats) return;
    var rows = [];
    (function walk(value, path, depth) {
      if (rows.length >= 24) return;
      if (typeof value === "number" && isFinite(value)) rows.push([path.join(" · ").replace(/[_-]+/g, " "), value]);
      else if (value && typeof value === "object" && !Array.isArray(value) && depth < 3) {
        Object.keys(value).forEach(function (k) { walk(value[k], path.concat(k), depth + 1); });
      }
    })(inst.stats, [], 0);
    if (!rows.length) return;
    var host = typeof inst.host === "string" ? inst.host : "a self-hosted instance";
    var s = section("Editor at " + host, "Counted by that server and shared by its operator" + (inst.fetched_at ? ", as of " + day(String(inst.fetched_at).slice(0, 10)) : "") + ".");
    facts(s, rows);
  }

  function fail() {
    root.textContent = "";
    var p = root.appendChild(el("p", "stats-status", "The numbers are not available right now. "));
    var a = p.appendChild(el("a", null, "The repository on GitHub"));
    a.href = root.dataset.repo;
    p.appendChild(document.createTextNode(" has the current ones."));
  }

  fetch(root.dataset.src, { credentials: "omit", referrerPolicy: "no-referrer" })
    .then(function (res) {
      if (!res.ok) throw new Error(String(res.status));
      return res.json();
    })
    .then(function (doc) {
      if (!doc || doc.version !== 1 || typeof doc.now !== "object") throw new Error("unknown format");
      root.textContent = "";
      project(doc);
      releases(doc);
      traffic(doc);
      instance(doc);
      if (doc.generated_at) root.appendChild(el("p", "meta", "Updated " + day(String(doc.generated_at).slice(0, 10)) + "."));
    })
    .catch(fail);
})();
