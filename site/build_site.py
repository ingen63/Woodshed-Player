#!/usr/bin/env python3
"""Builds the public GitHub Pages site (#50): start page, privacy policy and terms as HTML, W0 test page under w0/,
and with --app the built web app under app/ (#41).

Usage: python3 site/build_site.py <output dir> [--app <flutter build web output>]

The start page has an «App öffnen» button between <!--app--> and <!--/app-->; without --app (no tag to build
the app from) the button is removed, so the page never links to a missing app.

The person placeholders ({{CONTROLLER_NAME}}, {{CONTROLLER_ADDRESS}}, {{CONTACT_EMAIL}}) are filled from
environment variables of the same name (set from repository secrets in the Pages workflow). The build fails
if a variable is missing or empty, or if any placeholder ({{...}} or [...] without a link) is left in the HTML.
Standard library only: the Markdown converter covers the subset used in docs/DATENSCHUTZ.md and
docs/NUTZUNGSBEDINGUNGEN.md (headings, paragraphs, lists, bold, italic, code, links, hard line breaks).
"""
import html
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
PLACEHOLDERS = ("CONTROLLER_NAME", "CONTROLLER_ADDRESS", "CONTACT_EMAIL")
PAGES = {
    "datenschutz.html": ROOT / "docs" / "DATENSCHUTZ.md",
    "nutzungsbedingungen.html": ROOT / "docs" / "NUTZUNGSBEDINGUNGEN.md",
}


def inline(text: str) -> str:
    """Escapes text and renders inline Markdown (code, links, autolinks, bold, italic)."""
    out = []
    # Code spans first, so their content stays literal.
    for i, part in enumerate(re.split(r"`([^`]*)`", text)):
        if i % 2:
            out.append(f"<code>{html.escape(part)}</code>")
            continue
        s = html.escape(part, quote=False)
        s = re.sub(
            r"\[([^\]]+)\]\(([^)\s]+)\)",
            lambda m: f'<a href="{html.escape(html.unescape(m[2]))}">{m[1]}</a>',
            s,
        )
        s = re.sub(
            r"&lt;(https?://[^\s&]+)&gt;",
            lambda m: f'<a href="{m[1]}">{m[1]}</a>',
            s,
        )
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", s)
        out.append(s)
    return "".join(out)


def markdown_to_html(md: str) -> tuple[str, str]:
    """Returns (title, body HTML) for the Markdown subset of the legal texts."""
    title = ""
    blocks: list[str] = []
    para: list[str] = []
    items: list[str] = []

    def flush() -> None:
        if para:
            lines = []
            for line in para:
                hard = line.endswith("\\")
                lines.append(inline(line[:-1] if hard else line) + ("<br>" if hard else ""))
            blocks.append("<p>" + "\n".join(lines) + "</p>")
            para.clear()
        if items:
            blocks.append("<ul>\n" + "\n".join(f"<li>{inline(i)}</li>" for i in items) + "\n</ul>")
            items.clear()

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line:
            flush()
        elif m := re.match(r"(#{1,6}) (.*)", line):
            flush()
            level = len(m[1])
            if level == 1 and not title:
                title = m[2]
            blocks.append(f"<h{level}>{inline(m[2])}</h{level}>")
        elif line.startswith("- "):
            if para:
                flush()
            items.append(line[2:])
        elif items and raw.startswith("  "):
            items[-1] += " " + line.strip()
        else:
            if items:
                flush()
            para.append(line)
    flush()
    return title, "\n".join(blocks)


def fill_placeholders(text: str, values: dict[str, str]) -> str:
    for name, value in values.items():
        text = text.replace("{{" + name + "}}", html.escape(value))
    return text


def leftover_placeholders(page: str) -> list[str]:
    """Placeholders still in a page: {{...}} or text in square brackets."""
    return re.findall(r"\{\{[^}]*\}\}|\[[^\]<>]*\]", page)


def render(template: str, title: str, body: str) -> str:
    return template.replace("{{TITLE}}", html.escape(title)).replace("{{BODY}}", body)


def app_link(index: str, with_app: bool) -> str:
    """Keeps the content of the <!--app-->…<!--/app--> block when the app is published, else drops the block."""
    keep = r"\1" if with_app else ""
    return re.sub(r"<!--app-->(.*?)<!--/app-->\n?", keep, index, flags=re.S)


def main(argv: list[str], env: dict[str, str]) -> int:
    args = argv[1:]
    app_dir = None
    if len(args) == 3 and args[1] == "--app":
        app_dir = Path(args[2])
        args = args[:1]
    if len(args) != 1:
        print("usage: build_site.py <output dir> [--app <web build dir>]", file=sys.stderr)
        return 2
    if app_dir is not None and not (app_dir / "index.html").is_file():
        print(f"error: no web app in {app_dir} (index.html missing)", file=sys.stderr)
        return 1
    missing = [n for n in PLACEHOLDERS if not env.get(n, "").strip()]
    if missing:
        print(f"error: missing secrets: {', '.join(missing)}", file=sys.stderr)
        return 1
    values = {n: env[n].strip() for n in PLACEHOLDERS}

    out = Path(args[0])
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    template = (SITE / "page.html").read_text(encoding="utf-8")

    pages = {"index.html": app_link((SITE / "index.html").read_text(encoding="utf-8"), app_dir is not None)}
    for name, source in PAGES.items():
        title, body = markdown_to_html(source.read_text(encoding="utf-8"))
        pages[name] = render(template, title, body)

    failed = False
    for name, page in pages.items():
        page = fill_placeholders(page, values)
        left = leftover_placeholders(page)
        if left:
            print(f"error: placeholders left in {name}: {', '.join(sorted(set(left)))}", file=sys.stderr)
            failed = True
        (out / name).write_text(page, encoding="utf-8")
    if failed:
        return 1

    shutil.copy(SITE / "style.css", out / "style.css")
    shutil.copytree(ROOT / "web" / "w0", out / "w0")
    if app_dir is not None:
        shutil.copytree(app_dir, out / "app")
    print(f"site built in {out}: {', '.join(sorted(pages))}, style.css, w0/" + (", app/" if app_dir else ""))
    return 0


if __name__ == "__main__":
    import os

    sys.exit(main(sys.argv, dict(os.environ)))
