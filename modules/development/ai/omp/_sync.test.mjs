import { afterEach, expect, test } from "bun:test";
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync,
  symlinkSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = join(import.meta.dir, "_sync.mjs");
const roots = [];
afterEach(() => { while (roots.length) rmSync(roots.pop(), { recursive: true, force: true }); });

// A scratch world: agent dir plus a "managed" source dir standing in for the
// store / sops-rendered files. Every run goes through the real CLI.
function world() {
  const root = mkdtempSync(join(tmpdir(), "omp-sync-"));
  roots.push(root);
  const agent = join(root, "agent");
  const src = join(root, "src");
  mkdirSync(agent);
  mkdirSync(src);
  const w = {
    root, agent, src,
    path: name => join(agent, name),
    managed(name, value) { writeFileSync(join(src, name), JSON.stringify(value)); return join(src, name); },
    put(name, text) { writeFileSync(join(agent, name), text); },
    text: name => readFileSync(join(agent, name), "utf8"),
    yaml: name => Bun.YAML.parse(readFileSync(join(agent, name), "utf8")),
    mode: name => statSync(join(agent, name)).mode & 0o777,
    run({ config = "config.json", models, mcp } = {}) {
      const args = ["--agent-dir", agent, "--config", join(src, config)];
      if (models) args.push("--models", join(src, models));
      if (mcp) args.push("--mcp", join(src, mcp));
      const result = Bun.spawnSync([process.execPath, script, ...args], { env: { ...process.env, HOME: root } });
      return { code: result.exitCode, stderr: result.stderr.toString(), stdout: result.stdout.toString() };
    },
    snapshot() {
      return Object.fromEntries(readdirSync(agent).map(name => [name, readFileSync(join(agent, name), "utf8")]));
    },
  };
  return w;
}

const model = (id, extra = {}) => ({ id, name: id, input: ["text"], contextWindow: 100000, ...extra });

test("providers deep merge, models merge by id, local fields win, local files untouched", () => {
  const w = world();
  w.managed("config.json", {});
  w.managed("models.json", { providers: { llm: { baseUrl: "https://m", api: "x", models: [model("a", { contextWindow: 1 }), model("b")] } } });
  const local = "providers:\n  llm:\n    api: local-api\n    models:\n      - {id: a, name: Local}\n      - {id: c}\n  mine:\n    baseUrl: https://mine\n";
  w.put("models.local.yml", local);
  const result = w.run({ models: "models.json" });
  expect(result.code).toBe(0);
  const out = w.yaml("models.yml");
  expect(out.providers.llm.baseUrl).toBe("https://m");
  expect(out.providers.llm.api).toBe("local-api");
  expect(out.providers.llm.models.map(m => m.id)).toEqual(["a", "b", "c"]);
  expect(out.providers.llm.models[0]).toMatchObject({ name: "Local", contextWindow: 1 });
  expect(out.providers.mine.baseUrl).toBe("https://mine");
  expect(w.text("models.local.yml")).toBe(local);
  expect(w.mode("models.yml")).toBe(0o600);
});

test("models are rebuilt from managed + local: managed retirement does not strand models", () => {
  const w = world();
  w.managed("config.json", {});
  w.put("models.local.yml", "providers:\n  llm:\n    models:\n      - {id: c}\n");
  w.managed("models.json", { providers: { llm: { models: [model("a"), model("b")] } } });
  expect(w.run({ models: "models.json" }).code).toBe(0);
  w.managed("models.json", { providers: { llm: { models: [model("a")] } } });
  expect(w.run({ models: "models.json" }).code).toBe(0);
  expect(w.yaml("models.yml").providers.llm.models.map(m => m.id)).toEqual(["a", "c"]);
});

test("local models alone generate models.yml; no sources at all leaves it alone", () => {
  const w = world();
  w.managed("config.json", {});
  w.put("models.yml", "keep: me\n");
  expect(w.run().code).toBe(0);
  expect(w.text("models.yml")).toBe("keep: me\n");
  w.put("models.local.yml", "providers:\n  mine:\n    models:\n      - {id: x}\n");
  expect(w.run().code).toBe(0);
  expect(w.yaml("models.yml").providers.mine.models[0].id).toBe("x");
});

test("removing the last local catalog clears its adopted models and generated chains", () => {
  const w = world();
  w.managed("config.json", {});
  w.put("models.local.yml", "providers:\n  mine:\n    models:\n      - {id: retired}\n");
  expect(w.run().code).toBe(0);
  rmSync(w.path("models.local.yml"));
  expect(w.run().code).toBe(0);
  expect(w.yaml("models.yml")).toEqual({});
  expect(w.yaml("config.yml").retry.fallbackChains).toEqual({});
});

test("config: unmanaged keys survive, managed applied, local wins", () => {
  const w = world();
  w.managed("config.json", { theme: { dark: "nord", light: "x" }, a: 1 });
  w.put("config.yml", "runtime: kept\ntheme:\n  dark: user\n");
  w.put("config.local.yml", "theme:\n  light: mine\nb: 2\n");
  expect(w.run().code).toBe(0);
  expect(w.yaml("config.yml")).toMatchObject({ runtime: "kept", theme: { dark: "nord", light: "mine" }, a: 1, b: 2 });
  expect(w.mode("config.yml")).toBe(0o600);
});

