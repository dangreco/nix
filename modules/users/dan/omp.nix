{
  flake.modules.homeManager.dan-omp = {
    # Dan's omp settings.
    # hm.omp (modules/development/ai/omp/home.nix) serializes these verbatim to
    # ~/.omp/agent/config.yml.
    my.omp.settings = {
      # Add default settings here if needed, or leave empty to test.
      # e.g., defaultModel = "claude-3-5-sonnet-20241022";
    };
  };
}
