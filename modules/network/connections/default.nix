{ self, ... }:
{
  # Wi-Fi (and other) connection profiles for every user on the host.
  #
  # secrets/networks.yaml holds `networks:`, a list of NetworkManager keyfiles
  # (.nmconnection text) serialised as strings, so neither SSIDs nor the kind of
  # network (hidden, enterprise, ...) show up outside the encrypted file or in the
  # nix store. Add a network by appending a keyfile string with
  # `sops secrets/networks.yaml`. The profiles go to /run, never to disk.
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.networkConnections.enable = lib.mkEnableOption "NetworkManager profiles from sops";

      config = lib.mkIf config.my.networkConnections.enable {
        # key = "" hands the unit the whole decrypted file.
        sops.secrets.network-connections = {
          sopsFile = self + "/secrets/networks.yaml";
          key = "";
          restartUnits = [ "network-connections.service" ];
        };

        systemd.services.network-connections = {
          description = "Install NetworkManager connection profiles from sops";
          wantedBy = [ "multi-user.target" ];
          before = [ "network-online.target" ];
          after = [ "NetworkManager.service" ];
          path = [
            pkgs.coreutils
            pkgs.jq
            pkgs.yq-go
            config.networking.networkmanager.package
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0177";
          };
          script = ''
            dir=/run/NetworkManager/system-connections
            mkdir -p "$dir"
            rm -f "$dir"/sops-*.nmconnection

            # Files are named by content hash so the file names reveal nothing either.
            yq -o=json '.networks' ${config.sops.secrets.network-connections.path} \
              | jq -r '.[] | @base64' \
              | while read -r entry; do
                  profile=$(printf '%s' "$entry" | base64 -d)
                  name=$(printf '%s' "$profile" | sha256sum | cut -c1-16)
                  printf '%s\n' "$profile" > "$dir/sops-$name.nmconnection"
                done

            nmcli connection reload
          '';
        };
      };
    };
}
