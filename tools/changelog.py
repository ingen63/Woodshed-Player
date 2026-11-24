"""#139: release notes in two languages.

CHANGELOG.md (German) is authoritative; CHANGELOG.en.md translates every version of it.

Usage (Python standard library only, like site/build_site.py):
  python3 tools/changelog.py check              findings with file and version; exit 1 if any, 2 unreadable input
  python3 tools/changelog.py notes <version>    text of the GitHub release for one version (v prefix allowed),
                                                English open, German folded; [-o FILE] writes it to a file;
                                                exit 1 if a language lacks the version (names file and language)
  python3 tools/changelog.py title <version>    title of the GitHub release, language-neutral: Woodshed Player 0.9.0
  python3 tools/changelog.py tag <tag>          the version of a release tag (v0.9.0 -> 0.9.0); exit 1 if the tag
                                                is no version tag or differs from the version in app/pubspec.yaml

Checks of `check` (the name in brackets appears in each finding):
- [versions]  every version heading is «## Version X.Y.Z», at most once per file; the translation has the same
              versions in the same order as the German file;
- [sections]  each entry uses only the section headings of its language, in the fixed order, at least one;
              the translation has the same sections per version as German;
- [issues]    every bullet («- ») of a section names at least one issue (#123); each section of a version names
              the same issue numbers in both languages.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_NAME = "Woodshed Player"
LANGS = ["de", "en"]
FILES = {"de": "CHANGELOG.md", "en": "CHANGELOG.en.md"}
LANG_NAMES = {"de": "German", "en": "English"}
# Section headings per language in their fixed order; the index is the section's identity across languages.
SECTIONS = {
    "de": ["Neu, geändert, behoben", "Tests und Entwicklung"],
    "en": ["New, changed, fixed", "Tests and development"],
}
# Order of the release text: English open first, German folded.
NOTES_ORDER = [("en", None), ("de", "Deutsch")]
PUBSPEC = "app/pubspec.yaml"

VERSION = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?"
VERSION_RE = re.compile(rf"^## Version ({VERSION})$")
TAG_RE = re.compile(rf"^v({VERSION})$")
TITLE_RE = re.compile(r"^v?(\d+\.\d+\.\d+)(?:-([A-Za-z]+)\.?(\d+)?)?$")
PUBSPEC_RE = re.compile(r"^version:\s*([^\s+]+)", re.MULTILINE)
ISSUE_RE = re.compile(r"#(\d+)")


class Finding:
    def __init__(self, file, where, check, reason):
        self.file, self.where, self.check, self.reason = file, where, check, reason

    def __str__(self):
        return f"{self.file} {self.where} [{self.check}]: {self.reason}"


def parse(text):
    """Returns [(version or None, heading line, body lines)] in file order; a «## » heading that is not
    «## Version X.Y.Z» gives version None. The body ends before the next «## » heading."""
    entries = []
    for line in text.splitlines():
        if line.startswith("## "):
            m = VERSION_RE.match(line)
            entries.append((m.group(1) if m else None, line, []))
        elif entries:
            entries[-1][2].append(line)
    return entries


def sections(body):
    """Returns [(heading, issue numbers, bullets without an issue)] for the «### » sections of an entry;
    text before the first section is an introduction and ignored."""
    result = []
    for line in body:
        if line.startswith("### "):
            result.append((line[4:].strip(), set(), []))
        elif result:
            numbers = {int(n) for n in ISSUE_RE.findall(line)}
            result[-1][1].update(numbers)
            if line.startswith("- ") and not numbers:
                result[-1][2].append(line[2:].strip())
    return result


def check_entry(file, lang, version, secs):
    """Yields findings for unknown, misordered or missing section headings and bullets without an issue."""
    known = SECTIONS[lang]
    if not secs:
        yield Finding(file, version, "sections", f"no section («### {known[0]}» …)")
        return
    indices = []
    for heading, _, bare in secs:
        if heading not in known:
            yield Finding(file, version, "sections", f"unknown section «{heading}» (allowed: {', '.join(known)})")
        else:
            indices.append(known.index(heading))
        for bullet in bare:
            yield Finding(file, version, "issues", f"«{heading}»: bullet without an issue number: «{bullet[:60]}»")
    if indices != sorted(set(indices)):
        yield Finding(file, version, "sections", f"sections not in the order {', '.join(known)} or repeated")


def load(root):
    """Returns the parsed entries per language."""
    data = {}
    for lang in LANGS:
        path = root / FILES[lang]
        if not path.exists():
            raise ValueError(f"{FILES[lang]} ({LANG_NAMES[lang]}) missing")
        data[lang] = parse(path.read_text(encoding="utf-8"))
    return data


def check_versions(file, entries):
    """Yields findings for headings that are no version heading and for repeated versions."""
    seen = set()
    for version, heading, _ in entries:
        if version is None:
            yield Finding(file, "file", "versions", f"heading is not «## Version X.Y.Z»: «{heading}»")
        elif version in seen:
            yield Finding(file, version, "versions", "version appears more than once")
        else:
            seen.add(version)


def section_issues(lang, body):
    """{section index: issue numbers} of the known sections of an entry."""
    return {SECTIONS[lang].index(h): issues for h, issues, _ in sections(body) if h in SECTIONS[lang]}


