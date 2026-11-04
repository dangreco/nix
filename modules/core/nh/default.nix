_: {
  # nh on every host: `nh os ...`, `nh search`, `nh clean` for interactive use, plus a
  # weekly `nh clean all` that removes old system/user generations and stale GC roots
  # (result links, nix-direnv's .direnv profiles), then collects garbage and
  # deduplicates the store. The timer is Persistent; its stamp lives in
  # /var/lib/systemd, which survives the root wipe.
  flake.modules.nixos.base =
    { config, lib, ... }:
    let
      # Never drop a generation the boot menu still lists: lanzaboote keeps the
      # newest configurationLimit entries (10, see security/secure-boot).
      keep = lib.defaultTo 10 config.boot.loader.systemd-boot.configurationLimit;
    in
    {
      programs.nh = {
        enable = true;
        clean = {
          enable = true;
          dates = "weekly";
          # --keep-since spares anything touched in the last week even past the
          # count; --keep-one leaves each direnv project its newest profile so
          # entering a project does not rebuild its shell.
          extraArgs = "--keep ${toString keep} --keep-since 7d --keep-one --optimise";
        };
      };
    };
}
