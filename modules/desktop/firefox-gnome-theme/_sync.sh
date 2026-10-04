# shellcheck shell=bash
# Keep rafaelmardojai/firefox-gnome-theme current and applied to every Firefox
# profile of the calling user.
#
#   firefox-gnome-theme-sync update   resolve $FIREFOX_GNOME_THEME_REF, download it if new, apply
#   firefox-gnome-theme-sync apply    apply the cached theme only (no network)
#
# Profiles are found through profiles.ini (relative and absolute paths) and by
# scanning the Firefox directories, which also catches Selectable Profiles that
# profiles.ini does not list. Firefox 147+ uses ~/.config/mozilla/firefox on fresh
# installs and keeps ~/.mozilla/firefox on existing ones, so both are searched.
#
# The preferences the theme needs are set by Firefox policy (see nixos.nix), not
# by editing user.js.

repo=rafaelmardojai/firefox-gnome-theme
ref=${FIREFOX_GNOME_THEME_REF:-master}
mode=${1:-update}

data=${XDG_DATA_HOME:-$HOME/.local/share}/firefox-gnome-theme
config=${XDG_CONFIG_HOME:-$HOME/.config}

roots=(
  "$config/mozilla/firefox"
  "$HOME/.mozilla/firefox"
  "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
  "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
  "$HOME/snap/firefox/common/.mozilla/firefox"
)

begin_marker='/* BEGIN firefox-gnome-theme (managed, do not edit this block) */'
end_marker='/* END firefox-gnome-theme */'

log() { echo "firefox-gnome-theme: $*" >&2; }

case "$mode" in
  update | apply) ;;
  *) echo "usage: firefox-gnome-theme-sync [update|apply]" >&2; exit 2 ;;
esac

mkdir -p "$data"
exec 9>"$data/.lock"
flock -w 600 9 || { log "could not get the lock"; exit 1; }

# Newest commit for $ref (a branch, or a tag; annotated tags are peeled).
resolve_rev() {
  local refs
  refs=$(git ls-remote --heads --tags "https://github.com/$repo.git") || return 1
  awk -v ref="$ref" '
    $2 == "refs/heads/" ref || $2 == "refs/tags/" ref { plain = $1 }
    $2 == "refs/tags/" ref "^{}" { peeled = $1 }
    END { print (peeled != "" ? peeled : plain) }
  ' <<<"$refs"
}

# Download the tree for commit $1 into $data/$1; commit archives never change.
fetch_rev() {
  local rev=$1 tmp f
  [ -d "$data/$rev" ] && return 0
  tmp=$(mktemp -d "$data/.fetch.XXXXXX")
  if ! curl --fail --silent --show-error --location \
      --retry 5 --retry-delay 5 --retry-connrefused --max-time 180 \
      "https://codeload.github.com/$repo/tar.gz/$rev" \
      | tar -xz --strip-components=1 -C "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  for f in userChrome.css userContent.css theme/gnome-theme.css; do
    if [ ! -s "$tmp/$f" ]; then
      log "downloaded theme is missing $f, discarding it"
      rm -rf "$tmp"
      return 1
    fi
  done
  chmod 0755 "$tmp"
  mv -T "$tmp" "$data/$rev"
}

