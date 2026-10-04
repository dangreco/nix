{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    { config, ... }:
    {
      pre-commit.settings = {
        # Machine-written files: the lock file, facter reports, and the
        # byte-exact .sops.yaml compared by checks.sops-config.
        excludes = [
          "^flake\\.lock$"
          "^\\.sops\\.yaml$"
          "facter\\.json$"
        ];

        hooks = {
          # Nix
          nixfmt.enable = true;
          deadnix.enable = true;
          statix.enable = true;

          # Shell (writeShellApplication already shellchecks at build time;
          # this catches it before the build).
          shellcheck.enable = true;

          # Conventional commits (commit-msg stage)
          commitizen.enable = true;

          # Secrets: refuse unencrypted files under secrets/, and private keys anywhere.
          pre-commit-hook-ensure-sops.enable = true;
          detect-private-keys.enable = true;

          # Hygiene
          check-merge-conflicts.enable = true;
          check-added-large-files.enable = true;
          check-case-conflicts.enable = true;
          check-symlinks.enable = true;
          check-yaml.enable = true;
          mixed-line-endings.enable = true;
          end-of-file-fixer = {
            enable = true;
            excludes = [ "^secrets/" ]; # sops MAC covers the file bytes
          };
          trim-trailing-whitespace = {
            enable = true;
            excludes = [ "^secrets/" ];
          };
        };
      };

      formatter = config.pre-commit.settings.hooks.nixfmt.package;
    };
}
