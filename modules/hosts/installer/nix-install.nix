{
  perSystem =
    { pkgs, ... }:
    {
      # op, nix and nixos-install come from the ISO PATH (_1password-cli is unfree).
      packages.nix-install = pkgs.writeShellApplication {
        name = "nix-install";
        runtimeInputs = [
          pkgs.gum
          pkgs.git
          pkgs.jq
          pkgs.nixos-facter
          pkgs.ssh-to-age
          pkgs.openssh
          pkgs.util-linux
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.findutils
          pkgs.curl
          pkgs.gawk
        ];
        text = builtins.readFile ./_nix-install.sh;
      };
    };
}
