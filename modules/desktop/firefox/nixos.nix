_: {
  # Native (nixpkgs) Firefox with hardware video decoding through VA-API.
  #
  # The driver side comes from the host: sake gets iHD (intel-media-driver) from the
  # nixos-hardware profile, mezcal gets radeonsi VA-API from Mesa via hardware.graphics.
  # Firefox itself has no hardware *encoder* on Linux (WebRTC VA-API encode is still an
  # open Mozilla bug, 1658900), so encode only works in other apps (ffmpeg, OBS, ...).
  flake.modules.nixos.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
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

      # The profile is under ~/.mozilla; the rest of /home is wiped at boot.
      environment.persistence."/persist".users = lib.genAttrs config.my.users (_: {
        directories = [ ".mozilla" ];
      });
    };
}
