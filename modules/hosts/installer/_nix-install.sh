# shellcheck shell=bash
usage() {
  echo "usage: nix-install [--repo DIR | --branch NAME] [--host NAME] [--host-key FILE] [--luks-file FILE] [--yes]" >&2
}

repo_url=https://github.com/dangreco/nix.git
push_url=git@github.com:dangreco/nix.git
repo=""      # --repo: local tree, no GitHub
branch=""    # --branch: default = remote HEAD
host=""
host_key=""
luks_file=""
yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--branch|--host|--host-key|--luks-file)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      case "$1" in
        --repo) repo=$2 ;;
        --branch) branch=$2 ;;
        --host) host=$2 ;;
        --host-key) host_key=$2 ;;
        --luks-file) luks_file=$2 ;;
      esac
      shift 2 ;;
    --yes) yes=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

die() { gum log --level error "$*"; exit 1; }
info() { gum log --level info "$*"; }
warn() { gum log --level warn "$*"; }
confirm() { [ "$yes" = 1 ] || gum confirm "$1"; }

[ "$yes" = 0 ] || [ -n "$host" ] || die "--yes requires --host"
[ -z "$repo" ] || [ -z "$branch" ] || die "--repo and --branch are mutually exclusive"
local_mode=0
[ -z "$repo" ] || local_mode=1

tmpkey=$(mktemp)
trap 'rm -f "$tmpkey" /tmp/secret.key' EXIT

op_signin() {
  op whoami >/dev/null 2>&1 && return 0
  op account list 2>/dev/null | grep -q . || op account add
  eval "$(op signin)"
}

ask_secret() {  # $1 prompt; result in $REPLY
  local s="" c
  printf '%s' "$1" >/dev/tty
  while IFS= read -rsn1 c </dev/tty; do
    case "$c" in
      "") break ;;
      $'\x7f'|$'\b')
        if [ -n "$s" ]; then s=${s%?}; printf '\b \b' >/dev/tty; fi ;;
      *) s+=$c; printf '*' >/dev/tty ;;
    esac
  done
  printf '\n' >/dev/tty
  REPLY=$s
}

# Whole disks, minus the one the ISO booted from: "NAME SIZE MODEL" per line.
list_disks() {
  local iso_src iso_disk="" name type size model
  iso_src=$(findmnt -no SOURCE /iso 2>/dev/null || true)
  if [ -n "$iso_src" ]; then
    iso_disk=$(lsblk -no PKNAME "$iso_src" 2>/dev/null | head -n1 || true)
  fi
  lsblk -dnpo NAME,TYPE,SIZE,MODEL -e 7,11 | while read -r name type size model; do
    [ "$type" = disk ] || continue
    [ -z "$iso_disk" ] || [ "${name#/dev/}" != "$iso_disk" ] || continue
    echo "$name $size $model"
  done
}

# Prefer a stable /dev/disk/by-id path over the raw device node.
stable_path() {
  local dev=$1 real best="" p base
  real=$(readlink -f "$dev")
  for p in /dev/disk/by-id/*; do
    [ -e "$p" ] || continue
    base=${p##*/}
    case "$base" in *-part*) continue ;; esac
    [ "$(readlink -f "$p")" = "$real" ] || continue
    case "$base" in
      nvme-eui.*|wwn-*|nvme-nvme.*) [ -n "$best" ] || best=$p ;;
      *) best=$p; break ;;
    esac
  done
  echo "${best:-$dev}"
}

# ---------------------------------------------------------------- 1. readiness
failed=0
check() {  # name, reason; stdin-less: runs "$@" after the first two args
  local name=$1 reason=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "✓ $name"
  else
    echo "✗ $name: $reason"
    failed=1
  fi
}
has_ram() { [ "$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)" -ge 2097152 ]; }
has_disk() { [ -n "$(list_disks)" ]; }

check root "run as root: sudo nix-install" [ "$EUID" = 0 ]
check x86_64 "unsupported architecture $(uname -m)" [ "$(uname -m)" = x86_64 ]
check uefi "boot the USB in UEFI mode" [ -d /sys/firmware/efi ]
check ram "need at least 2 GiB" has_ram
check network "cannot reach https://cache.nixos.org" curl -sfI --max-time 10 https://cache.nixos.org
if [ "$local_mode" = 1 ]; then
  check repo "no flake.nix in $repo" [ -f "$repo/flake.nix" ]
