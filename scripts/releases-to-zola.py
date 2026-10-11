#!/usr/bin/env python3
"""Writes one Zola page per GitHub release.

Usage: releases-to-zola.py RELEASES_JSON SITE_DIR

RELEASES_JSON is the output of
  gh api --paginate repos/OWNER/REPO/releases --jq '.[]' | jq -s .
Drafts are skipped; prereleases are kept and flagged. Existing generated
pages are replaced, so a release edited or deleted on GitHub is reflected
on the next build. Release bodies are GitHub-flavoured Markdown, wrapped in
{% raw %} so Zola does not read braces in them as template tags.
"""
import json
import sys
from pathlib import Path


def toml_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)


def protect_body(body: str) -> str:
    """Normalizes newlines and wraps the body in {% raw %}: Zola reads "{{",
    "{%" and "{#" in page content as Tera tags, and release notes are free text."""
    body = body.replace("\r\n", "\n").replace("{% endraw %}", "{ % endraw % }")
    return "{% raw %}" + body + "{% endraw %}" if body else body


def main() -> None:
    releases = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2]) / "content" / "releases"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.md"):
        if old.name != "_index.md":
            old.unlink()

    count = 0
    for r in releases:
        if r.get("draft"):
            continue
        tag = r["tag_name"]
        assets = [
            {"name": a["name"], "url": a["browser_download_url"], "size": a["size"]}
            for a in r.get("assets", [])
        ]
        front = [
            f"title = {toml_str(r.get('name') or tag)}",
            f"date = {r['published_at']}",
            f"slug = {toml_str(tag)}",
            "[extra]",
            f"tag = {toml_str(tag)}",
            f"url = {toml_str(r['html_url'])}",
            f"prerelease = {str(bool(r.get('prerelease'))).lower()}",
        ]
        for a in assets:
            front += ["[[extra.assets]]", f"name = {toml_str(a['name'])}", f"url = {toml_str(a['url'])}", f"size = {a['size']}"]
        body = protect_body(r.get("body") or "")
        (out / f"{tag}.md").write_text("+++\n" + "\n".join(front) + "\n+++\n\n" + body + "\n", encoding="utf-8")
        count += 1
    print(f"wrote {count} release pages into {out}")


if __name__ == "__main__":
    main()
