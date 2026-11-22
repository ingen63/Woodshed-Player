#!/usr/bin/env bash
# Removes what aborted test runs left in the temporary directory ($TMPDIR): flutter_tools.* of
# flutter test/run/build (about 240 MB each, removed by Flutter only on a normal end) and the test
# directories of this project (wp_*, wp-run-*). Only entries in which nothing changed for
# CLEAN_TMP_MINUTES (default 60) go, so running tests and dev servers keep theirs. wp-mutants-* is
# the build cache of the mutation tests and stays. Other programs' entries are never touched.
# Usage: tools/clean-tmp.sh [-n]   (-n: only list)
set -euo pipefail

dry=0
[ "${1:-}" = "-n" ] && dry=1
tmp="${TMPDIR:-/tmp}"
tmp="${tmp%/}"
minutes="${CLEAN_TMP_MINUTES:-60}"

count=0
kib=0
shopt -s nullglob
for e in "$tmp"/flutter_tools.* "$tmp"/wp_* "$tmp"/wp-run-*; do
  [ -L "$e" ] && continue
  # still in use: something in it changed recently
  if [ -n "$(find "$e" -mmin "-$minutes" -print -quit 2>/dev/null)" ]; then
    continue
  fi
  size="$(du -sk "$e" 2>/dev/null | cut -f1 || true)"
  kib=$((kib + ${size:-0}))
  count=$((count + 1))
  if [ "$dry" -eq 1 ]; then
    echo "$e"
  else
    rm -rf "$e" 2>/dev/null || true
  fi
done

if [ "$count" -gt 0 ]; then
  verb="removed"
  [ "$dry" -eq 1 ] && verb="would remove"
  echo "clean-tmp: $verb $count entries, $((kib / 1024)) MB in $tmp"
fi