else
  check github "cannot reach $repo_url" git ls-remote --exit-code "$repo_url" HEAD
fi
check disk "no candidate disk found" has_disk
[ "$failed" = 0 ] || die "not ready"

setup_mode=$(od -An -tu1 /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | awk '{print $NF}' || true)
if [ "$setup_mode" = 1 ]; then
  echo "✓ secure-boot-setup-mode"
else
  warn "firmware not in Secure Boot setup mode; lanzaboote cannot auto-enroll keys. Clear PK/KEK/DB in firmware first."
  confirm "Continue anyway?" || exit 1
fi

# ---------------------------------------------------------------- 2. workspace
work=/tmp/nix-config
rm -rf "$work"
if [ "$local_mode" = 1 ]; then
  # /etc paths may be store symlinks; copy the real tree.
  cp -rT --no-preserve=mode,ownership "$(readlink -f "$repo")" "$work"
  git -C "$work" init -q
  git -C "$work" add -A
  git -C "$work" commit -qm "chore: baseline"
else
  git clone -q ${branch:+--branch "$branch"} "$repo_url" "$work"
  branch=$(git -C "$work" symbolic-ref --short HEAD)
  info "Cloned $repo_url ($branch @ $(git -C "$work" rev-parse --short HEAD))"
fi

keys=$(nix eval --json "$work#keys")
hosts=$(nix eval --json "$work#nixosConfigurations" --apply 'builtins.attrNames' | jq -r '.[] | select(. != "installer")')
mapfile -t host_arr <<<"$hosts"

# ---------------------------------------------------------------- 3. host and disk
if [ -n "$host" ]; then
  choice=$host
else
  choice=$(gum choose --header "Install which host?" "${host_arr[@]}" "+ New host")
fi