# Point $data/current at $1 and drop every other cached revision.
make_current() {
  local rev=$1 dir name
  ln -sfn "$rev" "$data/.current.new"
  mv -T "$data/.current.new" "$data/current"
  # Only real revision directories: the 'current' symlink and the temp dirs stay.
  for dir in "$data"/*/; do
    dir=${dir%/}
    name=$(basename "$dir")
    if [ ! -L "$dir" ] && [[ "$name" =~ ^[0-9a-f]{40}$ ]] && [ "$name" != "$rev" ]; then
      rm -rf "$dir"
    fi
  done
}

# Profile directories of every Firefox root, NUL separated and de-duplicated.
discover_profiles() {
  local root
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    if [ -f "$root/profiles.ini" ]; then
      awk -v root="$root" '
        BEGIN { rel = 1 }
        function flush() {
          if (in_profile && path != "") printf "%s\0", (rel ? root "/" : "") path
          in_profile = 0; path = ""; rel = 1
        }
        /^\[/ { flush(); in_profile = ($0 ~ /^\[Profile[0-9]+\][ \t\r]*$/); next }
        in_profile && /^Path=/ { path = substr($0, 6); sub(/\r$/, "", path) }
        in_profile && /^IsRelative=/ { rel = ($0 !~ /^IsRelative=0/) }
        END { flush() }
      ' "$root/profiles.ini"
    fi
    find "$root" -mindepth 2 -maxdepth 2 -name prefs.js -printf '%h\0'
  done | sort -zu
}

# Make $1 start with a managed @import of $2, keeping everything else in the file.
# @import has to come first in a stylesheet, hence the block at the top.
ensure_import() {
  local file=$1 import=$2 tmp
  if [ -L "$file" ]; then
    log "$file is a symlink, leaving it alone"
    return 0
  fi
  tmp=$(mktemp "$file.XXXXXX") || return 1
  {
    printf '%s\n@import "firefox-gnome-theme/%s";\n%s\n' "$begin_marker" "$import" "$end_marker"
    # Old managed block, plus the plain import lines the upstream install script adds.
    if [ -f "$file" ]; then
      awk -v b="$begin_marker" -v e="$end_marker" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip && $0 !~ /^@import "firefox-gnome-theme\// { print }
      ' "$file"
    fi
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
  else
    chmod 0644 "$tmp"
    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    log "updated $file"
  fi
}

apply_profile() {
  local profile=$1 rev=$2 chrome new old
  chrome=$profile/chrome
  mkdir -p "$chrome" || return 1

  if [ "$(cat "$chrome/firefox-gnome-theme/.rev" 2>/dev/null || true)" != "$rev" ]; then
    new=$chrome/.firefox-gnome-theme.new
    old=$chrome/.firefox-gnome-theme.old
    rm -rf "$new" "$old"
    mkdir "$new" || return 1
    cp -R --no-preserve=mode,ownership \
      "$data/$rev/userChrome.css" "$data/$rev/userContent.css" "$data/$rev/theme" "$new/" \
      || { rm -rf "$new"; return 1; }
    printf '%s\n' "$rev" > "$new/.rev" || { rm -rf "$new"; return 1; }
    chmod -R u+rwX,go+rX "$new"
    if [ -e "$chrome/firefox-gnome-theme" ]; then
      mv -T "$chrome/firefox-gnome-theme" "$old" || { rm -rf "$new"; return 1; }
    fi
    if ! mv -T "$new" "$chrome/firefox-gnome-theme"; then
      [ -e "$old" ] && mv -T "$old" "$chrome/firefox-gnome-theme"
      rm -rf "$new"
      return 1
    fi
    rm -rf "$old"
    log "installed ${rev:0:12} into $profile"
  fi

  ensure_import "$chrome/userChrome.css" userChrome.css || return 1
  ensure_import "$chrome/userContent.css" userContent.css || return 1
}

if [ "$mode" = update ]; then
  if rev=$(resolve_rev) && [[ "$rev" =~ ^[0-9a-f]{40}$ ]] && fetch_rev "$rev"; then
    make_current "$rev"
  elif [ -L "$data/current" ]; then
    log "could not update (offline, or '$ref' is gone); applying the cached theme"
  else
    log "could not download the theme and there is no cached copy"
    exit 1
  fi
fi

if [ ! -L "$data/current" ]; then
  log "no cached theme yet; run 'update' first"
  exit 1
fi
current=$(readlink "$data/current")

failed=0
count=0
while IFS= read -r -d '' profile; do
  if [ ! -d "$profile" ] || [ ! -w "$profile" ]; then
    log "skipping unusable profile $profile"
    continue
  fi
  count=$((count + 1))
  apply_profile "$profile" "$current" || { log "failed to apply to $profile"; failed=1; }
done < <(discover_profiles)

log "theme ${current:0:12} checked on $count profile(s)"
exit "$failed"
