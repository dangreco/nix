_: {
  flake.modules.homeManager.omp =
    { config, lib, ... }:
    {
      options.my.omp.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          omp user settings, written verbatim to ~/.omp/agent/config.yml as YAML.
        '';
      };

      config = {
        home.file.".omp/agent/config.yml" = lib.mkIf (config.my.omp.settings != { }) {
          text = lib.generators.toYAML { } config.my.omp.settings;
        };

        # The upstream installer links the CLI to ~/.local/bin/omp.
        home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
      };
    };
}
