_: {
  # CUPS with driverless printing: IPP Everywhere / AirPrint printers on the LAN show
  # up in GNOME's print dialog and Settings → Printers without per-model drivers.
  # Add vendor drivers with services.printing.drivers on the host if a printer
  # needs one.
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      options.my.printing.enable = lib.mkEnableOption "CUPS with network printer discovery";

      config = lib.mkIf config.my.printing.enable {
        services.printing = {
          enable = true;
          # CUPS finds DNS-SD printers itself (temporary queues). cups-browsed, which
          # NixOS turns on with Avahi, only adds the legacy CUPS browsing protocol on
          # UDP 631, the vector of CVE-2024-47176.
          browsed.enable = false;
        };

        # mDNS discovery, and resolving the printers' <name>.local addresses
        # (avahi opens UDP 5353 in the firewall by default).
        services.avahi = {
          enable = true;
          nssmdns4 = true;
        };

        # Queues added in Settings → Printers, plus their PPDs; /etc/cups links here.
        environment.persistence."/persist".directories = [ "/var/lib/cups" ];
      };
    };
}