test("plugins and chains: live and local persist; managed upgrade and removals drop owned ones", () => {
  const w = world();
  w.managed("config.json", { extensions: ["/p/super1"], retry: { fallbackChains: { "a/x": ["a/y"] } } });
  w.put("config.local.yml", "extensions: [/p/mine]\nretry:\n  fallbackChains:\n    a/z: [a/w]\n");
  expect(w.run().code).toBe(0);
  let cfg = w.yaml("config.yml");
  expect(cfg.extensions).toEqual(["/p/super1", "/p/mine"]);

  // The user adds a plugin and a chain at runtime.
  cfg.extensions.push("/p/live");
  cfg.retry.fallbackChains["live/k"] = ["live/j"];
  w.put("config.yml", Bun.YAML.stringify(cfg));
  expect(w.run().code).toBe(0);
  cfg = w.yaml("config.yml");
  expect(cfg.extensions).toEqual(["/p/super1", "/p/mine", "/p/live"]);

  // Managed upgrade: old managed path and chain go, everything else stays.
  w.managed("config.json", { extensions: ["/p/super2"], retry: { fallbackChains: { "a/x2": ["a/y"] } } });
  expect(w.run().code).toBe(0);
  cfg = w.yaml("config.yml");
  expect(cfg.extensions).toEqual(["/p/super2", "/p/mine", "/p/live"]);
  expect(Object.keys(cfg.retry.fallbackChains).sort()).toEqual(["a/x2", "a/z", "live/k"]);

  // Repeat activation is stable.
  const before = w.text("config.yml");
  expect(w.run().code).toBe(0);
  expect(w.text("config.yml")).toBe(before);

  // Local removal retires local-owned entries, live ones remain.
  rmSync(w.path("config.local.yml"));
  expect(w.run().code).toBe(0);
  cfg = w.yaml("config.yml");
  expect(cfg.extensions).toEqual(["/p/super2", "/p/live"]);
  expect(Object.keys(cfg.retry.fallbackChains).sort()).toEqual(["a/x2", "live/k"]);
  expect(w.text("config.yml")).not.toContain("/p/mine");
  expect(w.text(".omp-sync-state.json")).not.toContain("live/k");
});

test("generated fallback chains cross accounts and local explicit chains override per selector", () => {
  const w = world();
  w.managed("config.json", {});
  w.managed("models.json", {
    providers: {
      p1: { models: [model("m1", { reasoning: false })] },
      p2: { models: [model("m2")] },
    },
  });
  expect(w.run({ models: "models.json" }).code).toBe(0);
  let chains = w.yaml("config.yml").retry.fallbackChains;
  expect(chains["p1/m1"][0].startsWith("p2/m2")).toBe(true);
  expect(chains["p2/m2"][0].startsWith("p1/m1")).toBe(true);

  w.put("config.local.yml", "retry:\n  fallbackChains:\n    p1/m1: [p2/m2:low]\n");
  expect(w.run({ models: "models.json" }).code).toBe(0);
  chains = w.yaml("config.yml").retry.fallbackChains;
  expect(chains["p1/m1"]).toEqual(["p2/m2:low"]);
  expect(chains["p2/m2"][0].startsWith("p1/m1")).toBe(true);

  // Models retired from the catalog lose their generated chains; runtime chains stay.
  const cfg = w.yaml("config.yml");
  cfg.retry.fallbackChains["runtime/r"] = ["runtime/s"];
  w.put("config.yml", Bun.YAML.stringify(cfg));
  w.managed("models.json", { providers: { p1: { models: [model("m1")] } } });
  expect(w.run({ models: "models.json" }).code).toBe(0);
  chains = w.yaml("config.yml").retry.fallbackChains;
  expect(chains["p2/m2"]).toBeUndefined();
  expect(chains["runtime/r"]).toEqual(["runtime/s"]);
});

test("first run without ownership state keeps plugins except an obsolete managed router copy", () => {
  const w = world();
  const router = "/nix/store/new-source/modules/x/_router/index.ts";
  w.managed("config.json", { extensions: ["/nix/store/new-source", router] });
  w.put("config.yml", Bun.YAML.stringify({
    extensions: ["/nix/store/old-source", "/nix/store/old-source/modules/x/_router/index.ts",
      "/nix/store/old-_router/index.ts", "/p/live"],
    retry: { fallbackChains: { "old/k": ["old/j"] } },
  }));
  expect(w.run().code).toBe(0);
  const cfg = w.yaml("config.yml");
  expect(cfg.extensions).toEqual(["/nix/store/new-source", router, "/nix/store/old-source", "/p/live"]);
  expect(cfg.retry.fallbackChains["old/k"]).toEqual(["old/j"]);
});

