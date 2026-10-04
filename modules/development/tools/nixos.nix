_: {
  # The Home Manager side of this feature is in home.nix. These directories hold state the
  # tools build up over time, and /home is wiped at boot unless it is persisted here.
  flake.modules.nixos.dev-tools =
    { config, lib, ... }:
    {
      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [
          ".local/share/zoxide" # learned directory ranking
          ".local/share/direnv" # which .envrc files are allowed
          ".cache/tealdeer" # downloaded tldr pages
        ];
      });
    };
}
