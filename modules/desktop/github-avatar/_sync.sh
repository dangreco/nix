# shellcheck shell=bash
# Set each user's AccountsService (GNOME) picture to their GitHub avatar.
#
#   github-avatar-sync <user>=<github-login>...
#
# Runs as root: polkit always authorizes uid 0, so SetIconFile works without a
# session. accounts-daemon reads the file in its own namespace (so it must not
# live in a private /tmp) and copies it byte for byte to $icons/<user>, so an
# identical file there means the picture is already current.

icons=/var/lib/AccountsService/icons
work=${RUNTIME_DIRECTORY:?run through github-avatar-sync.service}

log() { echo "github-avatar: $*" >&2; }

sync_user() {
  local user=$1 login=$2 img path
  img="$work/$user"
  if ! curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused --max-time 60 \
      -o "$img" "https://github.com/$login.png?size=512"; then
    log "$user: could not download the avatar of GitHub user $login"
    return 1
  fi
  if cmp -s "$img" "$icons/$user"; then
    log "$user: picture already matches GitHub user $login"
    return 0
  fi
  if ! path=$(busctl --json=short call org.freedesktop.Accounts /org/freedesktop/Accounts \
      org.freedesktop.Accounts FindUserByName s "$user" | jq -er '.data[0]'); then
    log "$user: not known to AccountsService"
    return 1
  fi
  if ! busctl call org.freedesktop.Accounts "$path" org.freedesktop.Accounts.User SetIconFile s "$img"; then
    log "$user: AccountsService rejected the picture"
    return 1
  fi
  log "$user: picture set from GitHub user $login"
}

[ "$#" -gt 0 ] || { log "usage: github-avatar-sync <user>=<github-login>..."; exit 2; }

failed=0
for pair in "$@"; do
  sync_user "${pair%%=*}" "${pair#*=}" || failed=1
done
exit "$failed"
