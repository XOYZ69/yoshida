// Docs behaviour: search dialog, sidebar drawer on small screens, the
// "On this page" highlight, copy buttons on code blocks and scrollable
// tables. Everything degrades to plain links and content without JS.
(function () {
  "use strict";

  // ---------------------------------------------------------------- search
  // The index is templates/search-data.html: one entry per page intro and
  // per h2/h3 section ({t: title, p: page, g: group, u: url, b: text}).
  var dialog = document.querySelector("dialog.search");
  var input = document.getElementById("search-input");
  var list = document.getElementById("search-results");
  var status = dialog && dialog.querySelector(".search-status");
  var indexUrl = (document.querySelector("[data-index]") || {}).dataset;
  indexUrl = indexUrl && indexUrl.index;
  var entries = null;
  var loading = null;
  var active = -1;
  var shown = [];

  var decoder = document.createElement("textarea");
  function decode(s) {
    if (s.indexOf("&") < 0) return s;
    decoder.innerHTML = s;
    return decoder.value;
  }

  function load() {
    if (loading) return loading;
    loading = fetch(indexUrl)
      .then(function (r) {
        if (!r.ok) throw new Error(r.status);
        return r.json();
      })
      .then(function (data) {
        entries = data.map(function (e) {
          var t = decode(e.t), p = decode(e.p), b = decode(e.b);
          return { t: t, p: p, g: e.g, u: e.u, b: b, tl: t.toLowerCase(), pl: p.toLowerCase(), bl: b.toLowerCase(), intro: e.u.indexOf("#") < 0 };
        });
        return entries;
      })
      .catch(function () {
        loading = null;
        if (status) status.textContent = "The search index could not be loaded.";
      });
    return loading;
  }

  function terms(q) {
    return q.toLowerCase().split(/\s+/).filter(Boolean);
  }

  function score(e, ts, q) {
    var s = 0;
    for (var i = 0; i < ts.length; i++) {
      var t = ts[i];
      var inT = e.tl.indexOf(t), inP = e.pl.indexOf(t), inB = e.bl.indexOf(t);
      if (inT < 0 && inP < 0 && inB < 0) return 0;
      if (inT === 0) s += 40;
      else if (inT > 0) s += 25;
      if (inP >= 0) s += e.intro ? 20 : 6;
      if (inB >= 0) s += 4 + Math.min(6, e.bl.split(t).length - 1);
      // Whole words beat parts of words ("clip" over "clipboard").
      var word = new RegExp("(^|[^a-z0-9_])" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "($|[^a-z0-9_])");
      if (word.test(e.tl)) s += 30;
      if (word.test(e.bl)) s += 12;
    }
    if (e.tl === q) s += 60;
    if (e.intro && e.pl === q) s += 60;
    return s;
  }

  function esc(s) {
    return s.replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function mark(text, ts) {
    var out = esc(text);
    ts.forEach(function (t) {
      var re = new RegExp("(" + esc(t).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi");
      out = out.replace(re, "<mark>$1</mark>");
    });
    // Undo marks that landed inside an entity such as &amp;.
    return out.replace(/&(\w*)<mark>(\w*)<\/mark>(\w*);/g, "&$1$2$3;");
  }

  function snippet(e, ts) {
    var at = -1;
    for (var i = 0; i < ts.length && at < 0; i++) at = e.bl.indexOf(ts[i]);
    if (at < 0) return e.b.slice(0, 140);
    var start = Math.max(0, at - 50);
    var s = e.b.slice(start, start + 160);
    return (start > 0 ? "…" : "") + s + (start + 160 < e.b.length ? "…" : "");
  }

  function render(q) {
    var ts = terms(q);
    list.innerHTML = "";
    active = -1;
    shown = [];
    if (!ts.length) {
      status.textContent = entries ? "Search " + entries.length + " sections of the docs." : "";
      input.setAttribute("aria-expanded", "false");
      return;
    }
    var ql = q.trim().toLowerCase();
    shown = entries
      .map(function (e) { return { e: e, s: score(e, ts, ql) }; })
      .filter(function (r) { return r.s > 0; })
      .sort(function (a, b) { return b.s - a.s; })
      .slice(0, 20)
      .map(function (r) { return r.e; });
    status.textContent = shown.length ? shown.length + (shown.length === 20 ? "+" : "") + " results" : "Nothing found for “" + q.trim() + "”.";
    input.setAttribute("aria-expanded", shown.length ? "true" : "false");
    shown.forEach(function (e, i) {
      var li = document.createElement("li");
      li.id = "sr-" + i;
      li.setAttribute("role", "option");
      var where = e.g ? esc(e.g) + " · " : "";
      li.innerHTML =
        '<a href="' + esc(e.u) + '" tabindex="-1">' +
        '<span class="sr-where">' + where + (e.intro ? "Page" : esc(e.p)) + "</span>" +
        '<span class="sr-title">' + mark(e.t, ts) + "</span>" +
        '<span class="sr-text">' + mark(snippet(e, ts), ts) + "</span></a>";
      li.addEventListener("mousemove", function () { if (active !== i) setActive(i); });
      list.appendChild(li);
    });
    if (shown.length) setActive(0);
  }

  function setActive(i) {
    var items = list.children;
    if (active >= 0 && items[active]) items[active].removeAttribute("aria-selected");
    active = i;
    if (items[i]) {
      items[i].setAttribute("aria-selected", "true");
      items[i].scrollIntoView({ block: "nearest" });
      input.setAttribute("aria-activedescendant", items[i].id);
    } else {
      input.removeAttribute("aria-activedescendant");
    }
  }

  function openSearch() {
    if (!dialog || dialog.open) return;
    dialog.showModal();
    input.select();
    load().then(function () { if (entries) render(input.value); });
  }

  if (dialog && indexUrl) {
    document.addEventListener("click", function (e) {
      if (e.target.closest(".search-open")) openSearch();
    });
    // A click on the backdrop (outside the panel) closes the dialog.
    dialog.addEventListener("click", function (e) {
      if (e.target === dialog) dialog.close();
    });
    input.addEventListener("input", function () {
      if (entries) render(input.value);
    });
    input.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" && shown.length) {
        e.preventDefault();
        setActive((active + 1) % shown.length);
      } else if (e.key === "ArrowUp" && shown.length) {
        e.preventDefault();
        setActive((active - 1 + shown.length) % shown.length);
      } else if (e.key === "Enter") {
        e.preventDefault();
        if (shown[active]) {
          dialog.close();
          location.href = shown[active].u;
        }
      }
    });
    // Following a link to a section of the current page does not reload it.
    list.addEventListener("click", function (e) {
      if (e.target.closest("a")) dialog.close();
    });
    document.addEventListener("keydown", function (e) {
      var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable;
      if ((e.key === "k" || e.key === "K") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        openSearch();
      } else if (e.key === "/" && !typing && !e.altKey && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        openSearch();
      }
    });
    // Show the platform's shortcut in the header hint.
    if (/Mac|iPhone|iPad/.test(navigator.platform)) {
      document.querySelectorAll(".search-open .hint").forEach(function (k) { k.textContent = "⌘K"; });
    } else {
      document.querySelectorAll(".search-open .hint").forEach(function (k) { k.textContent = "Ctrl K"; });
    }
  }

  // ------------------------------------------------------- sidebar drawer
  var nav = document.getElementById("docs-nav");
  if (nav) {
    var scrim = document.createElement("div");
    scrim.className = "nav-scrim";
    document.body.appendChild(scrim);
    var toggles = document.querySelectorAll(".nav-toggle");
    var setOpen = function (open) {
      document.body.classList.toggle("nav-open", open);
      toggles.forEach(function (b) { b.setAttribute("aria-expanded", open ? "true" : "false"); });
      if (open) (nav.querySelector("[aria-current]") || nav.querySelector("a")).focus({ preventScroll: true });
    };
    toggles.forEach(function (b) {
      b.addEventListener("click", function () { setOpen(!document.body.classList.contains("nav-open")); });
    });
    scrim.addEventListener("click", function () { setOpen(false); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && document.body.classList.contains("nav-open")) setOpen(false);
    });
    // Keep the current page visible in a long sidebar.
    var current = nav.querySelector("[aria-current]");
    if (current && current.offsetTop + current.offsetHeight > nav.clientHeight) {
      nav.scrollTop = current.offsetTop - nav.clientHeight / 3;
    }
  }

  // ------------------------------------------------ "On this page" highlight
  var toc = document.querySelector(".toc");
  if (toc && "IntersectionObserver" in window) {
    var links = {};
    toc.querySelectorAll("a").forEach(function (a) { links[decodeURIComponent(a.hash.slice(1))] = a; });
    var heads = Array.prototype.filter.call(document.querySelectorAll(".prose h2[id], .prose h3[id]"), function (h) { return links[h.id]; });
    var visible = new Set();
    var markToc = function () {
      var id = null;
      // The first heading on screen, or else the last one scrolled past.
      for (var i = 0; i < heads.length; i++) {
        if (visible.has(heads[i].id)) { id = heads[i].id; break; }
      }
      if (!id) {
        for (var j = heads.length - 1; j >= 0; j--) {
          if (heads[j].getBoundingClientRect().top < 120) { id = heads[j].id; break; }
        }
      }
      toc.querySelectorAll("a.active").forEach(function (a) { a.classList.remove("active"); });
      if (id && links[id]) links[id].classList.add("active");
    };
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) visible.add(e.target.id); else visible.delete(e.target.id); });
      markToc();
    }, { rootMargin: "-72px 0px -55% 0px" });
    heads.forEach(function (h) { io.observe(h); });
  }

  // ------------------------------------------------------- code and tables
  document.querySelectorAll(".prose pre").forEach(function (pre) {
    var wrap = document.createElement("div");
    wrap.className = "code";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    var lang = pre.querySelector("code[data-lang]");
    lang = lang && lang.getAttribute("data-lang");
    if (lang && lang !== "plain" && lang !== "txt" && lang !== "text") {
      var tag = document.createElement("span");
      tag.className = "code-lang";
      tag.textContent = lang;
      wrap.appendChild(tag);
    }
    if (!navigator.clipboard) return;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy";
    btn.textContent = "Copy";
    btn.setAttribute("aria-label", "Copy code");
    btn.addEventListener("click", function () {
      navigator.clipboard.writeText(pre.innerText.replace(/\n$/, "")).then(function () {
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = "Copy"; }, 1500);
      });
    });
    wrap.appendChild(btn);
  });
  document.querySelectorAll(".prose table").forEach(function (t) {
    var wrap = document.createElement("div");
    wrap.className = "table-wrap";
    t.parentNode.insertBefore(wrap, t);
    wrap.appendChild(t);
  });
})();
