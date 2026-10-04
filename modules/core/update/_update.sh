# shellcheck shell=bash
usage() {
  cat <<'EOF'
usage: update [--pull]

Apply the flake in ~/projects/nix to this machine: NixOS first, then Home Manager.

  --pull       fast-forward the checkout to the latest origin/dev first
  -h, --help   show this message
EOF
}

pull=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pull) pull=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

repo=$HOME/projects/nix
branch=dev

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { echo "update: $*" >&2; exit 1; }

[ "$EUID" -ne 0 ] || die "run this as your own user, not root; sudo is used for the NixOS step"
[ -f "$repo/flake.nix" ] || die "no flake at $repo"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git checkout"

host=$(uname -n)
user=$(id -un)

# ---------------------------------------------------------------- pull
if [ "$pull" = 1 ]; then
  step "Pulling $branch into $repo"
  current=$(git -C "$repo" symbolic-ref --short -q HEAD || true)
  [ "$current" = "$branch" ] \
    || die "$repo is on '${current:-a detached HEAD}', not $branch; run: git -C $repo switch $branch"

  git -C "$repo" fetch --quiet origin "$branch" \
    || die "could not fetch origin/$branch (network down, or the SSH agent is not running?)"

  before=$(git -C "$repo" rev-parse --short HEAD)
  # Fast-forward only: never create a merge commit or touch local commits.
  git -C "$repo" merge --ff-only --quiet "origin/$branch" \
    || die "cannot fast-forward $branch to origin/$branch; resolve it in $repo"
  after=$(git -C "$repo" rev-parse --short HEAD)

  if [ "$before" = "$after" ]; then
    echo "already up to date at $after"
  else
    echo "$before -> $after"
    git -C "$repo" log --oneline --no-decorate "$before..$after"
  fi
fi

# ---------------------------------------------------------------- NixOS
step "NixOS ($host)"
# Not allowed to rewrite flake.lock: running as root, it would leave a root-owned file in the checkout.
sudo nixos-rebuild switch --flake "$repo#$host" --no-write-lock-file

# ---------------------------------------------------------------- Home Manager
step "Home Manager ($user@$host)"
configs=$(nix eval --json "$repo#homeConfigurations" --apply builtins.attrNames)
if jq -e --arg c "$user@$host" 'index($c) != null' <<<"$configs" >/dev/null; then
  home-manager switch --flake "$repo#$user@$host"
else
  echo "update: the flake has no Home Manager configuration '$user@$host'; skipping" >&2
fi
