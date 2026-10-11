#!/usr/bin/env python3
"""One-off migration of a GitHub wiki checkout into Zola content.

Usage: wiki-to-zola.py WIKI_DIR SITE_DIR

- Every Page-Name.md becomes SITE_DIR/content/docs/page-name.md with front
  matter (title from the first "# " heading, which is then removed because
  the template prints the title).
- Home.md becomes the docs section index (content/docs/_index.md).
- Wiki links [text](Page-Name) and [text](Page-Name#anchor) become Zola
  internal links [text](@/docs/page-name.md#anchor), so the build fails on
  any link to a page that does not exist.
- Lines containing "{{", "{%" or "{#" are wrapped in {% raw %}, because
  Zola reads those as Tera tags. Anchors are kept as written; Zola
  slugs some headings differently from GitHub (e.g. headings with code), and
  the build names every anchor that no longer matches so it can be fixed.
- images/* are copied to SITE_DIR/static/docs/images/ and referenced with a
  path relative to the page, so the site works under any base path.
- _Sidebar.md becomes SITE_DIR/data/docs-nav.toml, rendered by the docs
  templates. _Footer.md is dropped (the site template has its own footer).
"""
import re
import shutil
import sys
from pathlib import Path

LINK = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)\)")
HTML_IMG = re.compile(r'(<img\s[^>]*src=")images/')


def slug(name: str) -> str:
    return name.lower()


def page_file(target: str) -> str:
    return "_index.md" if target == "Home" else f"{slug(target)}.md"


def convert_links(text: str, pages: set[str], in_section_index: bool) -> str:
    img_prefix = "images/" if in_section_index else "../images/"

    def repl(m: re.Match) -> str:
        bang, label, url = m.groups()
        if url.startswith("images/"):
            return f"{bang}[{label}]({img_prefix}{url[len('images/'):]})"
        if re.match(r"^[a-z]+:|^#|^/|^\.\.", url):
            return m.group(0)
        target, _, anchor = url.partition("#")
        if target not in pages:
            print(f"warning: link to unknown page {url!r}", file=sys.stderr)
            return m.group(0)
        frag = f"#{anchor}" if anchor else ""
        return f"{bang}[{label}](@/docs/{page_file(target)}{frag})"

    text = LINK.sub(repl, text)
    # Zola's highlighter has no "text" grammar; "txt" is plain text.
    text = re.sub(r"^```text$", "```txt", text, flags=re.M)
    return HTML_IMG.sub(lambda m: m.group(1) + img_prefix, text)


def protect_tera(text: str) -> str:
    """Zola runs page content through Tera before Markdown, so yoshida's own
    brace syntax ("{{" for a literal brace, "{name}" holes are fine) must not
    look like a Tera tag. Lines with "{{", "{%" or "{#" are wrapped in raw."""
    return "\n".join(
        f"{{% raw %}}{line}{{% endraw %}}" if re.search(r"\{[{%#]", line) else line
        for line in text.split("\n")
    )


def split_title(text: str, fallback: str) -> tuple[str, str]:
    m = re.search(r"^# (.+)$", text, re.M)
    if not m:
        return fallback, text
    body = text[: m.start()] + text[m.end():]
    return m.group(1).strip(), body.lstrip("\n")


def toml_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sidebar_to_toml(text: str, pages: set[str]) -> str:
    """Turns the wiki sidebar (bold group headings, nested bullet lists)
    into [[group]] tables with [[group.item]] / [[group.item.child]]."""
    out = []
    for line in text.splitlines():
        heading = re.match(r"^\*\*([^*\[]+)\*\*$", line.strip())
        item = re.match(r"^(\s*)- \[([^\]]+)\]\(([^)#]+)\)", line)
        if heading:
            out.append(f"\n[[group]]\ntitle = {toml_str(heading.group(1))}")
        elif item:
            indent, label, target = item.groups()
            if target not in pages:
                print(f"warning: sidebar links unknown page {target!r}", file=sys.stderr)
                continue
            table = "group.item.child" if indent else "group.item"
            out.append(f"[[{table}]]\ntitle = {toml_str(label)}\npath = {toml_str('docs/' + page_file(target))}")
    return "\n".join(out).lstrip() + "\n"


def main() -> None:
    wiki, site = Path(sys.argv[1]), Path(sys.argv[2])
    docs = site / "content" / "docs"
    docs.mkdir(parents=True, exist_ok=True)
    pages = {p.stem for p in wiki.glob("*.md") if not p.stem.startswith("_")}

    for p in sorted(wiki.glob("*.md")):
        if p.stem.startswith("_"):
            continue
        title, body = split_title(p.read_text(encoding="utf-8"), p.stem.replace("-", " "))
        is_index = p.stem == "Home"
        body = protect_tera(convert_links(body, pages, is_index))
        front = [f"title = {toml_str(title)}"]
        if is_index:
            front += ['template = "docs-section.html"', 'page_template = "docs-page.html"', 'sort_by = "title"']
            title = "Documentation"
            front[0] = f"title = {toml_str(title)}"
        (docs / page_file(p.stem)).write_text("+++\n" + "\n".join(front) + "\n+++\n\n" + body, encoding="utf-8")

    sidebar = wiki / "_Sidebar.md"
    if sidebar.exists():
        (site / "data").mkdir(exist_ok=True)
        (site / "data" / "docs-nav.toml").write_text(sidebar_to_toml(sidebar.read_text(encoding="utf-8"), pages), encoding="utf-8")

    if (wiki / "images").is_dir():
        shutil.copytree(wiki / "images", site / "static" / "docs" / "images", dirs_exist_ok=True)

    print(f"converted {len(pages)} pages into {docs}")


if __name__ == "__main__":
    main()
