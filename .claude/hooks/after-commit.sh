#!/usr/bin/env bash
# Claude-Code-Hook (PostToolUse auf Bash):
# Erkennt einen erfolgreichen `git commit`,
#  1. prüft das Format der Commit-Nachricht (FEA-22 … (#22), gleiche Nummer),
#  2. weist Claude an, bei Code-Änderungen den test-agent im Schnellmodus zu starten.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# Nur auf git commit reagieren
if ! printf '%s' "$cmd" | grep -Eq '(^|[;&|(][[:space:]]*|[[:space:]])git([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"
git rev-parse --verify -q HEAD >/dev/null || exit 0

subject="$(git log -1 --pretty=%s)"
sha="$(git rev-parse --short HEAD)"

# Commits des Agenten selbst ignorieren (keine Schleife)
case "$subject" in
  "test(auto):"*) exit 0 ;;
esac

reasons=()

# 1. Format: PRÄFIX-<n> Text (#<n>) mit gleicher Nummer
if [[ "$subject" =~ ^(FEA|ISS|GEN)-([0-9]+)\ .+\ \(#([0-9]+)\)$ ]]; then
  if [ "${BASH_REMATCH[2]}" != "${BASH_REMATCH[3]}" ]; then
    reasons+=("Commit $sha: ID-Nummer ${BASH_REMATCH[2]} und Issue-Nummer #${BASH_REMATCH[3]} stimmen nicht überein. Nicht amenden, sondern melden und fragen, was zu tun ist.")
  fi
else
  reasons+=("Commit $sha hat nicht das Format «FEA-22 Text (#22)» (siehe CLAUDE.md, Ablauf Schritt 5). Melde das und frage, ob es so bleiben soll; Historie nicht umschreiben.")
fi

# 2. Code-Änderungen? (Swift, später Dart/C++)
changed="$(git diff-tree --root --no-commit-id --name-only -r HEAD 2>/dev/null || true)"
code="$(printf '%s\n' "$changed" | grep -E '\.(swift|dart|c|cc|cpp|h|hpp|mm)$|project\.pbxproj$|pubspec\.yaml$|CMakeLists\.txt$' || true)"
# Reine Test-Commits brauchen keinen Agenten
non_test="$(printf '%s\n' "$code" | grep -vE '(Tests?/|/test/|_test\.dart$)' || true)"
if [ -n "$non_test" ]; then
  reasons+=("Commit $sha enthält Code-Änderungen. Starte jetzt den Subagenten test-agent im SCHNELLMODUS (siehe Agentenbeschreibung): Build für macOS und iOS-Simulator prüfen, vorhandene Tests der betroffenen Teile laufen lassen, fehlende Tests für die Änderungen in $sha ergänzen. Fasse danach sein Ergebnis kurz zusammen.")
fi

[ ${#reasons[@]} -eq 0 ] && exit 0

joined="$(printf '%s\n' "${reasons[@]}")"
jq -n --arg r "$joined" '{decision: "block", reason: $r}'
