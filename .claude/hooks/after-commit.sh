#!/usr/bin/env bash
# Claude-Code-Hook (PostToolUse auf Bash) nach einem erfolgreichen `git commit`:
#  1. prüft das Format der Commit-Nachricht (Titel (#22), ohne eigenes Präfix),
#  2. baut und testet die betroffenen Teile selbst (kostet keine Tokens),
#  3. ruft den test-agent nur, wenn etwas fehlschlägt oder geänderte Logik ohne Tests committet wurde.
# Ausgaben der Builds landen in einer Logdatei; an Claude gehen nur die letzten Fehlerzeilen.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# Nur auf git commit reagieren
if ! printf '%s' "$cmd" | grep -Eq '(^|[;&|(][[:space:]]*|[[:space:]])git([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --verify -q HEAD >/dev/null || exit 0

subject="$(git log -1 --pretty=%s)"
sha="$(git rev-parse --short HEAD)"

# Commits des Agenten selbst ignorieren (keine Schleife)
case "$subject" in
  "test(auto):"*) exit 0 ;;
esac

reasons=()

# 1. Format: Titel (#<n>), ohne Präfix wie «FEA-22» (GitHub-Konvention, siehe CLAUDE.md)
if [[ ! "$subject" =~ ^.+\ \(#[0-9]+\)$ ]]; then
  reasons+=("Commit $sha hat nicht das Format «Titel (#22)». Melde das und frage, ob es so bleiben soll; Historie nicht umschreiben.")
elif [[ "$subject" =~ ^(FEA|ISS|GEN)-[0-9]+\  ]]; then
  reasons+=("Commit $sha beginnt mit einem alten Präfix (FEA/ISS/GEN). Neu nur «Titel (#22)». Melde das; Historie nicht umschreiben.")
fi

# 2. Was hat sich geändert?
changed="$(git diff-tree --root --no-commit-id --name-only -r HEAD 2>/dev/null || true)"
has() { printf '%s\n' "$changed" | grep -Eq "$1"; }

code_re='\.(swift|dart|c|cc|cpp|h|hpp|mm)$|project\.pbxproj$|pubspec\.yaml$|CMakeLists\.txt$'
test_re='(Tests?/|/tests?/|_tests?\.(dart|cpp)$)'
code="$(printf '%s\n' "$changed" | grep -E "$code_re" || true)"
non_test="$(printf '%s\n' "$code" | grep -vE "$test_re" || true)"

steps=()   # «Name|Befehl»
if [ -n "$non_test" ] || [ -n "$code" ]; then
  if has '^core/'; then
    steps+=("C++-Kern bauen|cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release && cmake --build core/build")
    steps+=("C++-Tests (ctest)|ctest --test-dir core/build --output-on-failure")
  fi
  if has '^(app|core)/'; then
    steps+=("flutter analyze|cd app && flutter analyze --no-pub")
    steps+=("flutter test|cd app && flutter test --reporter failures-only")
  fi
  if has '^(core/(src|include)/|core/CMakeLists\.txt|app/(packages|macos|ios)/|app/pubspec\.yaml)'; then
    steps+=("Flutter-Build macOS|cd app && flutter build macos --debug")
    steps+=("Flutter-Build iOS-Simulator|cd app && flutter build ios --simulator --debug")
  fi
  if has '^(WoodshedPlayer|WoodshedPlayerTests|WoodshedPlayer\.xcodeproj)/'; then
    steps+=("Swift-Tests macOS|xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'platform=macOS' -quiet test")
    steps+=("Swift-Build iOS-Simulator|xcodebuild -project WoodshedPlayer.xcodeproj -scheme WoodshedPlayer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet build")
  fi
fi

logdir="${TMPDIR:-/tmp}/woodshed-hook"
mkdir -p "$logdir"
ok=()
failed=""
for s in "${steps[@]+"${steps[@]}"}"; do
  name="${s%%|*}"; run="${s#*|}"
  log="$logdir/$sha-$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_').log"
  if (eval "$run") >"$log" 2>&1; then
    ok+=("$name")
  else
    failed="$name"
    tail_lines="$(grep -E 'error|Error|FAIL|failed|Failed|✗|Expectation' "$log" | tail -25)"
    [ -z "$tail_lines" ] && tail_lines="$(tail -25 "$log")"
    reasons+=("Commit $sha: «$name» ist fehlgeschlagen (ganzes Log: $log). Letzte Fehlerzeilen:
$tail_lines
Ursache im Produktivcode prüfen und beheben oder melden. Den test-agent nur starten, wenn ein Test wegen beabsichtigter Verhaltensänderung veraltet ist.")
    break
  fi
done

# 3. Geänderte Logik ohne Tests im Commit? Dann Tests vom test-agent schreiben lassen (Builds sind schon geprüft).
logic="$(printf '%s\n' "$non_test" | grep -E '^(core/(src|include)/|app/lib/|app/packages/[^/]+/lib/|WoodshedPlayer/(Audio|Model)/)' || true)"
tests_in_commit="$(printf '%s\n' "$code" | grep -E "$test_re" || true)"
if [ -z "$failed" ] && [ -n "$logic" ] && [ -z "$tests_in_commit" ]; then
  reasons+=("Commit $sha ändert Logik ohne Tests (${logic//$'\n'/, }). Build und vorhandene Tests sind grün (${ok[*]:-keine Schritte}). Starte den Subagenten test-agent im SCHNELLMODUS: nur fehlende Tests für $sha schreiben, Builds nicht wiederholen. Fasse sein Ergebnis in zwei, drei Sätzen zusammen.")
fi

if [ ${#reasons[@]} -gt 0 ]; then
  joined="$(printf '%s\n\n' "${reasons[@]}")"
  jq -n --arg r "$joined" '{decision: "block", reason: $r}'
elif [ ${#ok[@]} -gt 0 ]; then
  jq -n --arg c "Hook nach Commit $sha: grün (${ok[*]})." \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
exit 0
