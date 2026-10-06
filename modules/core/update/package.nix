_: {
  perSystem =
    { pkgs, ... }:
    let
      script = pkgs.writeShellApplication {
        name = "update";
        # nixos-rebuild, nix and sudo come from the host PATH.
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.openssh
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
