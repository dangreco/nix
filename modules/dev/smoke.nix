{ config, ... }:
let
  master = config.keys.master;
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      masterPub = pkgs.writeText "master.pub" master;

      # With IdentityFile pointing at a *public* key, ssh selects that key from the
      # 1Password agent, so other agent keys cannot exhaust MaxAuthTries.
      sshOpts = "-p 2222 -o IdentitiesOnly=yes -o IdentityFile=${masterPub} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5";
      scpOpts = "-P 2222 -o IdentitiesOnly=yes -o IdentityFile=${masterPub} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5";

      mkApp = args: {
        type = "app";
        program = lib.getExe (pkgs.writeShellApplication args);
      };
    in
    {
      apps = {
        smoke-vm = mkApp {
          name = "smoke-vm";
          runtimeInputs = [
            pkgs.qemu_kvm
            pkgs.coreutils
          ];
          text = ''
            usage() { echo "usage: smoke-vm [--iso PATH] [--reset]" >&2; }

            iso=""
            reset=0
            while [ $# -gt 0 ]; do
              case "$1" in
                --iso)
                  if [ $# -lt 2 ]; then usage; exit 2; fi
                  iso="$2"; shift 2 ;;
                --reset) reset=1; shift ;;
                *) usage; exit 2 ;;
              esac
            done

            state="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-smoke-vm"
            if [ "$reset" = 1 ]; then rm -rf "$state"; fi
            mkdir -p "$state"

            if [ ! -e "$state/disk.qcow2" ]; then
              qemu-img create -f qcow2 "$state/disk.qcow2" 20G
            fi
            if [ ! -e "$state/OVMF_VARS.fd" ]; then
              install -m 0644 ${pkgs.OVMFFull.variables} "$state/OVMF_VARS.fd"
            fi

            cdrom=()
            if [ -n "$iso" ]; then
              if [ ! -e "$iso" ]; then
                echo "smoke-vm: ISO not found: $iso" >&2
                exit 1
              fi
              cdrom=(-drive "file=$iso,media=cdrom,readonly=on,if=none,id=cd0" -device "ide-cd,drive=cd0,bootindex=0")
            fi

            echo "smoke-vm: quit QEMU with Ctrl-a x" >&2
            exec qemu-system-x86_64 -enable-kvm -machine q35,smm=on -cpu host -smp 4 -m 8192 \
              -global driver=cfi.pflash01,property=secure,value=on \
              -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMFFull.firmware} \
              -drive if=pflash,format=raw,unit=1,file="$state/OVMF_VARS.fd" \
              -drive file="$state/disk.qcow2",if=none,id=disk0,format=qcow2 -device virtio-blk-pci,drive=disk0,bootindex=1 \
              -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
              "''${cdrom[@]}" -nographic
          '';
        };

        smoke-install = mkApp {
          name = "smoke-install";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
          ];
          text = ''
            work=$(mktemp -d)
            trap 'rm -rf "$work"' EXIT
            # shellcheck disable=SC2086
            r() { ssh ${sshOpts} root@127.0.0.1 "$@"; }

            src=$(nix flake archive --json . | jq -r .path)
            NIX_SSHOPTS="${sshOpts}" nix copy --no-check-sigs --to ssh-ng://root@127.0.0.1 "$src"

            op read --out-file "$work/key" --file-mode 0600 "op://nix-hosts/$(nix eval --raw .#keys.hosts.smoke.opItem)/private key?ssh-format=openssh"
            printf '%s' smoke > "$work/luks"
            # shellcheck disable=SC2086
            scp ${scpOpts} "$work/key" "$work/luks" root@127.0.0.1:/tmp/

            r nix-install --repo "$src" --host smoke --host-key /tmp/key --luks-file /tmp/luks --yes
            r poweroff || true

            echo 'Installed. Restart without ISO: nix run .#smoke-vm   (LUKS passphrase: smoke)'
          '';
        };

        smoke-test = mkApp {
          name = "smoke-test";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = ''
            # shellcheck disable=SC2086
            r() { ssh ${sshOpts} root@127.0.0.1 "$@"; }
            # shellcheck disable=SC2086
            u() { ssh ${sshOpts} dan@127.0.0.1 "$@"; }

            wait_ssh() {
              local waited=0
              until r true >/dev/null 2>&1; do
                if [ "$waited" -ge 600 ]; then
                  echo "smoke-test: VM not reachable on 127.0.0.1:2222" >&2
                  exit 1
                fi
                sleep 5
                waited=$((waited + 5))
              done
            }

            wait_ssh

            if ! grep -q 'Secure Boot: enabled' <<<"$(r bootctl status 2>/dev/null)"; then
              echo "Secure Boot not enabled yet — let the VM finish its key-enrollment reboots, then rerun" >&2
              exit 1
            fi

            u 'echo eph > ~/eph-marker && echo keep > ~/Documents/keep-marker'
            mid=$(r cat /etc/machine-id)
            u 'podman pull -q docker.io/library/alpine:3 >/dev/null'
            r 'systemctl start flatpak-managed-install.service'

            r systemctl reboot || true
            sleep 15
            echo 'Type LUKS passphrase "smoke" in the smoke-vm terminal'
            wait_ssh

            fail=0
            verdict() {
              if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
            }

            rc=0; u 'test ! -e ~/eph-marker' || rc=$?
            verdict rollback "$rc"

            rc=0; [ "$(u 'cat ~/Documents/keep-marker')" = keep ] || rc=1
            verdict persist "$rc"

            rc=0; [ "$(r cat /etc/machine-id)" = "$mid" ] || rc=1
            verdict machine-id "$rc"

            rc=0; grep -q 'subvol=/root' <<<"$(r findmnt -no OPTIONS /)" || rc=$?
            verdict root-subvol "$rc"

            rc=0; grep -q 'Secure Boot: enabled' <<<"$(r bootctl status 2>/dev/null)" || rc=$?
            verdict secure-boot "$rc"

            rc=0; u 'test -r /run/secrets/users/dan/age-key' || rc=$?
            verdict system-sops "$rc"

            # Home Manager is part of the system: its activation service rebuilds ~ after the wipe.
            rc=0
            { [ "$(r systemctl is-active home-manager-dan.service)" = active ] \
              && u 'test -L ~/.config/git/config'; } || rc=$?
            verdict hm-activate "$rc"

            rc=1
            for _ in $(seq 1 12); do
              if [ "$(u 'cat ~/.config/sops-nix/secrets/users/dan/home/smoke' 2>/dev/null)" = smoke-ok ]; then rc=0; break; fi
              sleep 5
            done
            verdict hm-sops "$rc"

            rc=0; u 'podman image exists docker.io/library/alpine:3' || rc=$?
            verdict podman-persist "$rc"

            rc=0; [ "$(u 'podman run --rm docker.io/library/alpine:3 sh -c "wget -qO- http://example.com >/dev/null && echo ok"')" = ok ] || rc=1
            verdict podman-pasta "$rc"

            # `docker --version` prints "docker version X" under compat; `image exists` is podman-only.
            rc=0; u 'docker image exists docker.io/library/alpine:3' || rc=$?
            verdict docker-compat "$rc"

            rc=1
            for _ in $(seq 1 12); do
              if grep -qx flathub <<<"$(r 'flatpak remotes --system --columns=name' 2>/dev/null)"; then rc=0; break; fi
              sleep 5
            done
            verdict flatpak-remote "$rc"

            exit "$fail"
          '';
        };
      };
    };
}
