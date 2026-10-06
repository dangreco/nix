# shellcheck shell=bash
usage() {
  cat <<'EOF'
usage: update [--pull] [--verbose]

Apply the flake in ~/projects/nix to this machine (NixOS, including every user's Home Manager config).
Each step shows only the last three lines of its output; a failed step prints more.

  --pull       fast-forward the checkout to the latest origin/dev first
  --verbose    print the full output of every step instead of the box
  -h, --help   show this message
EOF
}

pull=0
verbose=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pull) pull=1; shift ;;
    --verbose) verbose=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

repo=$HOME/projects/nix
branch=dev
tail_lines=3

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { echo "update: $*" >&2; exit 1; }

[ "$EUID" -ne 0 ] || die "run this as your own user, not root; sudo is used for the NixOS step"
if [ "$pull" = 1 ] && [ ! -d "$repo/.git" ]; then
  step "Cloning $branch into $repo"
  mkdir -p "$(dirname "$repo")"
  git clone -b "$branch" --quiet https://github.com/dangreco/nix.git "$repo" \
    || die "could not clone https://github.com/dangreco/nix.git"
fi

[ -f "$repo/flake.nix" ] || die "no flake at $repo"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git checkout"

host=$(uname -n)
user=$(id -un)

# Output with colours and carriage-return progress redraws flattened to plain lines.
clean() {
  tr '\r' '\n' | sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\x1b\][^\x07]*\x07//g' | grep -v '^[[:space:]]*$' || true
}

# run_boxed TITLE CMD...: run CMD with its output in a rolling box, so a long build
# cannot fill the screen. Falls back to plain output without a terminal.
run_boxed() {
  local title=$1 log pid rc=0 cols inner box_lines=$((tail_lines + 2))
  shift
  step "$title"
  if [ "$verbose" = 1 ] || [ ! -t 1 ]; then
    "$@"
    return
  fi

  read -r _ cols < <(stty size 2>/dev/null || echo "24 80")
  [ "$cols" -ge 30 ] || cols=80
  inner=$((cols - 4))
  log=$(mktemp "${TMPDIR:-/tmp}/update.XXXXXX.log")

  "$@" >"$log" 2>&1 </dev/null &
  pid=$!
  trap 'kill "$pid" 2>/dev/null; printf "\033[%dA\033[J\033[?25h" "$box_lines"; echo "update: interrupted during $title" >&2; exit 130' INT TERM
  printf '\033[?25l'

  local first=1 i line dashes lines
  while :; do
    # Only the end of the log matters, and it can be megabytes long.
    mapfile -t lines < <(tail -c 16384 "$log" | clean | tail -n "$tail_lines")
    [ "$first" = 1 ] || printf '\033[%dA' "$box_lines"
    first=0
    dashes=$(printf '%*s' $((cols - 5 - ${#title})) '' | tr ' ' '-')
    printf '\033[2K+- %s %s+\n' "${title:0:$((cols - 6))}" "$dashes"
    for ((i = 0; i < tail_lines; i++)); do
      line=${lines[i]:-}
      printf '\033[2K| %-*s |\n' "$inner" "${line:0:$inner}"
    done
    printf '\033[2K+%s+\n' "$(printf '%*s' $((cols - 2)) '' | tr ' ' '-')"
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  wait "$pid" || rc=$?
  trap - INT TERM

  # Replace the box with a one-line result.
  printf '\033[%dA\033[J\033[?25h' "$box_lines"
  if [ "$rc" = 0 ]; then
    printf '\033[32m✓\033[0m %s\n' "$title"
    rm -f "$log"
  else
    printf '\033[31m✗\033[0m %s failed (exit %d); last 40 lines:\n' "$title" "$rc"
    clean <"$log" | tail -n 40 | cut -c "1-$((cols - 2))" | sed 's/^/  /'
    echo "  full output: $log"
    return "$rc"
  fi
}

# ---------------------------------------------------------------- pull
if [ "$pull" = 1 ]; then
  step "Pulling $branch into $repo"
  current=$(git -C "$repo" symbolic-ref --short -q HEAD || true)
  [ "$current" = "$branch" ] \
    || die "$repo is on '${current:-a detached HEAD}', not $branch; run: git -C $repo switch $branch"

  git -C "$repo" fetch --quiet https://github.com/dangreco/nix.git "$branch" \
    || die "could not fetch https://github.com/dangreco/nix.git (network down?)"

  before=$(git -C "$repo" rev-parse --short HEAD)
  # Fast-forward only: never create a merge commit or touch local commits.
  git -C "$repo" merge --ff-only --quiet FETCH_HEAD \
    || die "cannot fast-forward $branch to remote; resolve it in $repo"
  after=$(git -C "$repo" rev-parse --short HEAD)

  if [ "$before" = "$after" ]; then
    echo "already up to date at $after"
  else
    echo "$before -> $after"
    git -C "$repo" log --oneline --no-decorate "$before..$after"
  fi
fi
# Home Manager is part of the NixOS configuration, so this one step updates every
# user's home too.
[ "$user" = "dan" ] || die "user '$user' is not a main user; ask dan to run update (it covers every user's Home Manager config)"

# ---------------------------------------------------------------- sudo
# The boxed steps run in the background with no terminal input, so a password prompt
# would hang. Ask once here; the cached credential covers the NixOS step.
if [ "$verbose" = 0 ] && [ -t 1 ]; then
  sudo -v || die "sudo authentication failed"
fi

# ---------------------------------------------------------------- NixOS
# Not allowed to rewrite flake.lock: running as root, it would leave a root-owned file in the checkout.
run_boxed "NixOS ($host)" sudo nixos-rebuild switch --flake "$repo#$host" --no-write-lock-file