test("malformed or invalid local input fails nonzero with a filename-only error and writes nothing", () => {
  const cases = [
    ["models.local.yml", "providers: [unclosed SECRET-LOCAL\n  - : :\n"],
    ["models.local.yml", "just a string SECRET-LOCAL\n"],
    ["models.local.yml", "providers:\n  p:\n    models:\n      - {id: a}\n      - {id: a}\n"],
    ["models.local.yml", "providers:\n  p:\n    models:\n      - {name: SECRET-LOCAL}\n"],
    ["config.local.yml", "extensions: SECRET-LOCAL\n"],
    ["config.local.yml", "retry:\n  fallbackChains:\n    a/b: SECRET-LOCAL\n"],
    ["routing.local.yml", "models:\n  p/x: {tier: nonsense}\n"],
    ["routing.local.yml", "- SECRET-LOCAL\n"],
  ];
  for (const [file, body] of cases) {
    const w = world();
    w.managed("config.json", { extensions: ["/p/a"] });
    w.managed("models.json", { providers: { llm: { apiKey: "sk-SECRET-KEY", models: [model("a")] } } });
    w.managed("mcp.json", { nixos: { type: "stdio" } });
    w.put("config.yml", "runtime: 1\n");
    w.put("models.yml", "old: 1\n");
    w.put("mcp.json", '{"mcpServers":{"mine":{}}}');
    w.put(file, body);
    const before = w.snapshot();
    const result = w.run({ models: "models.json", mcp: "mcp.json" });
    expect(result.code).not.toBe(0);
    expect(result.stderr).toContain(file);
    expect(result.stderr).not.toContain("SECRET");
    expect(w.snapshot()).toEqual(before);
  }
});

test("missing managed sops files defer config/models, keep old files, still update mcp", () => {
  const w = world();
  w.put("config.yml", "runtime: old\n");
  w.put("models.yml", "old: 1\n");
  w.managed("mcp.json", { nixos: { type: "stdio", command: "n" } });
  const result = w.run({ config: "absent-config", models: "absent-models", mcp: "mcp.json" });
  expect(result.code).toBe(0);
  expect(result.stderr).toContain("deferred");
  expect(w.text("config.yml")).toBe("runtime: old\n");
  expect(w.text("models.yml")).toBe("old: 1\n");
  expect(existsSync(w.path(".omp-sync-state.json"))).toBe(false);
  expect(JSON.parse(w.text("mcp.json")).mcpServers.nixos.command).toBe("n");
});

test("mcp: declared servers replace by name, others and top-level keys stay", () => {
  const w = world();
  w.managed("config.json", {});
  w.managed("mcp.json", { nixos: { type: "stdio", command: "new" } });
  w.put("mcp.json", JSON.stringify({ other: 1, mcpServers: { nixos: { command: "old", extra: 1 }, mine: { url: "u" } } }));
  expect(w.run({ mcp: "mcp.json" }).code).toBe(0);
  const out = JSON.parse(w.text("mcp.json"));
  expect(out.mcpServers.nixos).toEqual({ type: "stdio", command: "new" });
  expect(out.mcpServers.mine).toEqual({ url: "u" });
  expect(out.other).toBe(1);
  expect(out.$schema).toContain("mcp-schema.json");
  expect(w.mode("mcp.json")).toBe(0o600);
});

test("native symlinks are replaced, never written through; modes 0600; directories only created 0700", () => {
  const w = world();
  w.managed("config.json", { a: 1 });
  w.managed("mcp.json", { s: { type: "stdio" } });
  const store = join(w.root, "store");
  mkdirSync(store);
  writeFileSync(join(store, "config.yml"), "runtime: kept\n");
  writeFileSync(join(store, "mcp.json"), '{"mcpServers":{"mine":{}}}');
  chmodSync(join(store, "config.yml"), 0o444);
  symlinkSync(join(store, "config.yml"), w.path("config.yml"));
  symlinkSync(join(store, "mcp.json"), w.path("mcp.json"));
  chmodSync(w.agent, 0o755);
  expect(w.run({ mcp: "mcp.json" }).code).toBe(0);
  expect(readFileSync(join(store, "config.yml"), "utf8")).toBe("runtime: kept\n");
  expect(readFileSync(join(store, "mcp.json"), "utf8")).toBe('{"mcpServers":{"mine":{}}}');
  expect(Bun.file(w.path("config.yml")).size).toBeGreaterThan(0);
  for (const name of ["config.yml", "mcp.json"]) {
    expect(require("node:fs").lstatSync(w.path(name)).isSymbolicLink()).toBe(false);
    expect(w.mode(name)).toBe(0o600);
  }
  expect(w.yaml("config.yml")).toMatchObject({ runtime: "kept", a: 1 });
  expect(JSON.parse(w.text("mcp.json")).mcpServers.mine).toEqual({});
  expect(statSync(w.agent).mode & 0o777).toBe(0o755);
  expect(readdirSync(w.agent).filter(name => name.endsWith(".tmp"))).toEqual([]);

  const fresh = join(w.root, "new", "agent");
  const result = Bun.spawnSync([process.execPath, script, "--agent-dir", fresh, "--config", join(w.src, "config.json")]);
  expect(result.exitCode).toBe(0);
  expect(statSync(fresh).mode & 0o777).toBe(0o700);
});