new_host=0
users_list=""
if [ "$choice" = "+ New host" ]; then
  new_host=1
  while true; do
    h=$(gum input --header "Hostname" --placeholder "e.g. tequila")
    if ! [[ "$h" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
      warn "hostname must match ^[a-z][a-z0-9-]{0,62}\$"
    elif grep -qx -- "$h" <<<"$hosts"; then
      warn "host $h already exists"
    else
      break
    fi
  done

  mapfile -t all_users < <(find "$work/modules/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  selected=$(IFS=,; echo "${all_users[*]}")
  users_list=$(gum choose --no-limit --selected="$selected" --header "Users on $h" "${all_users[@]}")
  [ -n "$users_list" ] || die "no users selected"

  mapfile -t disk_lines < <(list_disks)
  pick=$(gum choose --header "Install to which disk?" "${disk_lines[@]}")
  dev=${pick%% *}
  disk=$(stable_path "$dev")
  size_bytes=$(lsblk -bdno SIZE "$dev")
  [ "$size_bytes" -ge 17179869184 ] || die "$dev is smaller than 16 GiB"

  mkdir -p "$work/modules/hosts/$h"
  nixos-facter -o "$work/modules/hosts/$h/facter.json"
  chmod 0644 "$work/modules/hosts/$h/facter.json"

  op_signin
  item="$h.$(date +%Y.%m.%d)"
  title=$item
  op item create --category "SSH Key" --vault nix-hosts --title "$item" --ssh-generate-key ed25519 >/dev/null
  op read --force --out-file "$tmpkey" --file-mode 0600 "op://nix-hosts/$item/private key?ssh-format=openssh"
  age=$(ssh-keygen -y -f "$tmpkey" | ssh-to-age)

  users_nixos=""
  home_configs=""
  while read -r u; do
    [ -n "$u" ] || continue
    users_nixos+="${users_nixos:+ }nixos.$u"
    home_configs+="  flake.homeConfigurations.\"$u@@HOST@\" = mkHome [ hm.$u hm.desktop { my.onepassword.sshAgentItems = [ config.keys.hosts.@HOST@.opItem ]; } ];"$'\n'
  done <<<"$users_list"
  home_configs=${home_configs%$'\n'}

  tpl=$(cat <<'EOF'
{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
  mkHome = modules: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit modules;
  };
in
{
  keys.hosts.@HOST@ = { age = "@AGE@"; opItem = "@ITEM@"; };

  flake.modules.nixos.@HOST@ = {
    imports = [ nixos.desktop @USERS_NIXOS@ ];
    networking.hostName = "@HOST@";
    nixpkgs.hostPlatform = "x86_64-linux";
    my.disk.device = "@DISK@";
    hardware.facter.reportPath = ./facter.json;
    boot.lanzaboote.autoEnrollKeys.includeFirmwareBuiltinKeys = true;
  };

  flake.nixosConfigurations.@HOST@ = inputs.nixpkgs.lib.nixosSystem { modules = [ nixos.@HOST@ ]; };
@HOME_CONFIGS@
}
EOF
)
  tpl=${tpl//@USERS_NIXOS@/$users_nixos}
  tpl=${tpl//@HOME_CONFIGS@/$home_configs}
  tpl=${tpl//@DISK@/$disk}
  tpl=${tpl//@AGE@/$age}
  tpl=${tpl//@ITEM@/$item}
  tpl=${tpl//@HOST@/$h}
  printf '%s\n' "$tpl" > "$work/modules/hosts/$h/configuration.nix"
  git -C "$work" add -A

  (cd "$work" && nix run .#sops-config)
  git -C "$work" add -A
else
  h=$choice
  grep -qx -- "$h" <<<"$hosts" || die "unknown host $h"
  disk=$(nix eval --raw "$work#nixosConfigurations.$h.config.my.disk.device")
  [ -b "$disk" ] || die "$disk not present on this machine"
  dev=$(readlink -f "$disk")
  size_bytes=$(lsblk -bdno SIZE "$dev")

  facter="$work/modules/hosts/$h/facter.json"
  if [ -f "$facter" ] && [ "$yes" = 0 ] && confirm "Regenerate facter.json for $h?"; then
    nixos-facter -o "$facter"
    chmod 0644 "$facter"
  fi

  opitem=$(jq -r --arg h "$h" '.hosts[$h].opItem' <<<"$keys")
  title=$opitem
  if [ -n "$host_key" ]; then
    cp "$host_key" "$tmpkey"
  else
    op_signin
    op read --force --out-file "$tmpkey" --file-mode 0600 "op://nix-hosts/$opitem/private key?ssh-format=openssh"
  fi
  chmod 0600 "$tmpkey"
  want_age=$(jq -r --arg h "$h" '.hosts[$h].age' <<<"$keys")
  have_age=$(ssh-keygen -y -f "$tmpkey" | ssh-to-age)
  [ "$have_age" = "$want_age" ] || die "host key does not match keys.hosts.$h.age"
fi

# GitHub token, fetched before anything destructive.
if [ "$local_mode" = 0 ]; then
  op_signin
  gh_token=$(op read "op://Private/GitHub/token")
  gh_api() { curl -sf -H "Authorization: Bearer $gh_token" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"; }
  gh_api https://api.github.com/user >/dev/null || die "GitHub token at op://Private/GitHub/token was rejected"
fi

# ---------------------------------------------------------------- 4. LUKS passphrase
if [ -n "$luks_file" ]; then
  install -m 0600 "$luks_file" /tmp/secret.key
else
  while true; do
    ask_secret "LUKS passphrase: "
    p1=$REPLY
    if [ -z "$p1" ]; then warn "passphrase must not be empty"; continue; fi
    ask_secret "Confirm passphrase: "
    if [ "$REPLY" != "$p1" ]; then warn "passphrases do not match"; continue; fi
    (umask 077; printf '%s' "$p1" > /tmp/secret.key)
    unset p1 REPLY
    break
  done
fi

# ---------------------------------------------------------------- 5. final confirmation
model=$(lsblk -dno MODEL "$dev" | sed 's/[[:space:]]*$//')
summary="Host:  $h
Disk:  $disk -> $dev ($(numfmt --to=iec "$size_bytes"), ${model:-unknown model})"
if [ "$new_host" = 1 ]; then
  summary+="
Users: $(tr '\n' ' ' <<<"$users_list")"
fi
summary+="

ALL DATA ON THIS DISK WILL BE DESTROYED"
gum style --border rounded --padding "1 2" "$summary"
if [ "$yes" = 0 ]; then
  [ "$(gum input --header "Type the hostname to confirm")" = "$h" ] || die "aborted"
fi

# ---------------------------------------------------------------- 6. partition and install
git -C "$work" add -A
nix build "$work#nixosConfigurations.$h.config.system.build.diskoScript" -o /tmp/disko
/tmp/disko
install -d -m 0755 /mnt/persist/etc/ssh
install -m 0600 "$tmpkey" /mnt/persist/etc/ssh/ssh_host_ed25519_key
ssh-keygen -y -f "$tmpkey" > /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
nixos-install --flake "$work#$h" --no-root-passwd --no-channel-copy

# ---------------------------------------------------------------- 7. register key, push, leave ~/projects/nix
git -C "$work" add -A
if [ -n "$(git -C "$work" status --porcelain)" ]; then
  if [ "$new_host" = 1 ]; then msg="feat(hosts): add $h"; else msg="chore(hosts): update $h"; fi
  git -C "$work" commit -qm "$msg"
fi

if [ "$local_mode" = 0 ]; then
  pushed=0
  pub=$(ssh-keygen -y -f "$tmpkey" | cut -d' ' -f1,2)
  if gh_api "https://api.github.com/user/keys?per_page=100" | jq -e --arg k "$pub" 'any(.[]; .key == $k)' >/dev/null; then
    info "Host key already registered on GitHub"
    key_ok=1
  elif jq -n --arg t "$title" --arg k "$pub" '{title: $t, key: $k}' | gh_api -X POST https://api.github.com/user/keys -d @- >/dev/null; then
    info "Added SSH key '$title' to GitHub"
    key_ok=1
  else
    warn "could not add SSH key '$title' to GitHub (already used by another account or a deploy key?)"
    key_ok=0
  fi

  git -C "$work" remote set-url origin "$push_url"
  gitssh() { GIT_SSH_COMMAND="ssh -i $tmpkey -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=yes" git -C "$work" "$@"; }
  if [ "$key_ok" = 1 ] && [ "$(git -C "$work" rev-list --count "origin/$branch..HEAD")" -gt 0 ]; then
    for _ in 1 2 3 4 5 6; do
      if gitssh push -q origin "HEAD:$branch"; then pushed=1; break; fi
      sleep 5   # new keys can take a few seconds to become usable
      gitssh fetch -q origin "$branch" || continue
      if ! git -C "$work" merge-base --is-ancestor "origin/$branch" HEAD; then
        if ! git -C "$work" rebase -q "origin/$branch"; then
          git -C "$work" rebase --abort
          side="install/$h-$(date +%Y%m%d%H%M%S)"
          if gitssh push -q origin "HEAD:refs/heads/$side"; then
            warn "rebase onto $branch conflicted; pushed to branch $side instead"
          fi
          break
        fi
      fi
    done
    if [ "$pushed" = 1 ]; then info "Pushed $(git -C "$work" rev-parse --short HEAD) to $branch"; fi
  elif [ "$key_ok" = 1 ]; then
    info "No repo changes to push"
    pushed=1
  fi
  if [ "$pushed" = 0 ]; then warn "repo changes not pushed; after first login run: cd ~/projects/nix && git push"; fi
  git -C "$work" branch -q --set-upstream-to="origin/$branch"
fi

u=$(nix eval --json "$work#nixosConfigurations.$h.config.my.users" | jq -r '.[0]')
uid=$(nix eval --json "$work#nixosConfigurations.$h.config.users.users.$u.uid" | jq -r '.')
gid=$(nix eval --json "$work#nixosConfigurations.$h.config.users.groups.users.gid" | jq -r '.')
[ "$uid" != null ] || die "user $u has no fixed uid; cannot set up ~/projects/nix"

install -d -m 0700 -o "$uid" -g "$gid" "/mnt/persist/home/$u"
install -d -m 0755 -o "$uid" -g "$gid" "/mnt/persist/home/$u/projects"
dest=/mnt/persist/home/$u/projects/nix
rm -rf "$dest"
cp -a "$work" "$dest"
chown -R "$uid:$gid" "$dest"
info "Repo checked out at ~/projects/nix for $u"

shred -u /tmp/secret.key 2>/dev/null || rm -f /tmp/secret.key
info "Done. Remove the USB and reboot. The first boots enroll Secure Boot keys (auto-reboot); enter the LUKS passphrase each time."
