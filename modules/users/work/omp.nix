{
  flake.modules.homeManager.work-omp = {
    # Work's omp settings.
    # hm.omp (modules/development/ai/omp/home.nix) serializes these verbatim to
    # ~/.omp/agent/config.yml.
    my.omp.settings = {
      # Work-specific overrides could go here.
    };
  };
}