def run_checks(root):
    data = load(root)
    findings = []
    for lang in LANGS:
        file = FILES[lang]
        findings += check_versions(file, data[lang])
        for version, _, body in data[lang]:
            if version is not None:
                findings += check_entry(file, lang, version, sections(body))
    de = [(v, body) for v, _, body in data["de"] if v is not None]
    if not de:
        findings.append(Finding(FILES["de"], "file", "versions", "no version («## Version X.Y.Z»)"))
    de_versions = [v for v, _ in de]
    for lang in LANGS[1:]:
        file = FILES[lang]
        entries = [(v, body) for v, _, body in data[lang] if v is not None]
        versions = [v for v, _ in entries]
        if versions != de_versions:
            missing = [v for v in de_versions if v not in versions]
            extra = [v for v in versions if v not in de_versions]
            reason = f"versions {versions}, German {de_versions}"
            if missing:
                reason += f"; missing {missing}"
            if extra:
                reason += f"; not in German {extra}"
            findings.append(Finding(file, "file", "versions", reason))
        by_version = dict(entries)
        for version, de_body in de:
            if version not in by_version:
                continue
            de_secs = section_issues("de", de_body)
            tr_secs = section_issues(lang, by_version[version])
            if sorted(de_secs) != sorted(tr_secs):
                findings.append(
                    Finding(
                        file,
                        version,
                        "sections",
                        f"sections {[SECTIONS[lang][i] for i in sorted(tr_secs)]}, German "
                        f"{[SECTIONS['de'][i] for i in sorted(de_secs)]}",
                    )
                )
            for i in sorted(set(de_secs) & set(tr_secs)):
                if de_secs[i] != tr_secs[i]:
                    missing = sorted(de_secs[i] - tr_secs[i])
                    extra = sorted(tr_secs[i] - de_secs[i])
                    parts = []
                    if missing:
                        parts.append("missing " + ", ".join(f"#{n}" for n in missing))
                    if extra:
                        parts.append("not in German " + ", ".join(f"#{n}" for n in extra))
                    findings.append(Finding(file, version, "issues", f"«{SECTIONS[lang][i]}»: {'; '.join(parts)}"))
    return findings


def bare_version(version):
    return version[1:] if version.startswith("v") else version


def title(version):
    """Release title from the version: app name and version only, so it reads the same in every language;
    a pre-release label is capitalised and its number separated (0.9.0-beta.2 -> Woodshed Player 0.9.0 Beta 2)."""
    m = TITLE_RE.match(version)
    if not m:
        raise ValueError(f"version {version!r} is not X.Y.Z or X.Y.Z-label.N")
    parts = [APP_NAME, m.group(1)]
    if m.group(2):
        parts.append(m.group(2).capitalize())
    if m.group(3):
        parts.append(m.group(3))
    return " ".join(parts)


def notes(root, version):
    """The release text of one version: English open, German in a <details> block. Raises ValueError naming
    the file and the language of every language that lacks the version."""
    version = bare_version(version)
    bodies, missing = {}, []
    for lang, _ in NOTES_ORDER:
        path = root / FILES[lang]
        if not path.exists():
            missing.append(f"{FILES[lang]} ({LANG_NAMES[lang]}) missing")
            continue
        entries = {v: body for v, _, body in parse(path.read_text(encoding="utf-8")) if v is not None}
        if version in entries:
            bodies[lang] = "\n".join(entries[version]).strip()
        else:
            missing.append(f"{FILES[lang]} ({LANG_NAMES[lang]}): version {version} missing")
    if missing:
        raise ValueError("; ".join(missing))
    parts = []
    for lang, label in NOTES_ORDER:
        body = bodies[lang]
        if label is None:
            parts.append(body)
        else:
            parts.append(f"<details>\n<summary>{label}</summary>\n\n{body}\n\n</details>")
    return "\n\n".join(parts) + "\n"


def tag_version(root, tag):
    """The version of release tag [tag]; it must be «vX.Y.Z» and equal the version in app/pubspec.yaml, which
    the About dialog shows (#139/AK4)."""
    m = TAG_RE.match(tag)
    if not m:
        raise ValueError(f"tag {tag!r} is not vX.Y.Z")
    pubspec = PUBSPEC_RE.search((root / PUBSPEC).read_text(encoding="utf-8"))
    if not pubspec:
        raise ValueError(f"{PUBSPEC}: no version")
    if pubspec.group(1) != m.group(1):
        raise ValueError(f"tag {tag} differs from version {pubspec.group(1)} in {PUBSPEC}")
    return m.group(1)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=str(ROOT))
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    n = sub.add_parser("notes")
    n.add_argument("version")
    n.add_argument("-o", "--output")
    sub.add_parser("title").add_argument("version")
    sub.add_parser("tag").add_argument("tag")
    args = ap.parse_args(argv)
    root = pathlib.Path(args.root)
    if args.command in ("title", "tag", "notes"):
        try:
            if args.command == "title":
                text = title(args.version) + "\n"
            elif args.command == "tag":
                text = tag_version(root, args.tag) + "\n"
            else:
                text = notes(root, args.version)
        except (OSError, ValueError) as err:
            print(f"changelog: {err}", file=sys.stderr)
            return 1
        if getattr(args, "output", None):
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        else:
            sys.stdout.write(text)
        return 0
    try:
        findings = run_checks(root)
    except (OSError, ValueError) as err:
        print(f"changelog: {err}")
        return 2
    for finding in findings:
        print(finding)
    print(f"changelog: {len(findings)} findings")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
