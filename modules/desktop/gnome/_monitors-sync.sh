# shellcheck shell=bash
# Persist a user's GNOME monitor layout and mirror it to the GDM greeter.
#
#   monitors-sync <restore|save> <user> <group> <home> [gdm]
#
# The file is copied, never linked: mutter saves with rename-replace, which
# turns an impermanence symlink into a plain file and fails with EBUSY on a bind mount.
# GDM 49 runs the greeter with XDG_CONFIG_HOME=/var/lib/gdm/seat0/config.
# Units run as root and only refuse symlinks: managed users are trusted (wheel).

usage="usage: monitors-sync <restore|save> <user> <group> <home> [gdm]"

log() { echo "monitors-sync: $*" >&2; }

{ [ "$#" -eq 4 ] || { [ "$#" -eq 5 ] && [ "$5" = gdm ]; }; } || { log "$usage"; exit 2; }

mode=$1 user=$2 group=$3 home=$4 gdm=${5:-}
live=$home/.config/monitors.xml
saved=/persist$home/.config/monitors.xml
greeter=/var/lib/gdm/seat0/config/monitors.xml

# copy <src> <dst> <owner> <group>
copy() {
  local src=$1 dst=$2 owner=$3 grp=$4
  if cmp -s "$src" "$dst"; then
    return 0
  fi
  if [ ! -d "${dst%/*}" ]; then
    install -d -o "$owner" -g "$grp" -m 0755 "${dst%/*}"
  fi
  if [ -L "$dst" ]; then
    log "$user: $dst is a symlink; refusing to write it"
    return 1
  fi
  install -o "$owner" -g "$grp" -m 0644 "$src" "$dst"
  log "$user: copied $src -> $dst"
}

regular() { [ -f "$1" ] && [ ! -L "$1" ]; }

rc=0
case "$mode" in
  restore)
    if [ -e "$live" ] || [ -L "$live" ]; then
      log "$user: $live exists, keeping it"
    elif regular "$saved"; then
      copy "$saved" "$live" "$user" "$group" || rc=1
    else
      log "$user: no saved monitors.xml"
    fi
    ;;
  save)
    if regular "$live"; then
      copy "$live" "$saved" "$user" "$group" || rc=1
    else
      log "$user: $live missing; nothing to save"
      exit 0
    fi
    ;;
  *)
    log "$usage"
    exit 2
    ;;
esac

if [ "$gdm" = gdm ] && regular "$live"; then
  copy "$live" "$greeter" root root || rc=1
fi
exit "$rc"
