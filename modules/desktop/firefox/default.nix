_: {
  # Native (nixpkgs) Firefox with hardware video decoding through VA-API.
  #
  # The driver side comes from the host: sake gets iHD (intel-media-driver) from the
  # nixos-hardware profile, mezcal gets radeonsi VA-API from Mesa via hardware.graphics.
  # Firefox itself has no hardware *encoder* on Linux (WebRTC VA-API encode is still an
  # open Mozilla bug, 1658900), so encode only works in other apps (ffmpeg, OBS, ...).
  flake.modules.nixos.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.firefox.enable = lib.mkEnableOption "Firefox with VA-API decoding";

      config = lib.mkIf config.my.firefox.enable {
        programs.firefox = {
          enable = true;

          # "default" keeps these changeable in about:config while debugging.
          preferencesStatus = "default";
          preferences = {
            # On by default for Intel (115+) and AMD (136+), but the blocklist can still
            # turn it off; force-enabled overrides that (replaces media.ffmpeg.vaapi.enabled).
            "media.hardware-video-decoding.enabled" = true;
            "media.hardware-video-decoding.force-enabled" = true;
            # WebRTC H.264 through the hardware decoder; default only from Firefox 154.
            "media.webrtc.hw.h264.enabled" = true;
          };
        };

        # vainfo, to check which codecs the GPU exposes.
        environment.systemPackages = [ pkgs.libva-utils ];

        # Fresh installs of Firefox 147+ keep the profile in ~/.config/mozilla, existing ones in
        # ~/.mozilla. Which one wins can depend on whether ~/.mozilla exists, and the bind
        # mount below creates it, so persist both. The rest of /home is wiped at boot.
        home-manager.sharedModules = [
          {
            home.persistence."/persist".directories = [
              ".mozilla"
              ".config/mozilla"
            ];
          }
        ];
      };
    };
}
