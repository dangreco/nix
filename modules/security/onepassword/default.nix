_: {
  # 1Password: the app and CLI on the host (my.onepassword.enable); each user who opts
  # in (home-manager.users.<name>.my.onepassword.enable) uses its SSH agent.
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      options.my.onepassword.enable = lib.mkEnableOption "the 1Password app and CLI";

      config = lib.mkIf config.my.onepassword.enable {
        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = config.my.users;
        };

        # Vault cache and app settings, for everyone who can launch the app.
        home-manager.sharedModules = [
          { home.persistence."/persist".directories = [ ".config/1Password" ]; }
        ];
      };
    };

  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      cfg = config.my.onepassword;
      items = cfg.sshAgentItems;
    in
    {
      options.my.onepassword.enable = lib.mkEnableOption "the 1Password SSH agent";

      options.my.onepassword.sshAgentItems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Items in the nix-hosts vault the 1Password SSH agent exposes, next to the
          Private vault. Normally this host's own key item, so the key the installer
          registered on GitHub is the one offered.
        '';
      };

      config = lib.mkIf (cfg.enable && osConfig.my.onepassword.enable) {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings."*".IdentityAgent = "~/.1password/agent.sock";
        };

        programs.fish.interactiveShellInit = ''
          set SSH_AUTH_SOCK ~/.1password/agent.sock
        '';

        # Setting this file replaces the agent's default key list, so keep Private.
        xdg.configFile."1Password/ssh/agent.toml" = lib.mkIf (items != [ ]) {
          force = true;
          text = ''
            [[ssh-keys]]
            vault = "Private"
          ''
          + lib.concatMapStrings (item: ''

            [[ssh-keys]]
            vault = "nix-hosts"
            item = "${item}"
          '') items;
        };
      };
    };
}
