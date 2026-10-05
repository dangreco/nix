_: {
  flake.modules.homeManager.zed =
    { config, lib, ... }:
    {
      options.my.zed.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          auto_update = true;
        };
        description = ''
          Zed user settings, written verbatim to ~/.config/zed/settings.json as JSON.
          Keys and defaults follow Zed's settings reference:
          https://zed.dev/docs/configuring-zed
        '';
      };

      config = {
        xdg.configFile."zed/settings.json".text = builtins.toJSON config.my.zed.settings;

        # The upstream installer links the CLI to ~/.local/bin/zed.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
      };
    };
}
