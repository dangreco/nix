#!/usr/bin/env bash
# usage: release-notes.sh BASE HEAD
# Markdown changelog of BASE..HEAD, grouped by conventional-commit type.
# Merge commits are skipped; nightly flake.lock updates collapse into one line.
set -euo pipefail

base=$1
head=$2

breaking=() features=() fixes=() other=()
locks=0
while IFS=$'\t' read -r sha subject; do
  [ -n "$sha" ] || continue
  if [[ "$subject" =~ ^chore\(flake\):\ update\ flake\.lock ]]; then
    locks=$((locks + 1))
    continue
  fi
  line="$subject (${sha:0:7})"
  if [[ "$subject" =~ ^([a-z]+)(\(([^\)]*)\))?(!)?:\ (.*)$ ]]; then
    type=${BASH_REMATCH[1]}
    scope=${BASH_REMATCH[3]}
    bang=${BASH_REMATCH[4]}
    line="${scope:+**$scope:** }${BASH_REMATCH[5]} (${sha:0:7})"
    if [ -n "$bang" ]; then
      breaking+=("$line")
    else
      case "$type" in
        feat) features+=("$line") ;;
        fix) fixes+=("$line") ;;
        *) other+=("$type: $line") ;;
      esac
    fi
  else
    other+=("$line")
  fi
done < <(git log --no-merges --reverse --format='%H%x09%s' "$base..$head")

section() {
  local title=$1
  shift
  [ $# -gt 0 ] || return 0
  printf '### %s\n\n' "$title"
  printf -- '- %s\n' "$@"
  printf '\n'
}

section "Breaking changes" ${breaking[@]+"${breaking[@]}"}
section "Features" ${features[@]+"${features[@]}"}
section "Fixes" ${fixes[@]+"${fixes[@]}"}
if [ "$locks" -gt 0 ]; then
  plural=s
  [ "$locks" != 1 ] || plural=
  section "Dependencies" "Flake inputs updated ($locks nightly flake.lock update$plural)"
fi
section "Other" ${other[@]+"${other[@]}"}
