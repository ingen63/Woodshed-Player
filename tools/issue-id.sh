#!/usr/bin/env bash
# Issue-IDs mit der GitHub-Nummer abgleichen: Issue #22 heisst «FEA-22 …», «ISS-22 …» oder «GEN-22 …».
#
#   tools/issue-id.sh new <FEA|ISS|GEN> "<Titel ohne ID>" <Datei mit Text> [weitere Labels, kommagetrennt]
#       legt das Issue an und setzt danach die ID mit der richtigen Nummer in den Titel.
#   tools/issue-id.sh sync [--apply]
#       zeigt Issues, deren ID fehlt oder nicht zur Nummer passt; mit --apply werden sie umbenannt.
#       Ohne Präfix im Titel entscheidet das Label: bug → ISS, feature → FEA, sonst GEN.
set -euo pipefail

label_for() {
  case "$1" in
    FEA) echo feature ;;
    ISS) echo bug ;;
    GEN) echo allgemein ;;
    *) echo "Unbekanntes Präfix: $1 (erlaubt: FEA, ISS, GEN)" >&2; exit 2 ;;
  esac
}

cmd_new() {
  [ $# -ge 3 ] || { sed -n '2,9p' "$0"; exit 2; }
  local prefix="$1" title="$2" body="$3" extra="${4:-}"
  local labels; labels="$(label_for "$prefix")${extra:+,$extra}"
  [ -f "$body" ] || { echo "Textdatei fehlt: $body" >&2; exit 2; }
  local url num
  url="$(gh issue create --title "$prefix-? $title" --body-file "$body" --label "$labels")"
  num="${url##*/}"
  gh issue edit "$num" --title "$prefix-$num $title" >/dev/null
  echo "Angelegt: #$num «$prefix-$num $title»  $url"
}

cmd_sync() {
  local apply="${1:-}" count=0
  while IFS=$'\t' read -r num title labels; do
    local prefix="" rest="$title"
    if [[ "$title" =~ ^(FEA|ISS|GEN)-[^[:space:]]*[[:space:]]+(.*)$ ]]; then
      prefix="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    elif [[ ",$labels," == *",bug,"* ]]; then prefix=ISS
    elif [[ ",$labels," == *",feature,"* ]]; then prefix=FEA
    else prefix=GEN
    fi
    local want="$prefix-$num $rest"
    if [ "$title" != "$want" ]; then
      count=$((count + 1))
      printf '#%s  «%s»  →  «%s»\n' "$num" "$title" "$want"
      if [ "$apply" = "--apply" ]; then gh issue edit "$num" --title "$want" >/dev/null; fi
    fi
  done < <(gh issue list --state all --limit 1000 --json number,title,labels \
             --jq '.[] | [.number, .title, ([.labels[].name] | join(","))] | @tsv')
  if [ "$count" -eq 0 ]; then echo "Alle Issue-IDs passen zur Nummer.";
  elif [ "$apply" = "--apply" ]; then echo "Umbenannt: $count Issues.";
  else echo "Trockenlauf: $count Issues würden umbenannt. Mit --apply ausführen."; fi
}

case "${1:-}" in
  new) shift; cmd_new "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
