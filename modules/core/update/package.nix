_: {
  perSystem =
    { pkgs, inputs', ... }:
    let
      script = pkgs.writeShellApplication {
        name = "update";
        # nixos-rebuild, nix and sudo come from the host PATH. home-manager is the version
        # this flake pins, so `update` works before the first Home Manager switch too.
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jq
          pkgs.openssh
          inputs'.home-manager.packages.default
        ];
        text = builtins.readFile ./_update.sh;
      };

      # Picked up from share/fish/vendor_completions.d once the package is in systemPackages.
      completions = pkgs.writeTextDir "share/fish/vendor_completions.d/update.fish" (
        builtins.readFile ./_update.fish
      );
    in
    {
      packages.update = pkgs.symlinkJoin {
        name = "update";
        paths = [
          script
          completions
        ];
        meta.mainProgram = "update";
      };
    };
}
