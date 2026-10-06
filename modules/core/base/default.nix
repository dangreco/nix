{
  config,
  inputs,
  self,
  ...
}:
let
  hm = config.flake.modules.homeManager;
in
{
  # Every host imports base, so everything here is on every host.
  #
  # Features live in one default.nix each and add to two aggregate modules:
  #  - flake.modules.nixos.base: system side, gated on my.<feature>.enable (set by the
  #    host or a profile);
  #  - flake.modules.homeManager.base: user side, gated on the user's own
  #    my.<feature>.enable (home-manager.users.<name>.my...) and, when the feature has a
  #    system side, on the host enabling it too.
  # Each feature declares the state it needs to survive the root wipe next to its config:
  # environment.persistence."/persist" for system paths, home.persistence."/persist" for
  # paths under $HOME.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      options.my.users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Normal users this flake manages on the host.";
      };

      options.my.githubUsers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          dan = "dangreco";
        };
        description = "GitHub login of each managed user, keyed by local username.";
      };

      config = {
        home-manager = {
          useGlobalPkgs = true;
          # Packages go to /etc/profiles/per-user, so nothing under ~/.local/state/nix
          # has to survive a reboot.
          useUserPackages = true;
          backupFileExtension = "hm-bak";
          extraSpecialArgs = { inherit inputs self; };
          sharedModules = [ hm.base ];
        };

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          use-xdg-base-directories = true;
        };
        nixpkgs.config.allowUnfree = true;

        networking.networkmanager.enable = true;

        time.timeZone = "America/Toronto";
        i18n.defaultLocale = "en_CA.UTF-8";
        console.keyMap = "us";

        users.mutableUsers = false;
        zramSwap.enable = true;

        environment.systemPackages = [ pkgs.git ];

        system.stateVersion = "26.05";
      };
    };

  flake.modules.homeManager.base = {
    home.stateVersion = "26.05";
    nix.assumeXdg = true;
  };
}
