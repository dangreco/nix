# Android device development: adb/fastboot for managed users plus USB access to
# Samsung devices in Odin/Download mode. systemd's built-in uaccess rules cover
# ADB and Fastboot interfaces, but Download mode shows up as a plain vendor
# device (VID 04e8) nothing grants access to. samloader's `fix-usb` command
# tries to install that rule into /etc/udev/rules.d, which is read-only on
# NixOS, so the rule ships here instead.
{
  flake.modules.nixos.base =
    { config, lib, pkgs, ... }:
    {
      options.my.android.enable = lib.mkEnableOption "Android device development (adb/fastboot, Samsung Download mode USB access)";

      config = lib.mkIf config.my.android.enable {
        users.users = lib.genAttrs config.my.users (_: {
          packages = [ pkgs.android-tools ];
        });

        # Must sort before systemd's 73-seat-late.rules, where TAG=="uaccess"
        # triggers the uaccess builtin that ACLs the device node for the active
        # seat user (services.udev.extraRules would land in 99-local.rules,
        # after that point).
        services.udev.packages = [
          (pkgs.writeTextFile {
            name = "samloader-udev-rules";
            text = ''
              # Samsung Odin/Download mode (samloader, Heimdall)
              SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", TAG+="uaccess"
            '';
            destination = "/lib/udev/rules.d/60-samloader.rules";
          })
        ];
      };
    };
}
