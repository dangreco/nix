_: {
  # Fedora-style boot: firmware logo + spinner (bgrt) from the initrd onward,
  # LUKS passphrase asked through Plymouth's graphical prompt, no boot text.
  flake.modules.nixos.boot-splash = {
    boot.plymouth = {
      enable = true;
      theme = "bgrt";
    };

    # loglevel=3 plus quiet: only critical kernel messages; systemd status
    # output only on errors/delays (quiet implies systemd.show_status=auto).
    boot.consoleLogLevel = 3;
    boot.kernelParams = [
      "quiet"
      "udev.log_level=3"
    ];

    # Hide the systemd-boot menu; hold Space while booting to pick another generation.
    boot.loader.timeout = 0;
  };
}
