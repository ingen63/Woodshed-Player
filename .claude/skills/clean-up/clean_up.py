#!/usr/bin/env python3
"""Aufräumen für Woodshed Player: GitHub-Workflow-Runs und lokaler Projektordner.

Ohne --apply wird nur angezeigt, was gelöscht würde (Zusammenfassung). Mit --apply wird gelöscht.

  clean_up.py runs  [--apply]   Workflow-Runs auf GitHub
  clean_up.py local [--apply]   Systemmüll und Build-Ordner im Projekt

Runs, die bleiben:
  - laufende oder wartende Runs (Status nicht «completed»),
  - je Workflow der neueste abgeschlossene Run,
  - Runs zu einem veröffentlichten Release (gleicher Tag oder gleicher Commit wie der Tag).

Lokal gelöscht werden:
  - .DS_Store und __pycache__ im ganzen Projekt (ohne .git und Build-Ordner),
  - die Build-Ordner ganz: Xcode-DerivedData dieses Projekts, build/, app/build/, app/.dart_tool/, core/build/.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKIP_DIRS = {".git", "build", ".dart_tool", "node_modules"}
DERIVED = Path.home() / "Library/Developer/Xcode/DerivedData"
BUILD_TOOLS = ("xcodebuild", "flutter", "dart", "cmake")


def gh(*args, check=True):
    r = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"gh {' '.join(args)} fehlgeschlagen: {r.stderr.strip()}")
    return r.stdout


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def dir_size(p):
    total = 0
    for dirpath, _, files in os.walk(p):
        for f in files:
            try:
                total += os.lstat(os.path.join(dirpath, f)).st_size
            except OSError:
                pass
    return total


# ---------- Workflow-Runs ----------

def release_refs():
    """Tags und Commits der veröffentlichten Releases (ohne Entwürfe)."""
    rels = json.loads(gh("release", "list", "--exclude-drafts", "--limit", "200", "--json", "tagName"))
    tags = {r["tagName"] for r in rels}
    shas = set()
    for t in tags:
        sha = gh("api", f"repos/{{owner}}/{{repo}}/commits/{t}", "--jq", ".sha", check=False).strip()
        if sha:
            shas.add(sha)
    return tags, shas


def runs(apply):
    lines = gh("api", "--paginate", "repos/{owner}/{repo}/actions/runs?per_page=100",
               "--jq", ".workflow_runs[] | @json")
    all_runs = [json.loads(l) for l in lines.splitlines() if l.strip()]
    all_runs.sort(key=lambda r: r["created_at"], reverse=True)
    tags, shas = release_refs()

    keep, delete, newest = [], [], set()
    for r in all_runs:
        why = None
        if r["status"] != "completed":
            why = "läuft noch"
        elif r["head_branch"] in tags or r["head_sha"] in shas:
            why = f"Release {r['head_branch'] if r['head_branch'] in tags else r['head_sha'][:7]}"
        elif r["workflow_id"] not in newest:
            why = "neuester des Workflows"
        if r["status"] == "completed":
            newest.add(r["workflow_id"])
        (keep if why else delete).append((r, why))

    def row(r, why=""):
        return (f"  {r['created_at'][:16].replace('T', ' ')}  {r['name'][:22]:22}  "
                f"{(r['conclusion'] or r['status'])[:10]:10}  {r['head_branch'] or '':12}  {r['head_sha'][:7]}"
                + (f"  ({why})" if why else ""))

    print(f"Workflow-Runs: {len(all_runs)} insgesamt, {len(keep)} bleiben, {len(delete)} werden gelöscht.")
    print(f"Veröffentlichte Releases: {', '.join(sorted(tags)) or 'keine'}\n")
    print("Bleiben:")
    for r, why in keep:
        print(row(r, why))
    print("\nWerden gelöscht:")
    by_wf = {}
    for r, _ in delete:
        by_wf[r["name"]] = by_wf.get(r["name"], 0) + 1
        print(row(r))
    if not delete:
        print("  (nichts)")
    else:
        print("\nJe Workflow: " + ", ".join(f"{k} {v}" for k, v in sorted(by_wf.items())))

    if apply and delete:
        failed = 0
        for r, _ in delete:
            res = subprocess.run(["gh", "api", "-X", "DELETE", f"repos/{{owner}}/{{repo}}/actions/runs/{r['id']}"],
                                 cwd=ROOT, capture_output=True, text=True)
            if res.returncode != 0:
                failed += 1
                print(f"  Fehler bei Run {r['id']}: {res.stderr.strip()}")
        print(f"\nGelöscht: {len(delete) - failed} Runs" + (f", {failed} Fehler" if failed else "") + ".")
    elif not apply:
        print("\nTrockenlauf: nichts gelöscht. Zum Löschen mit --apply aufrufen.")


# ---------- Lokaler Ordner ----------

def local_targets():
    junk = []
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for d in list(dirs):
            if d == "__pycache__":
                junk.append(Path(dirpath) / d)
                dirs.remove(d)
        for f in files:
            if f == ".DS_Store":
                junk.append(Path(dirpath) / f)
    builds = [p for p in (ROOT / "build", ROOT / "app" / "build", ROOT / "app" / ".dart_tool", ROOT / "core" / "build")
              if p.exists()]
    if DERIVED.is_dir():
        builds += sorted(p for p in DERIVED.glob("WoodshedPlayer-*") if p.is_dir())
    return junk, builds


def builds_running():
    pids = []
    for tool in BUILD_TOOLS:
        r = subprocess.run(["pgrep", "-x", tool], capture_output=True, text=True)
        pids += [f"{tool} {p}" for p in r.stdout.split()]
    return pids


def show(p):
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p).replace(str(Path.home()), "~")


def local(apply):
    junk, builds = local_targets()
    print("Lokal:\n")
    print(f"Systemmüll: {len(junk)} Einträge (.DS_Store, __pycache__)")
    for p in junk:
        print(f"  {show(p)}")
    print("\nBuild-Ordner (ganz):")
    total = 0
    for p in builds:
        s = dir_size(p)
        total += s
        print(f"  {show(p)}/  {human(s)}")
    if not builds:
        print("  (keine)")
    total += sum(dir_size(p) if p.is_dir() else p.stat().st_size for p in junk)
    print(f"\nFreier Platz danach: etwa {human(total)} mehr. Der nächste Build dauert länger.")

    busy = builds_running()
    if busy:
        print(f"\nACHTUNG: Es wird gerade gebaut ({', '.join(busy)}). Erst danach aufräumen.")
    if not apply:
        print("\nTrockenlauf: nichts gelöscht. Zum Löschen mit --apply aufrufen.")
        return
    if busy:
        sys.exit("Abgebrochen: Build läuft noch.")
    for p in junk:
        shutil.rmtree(p) if p.is_dir() else p.unlink()
    for p in builds:
        shutil.rmtree(p)
    print(f"\nGelöscht: {len(junk)} Einträge Systemmüll, {len(builds)} Build-Ordner.")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("runs", "local"):
        sys.exit(__doc__)
    apply = "--apply" in sys.argv[2:]
    (runs if sys.argv[1] == "runs" else local)(apply)
