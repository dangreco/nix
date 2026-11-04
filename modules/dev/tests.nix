{ config, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  # NixOS integration tests run by `nix flake check`, on the systemd-nspawn container
  # backend (NixOS 26.05): no VM and no KVM, so they also run on CI runners. The
  # daemon needs the uid-range feature, set in core/base for every host.
  #
  # A container shares the host kernel and has no initrd, bootloader or disk, so
  # the root wipe, LUKS, Secure Boot and hibernation stay with the full-install
  # smoke test (dev/smoke.nix). So does Home Manager: its activation registers the
  # generation through the nix daemon, which cannot run on the container's
  # read-only /nix/store. These tests cover the system side of the booted host.
  perSystem =
    { pkgs, ... }:
    let
      # Throwaway secrets for the test, generated at build time (never in the repo):
      # a host age key, and dan's sops file encrypted to it with the same layout as
      # secrets/users/dan.yaml.
      testSecrets =
        pkgs.runCommand "test-secrets"
          {
            nativeBuildInputs = [
              pkgs.age
              pkgs.sops
              pkgs.mkpasswd
            ];
          }
          ''
            export HOME=$TMPDIR
            mkdir $out
            age-keygen -o $out/host.key 2>/dev/null
            age-keygen -o user.key 2>/dev/null
            mkpasswd -m yescrypt test > $out/dan.hash
            cat > dan.yaml <<EOF
            users:
              dan:
                password: '$(cat $out/dan.hash)'
                age-key: |
            $(sed 's/^/      /' user.key)
            EOF
            sops --encrypt --age "$(age-keygen -y $out/host.key)" dan.yaml > $out/dan.yaml
          '';
    in
    {
      checks.nixos-base = pkgs.testers.runNixOSTest {
        name = "nixos-base";

        # core/base sets nixpkgs.config (allowUnfree), like on the real hosts.
        node.pkgsReadOnly = false;

        containers.machine =
          { lib, ... }:
          {
            imports = [
              nixos.base
              nixos.dan
            ];

            my.printing.enable = true;

            # The real recipients are host SSH keys; here the throwaway host key.
            # sops-nix refuses key files in the store, so copy it to /run before
            # the secrets are installed.
            sops.age.sshKeyPaths = lib.mkForce [ ];
            sops.age.keyFile = "/run/test-host.key";
            system.activationScripts = {
              testHostKey = lib.stringAfter [ "specialfs" ] ''
                install -m 0400 ${testSecrets}/host.key /run/test-host.key
              '';
              setupSecretsForUsers.deps = [ "testHostKey" ];
              setupSecrets.deps = [ "testHostKey" ];
            };
            # The files are build outputs; checking them at evaluation would need IFD.
            sops.validateSopsFiles = false;
            sops.secrets."users/dan/password".sopsFile = lib.mkForce "${testSecrets}/dan.yaml";
            sops.secrets."users/dan/age-key".sopsFile = lib.mkForce "${testSecrets}/dan.yaml";

            # zram needs a kernel module, which a container cannot load.
            zramSwap.enable = lib.mkForce false;
          };

        testScript = ''
          hash = open("${testSecrets}/dan.hash").read().strip()

          machine.start()
          machine.wait_for_unit("multi-user.target")

          with subtest("sops: system secrets decrypt with the host key"):
              machine.succeed("test -s /run/secrets/users/dan/age-key")
              t.assertEqual(
                  machine.succeed("stat -c %U /run/secrets/users/dan/age-key").strip(), "dan"
              )

          with subtest("users: dan exists, password hash from sops, fish as login shell"):
              machine.succeed(f"grep -qF 'dan:{hash}:' /etc/shadow")
              t.assertTrue(
                  machine.succeed("getent passwd dan").strip().endswith("/fish")
              )

          with subtest("printing: CUPS scheduler and Avahi run"):
              machine.wait_for_unit("avahi-daemon.service")
              machine.succeed("lpstat -r | grep -q 'scheduler is running'")
              machine.fail("systemctl cat cups-browsed.service")

          with subtest("nh: weekly clean is scheduled"):
              machine.succeed("systemctl is-active nh-clean.timer")
        '';
      };
    };
}
