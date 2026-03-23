import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const repoRoot = path.resolve(process.cwd(), "zenmind");

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, "utf8");
}

test("package-agents bundles all example configs unconditionally and preserves provider example secrets", () => {
  const root = makeTempDir("zenmind-package-agents-");
  const zenmindRepo = path.join(root, "zenmind");
  const runtimeRoot = path.join(root, ".zenmind");
  const scriptSource = path.join(repoRoot, "scripts", "deploy", "package-agents.sh");
  const scriptTarget = path.join(zenmindRepo, "scripts", "deploy", "package-agents.sh");

  writeFile(path.join(zenmindRepo, "VERSION"), "v0.0.1\n");
  fs.mkdirSync(path.dirname(scriptTarget), { recursive: true });
  fs.copyFileSync(scriptSource, scriptTarget);

  writeFile(path.join(runtimeRoot, "agents", "testAgent", "agent.yml"), [
    "name: Test Agent",
    "modelKey: demo-model",
    ""
  ].join("\n"));
  fs.mkdirSync(path.join(runtimeRoot, "skills-market"), { recursive: true });
  fs.mkdirSync(path.join(runtimeRoot, "teams"), { recursive: true });
  fs.mkdirSync(path.join(runtimeRoot, "schedules"), { recursive: true });
  fs.mkdirSync(path.join(runtimeRoot, "tools"), { recursive: true });

  writeFile(path.join(runtimeRoot, "configs", "models", "demo-model.example.yml"), [
    "key: demo-model",
    "provider: demo-provider",
    "protocol: OPENAI",
    "modelId: demo-model-id",
    ""
  ].join("\n"));
  writeFile(path.join(runtimeRoot, "configs", "models", "demo-model.yml"), "key: should-not-package\n");

  writeFile(path.join(runtimeRoot, "configs", "providers", "demo-provider.example.yml"), [
    "key: demo-provider",
    "baseUrl: https://provider.example.test",
    "apiKey: secret-from-example",
    "defaultModel: demo-model-id",
    ""
  ].join("\n"));
  writeFile(path.join(runtimeRoot, "configs", "providers", "demo-provider.yml"), "apiKey: should-not-package\n");
  writeFile(path.join(runtimeRoot, "configs", "providers", "extra-provider.example.yml"), [
    "key: extra-provider",
    "baseUrl: https://extra-provider.example.test",
    "apiKey: extra-secret-from-example",
    "defaultModel: extra-model-id",
    ""
  ].join("\n"));

  writeFile(path.join(runtimeRoot, "configs", "models", "extra-model.example.yml"), [
    "key: extra-model",
    "provider: extra-provider",
    "protocol: OPENAI",
    "modelId: extra-model-id",
    ""
  ].join("\n"));

  writeFile(path.join(runtimeRoot, "configs", "mcp-servers", "mock.example.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    "enabled: true",
    ""
  ].join("\n"));
  writeFile(path.join(runtimeRoot, "configs", "mcp-servers", "mock.yml"), "baseUrl: http://127.0.0.1:1\n");
  writeFile(path.join(runtimeRoot, "configs", "mcp-servers", "imagine.example.yml"), [
    "serverKey: imagine",
    "baseUrl: http://127.0.0.1:11962",
    "endpointPath: \"/mcp\"",
    "enabled: true",
    ""
  ].join("\n"));

  writeFile(path.join(runtimeRoot, "configs", "viewport-servers", "mock.example.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(runtimeRoot, "configs", "viewport-servers", "mock.yml"), "baseUrl: http://127.0.0.1:2\n");

  execFileSync("bash", [scriptTarget, "--agents", "testAgent"], {
    cwd: zenmindRepo,
    env: { ...process.env, VERSION: "v0.0.1" },
    stdio: "pipe"
  });

  const archivePath = path.join(runtimeRoot, "dist", "v0.0.1", "zenmind-agents-v0.0.1.tar.gz");
  const extractedRoot = path.join(root, "extracted");
  fs.mkdirSync(extractedRoot, { recursive: true });
  execFileSync("tar", ["-xzf", archivePath, "-C", extractedRoot]);

  const packageRoot = path.join(extractedRoot, "zenmind-agents");
  const packagedModel = path.join(packageRoot, "configs", "models", "demo-model.example.yml");
  const packagedExtraModel = path.join(packageRoot, "configs", "models", "extra-model.example.yml");
  const packagedProvider = path.join(packageRoot, "configs", "providers", "demo-provider.example.yml");
  const packagedExtraProvider = path.join(packageRoot, "configs", "providers", "extra-provider.example.yml");
  const packagedMcp = path.join(packageRoot, "configs", "mcp-servers", "mock.example.yml");
  const packagedImagineMcp = path.join(packageRoot, "configs", "mcp-servers", "imagine.example.yml");
  const packagedViewport = path.join(packageRoot, "configs", "viewport-servers", "mock.example.yml");

  assert.equal(fs.existsSync(packagedModel), true);
  assert.equal(fs.existsSync(packagedExtraModel), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "configs", "models", "demo-model.yml")), false);
  assert.equal(fs.existsSync(packagedProvider), true);
  assert.equal(fs.existsSync(packagedExtraProvider), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "configs", "providers", "demo-provider.yml")), false);
  assert.equal(fs.existsSync(packagedMcp), true);
  assert.equal(fs.existsSync(packagedImagineMcp), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "configs", "mcp-servers", "mock.yml")), false);
  assert.equal(fs.existsSync(packagedViewport), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "configs", "viewport-servers", "mock.yml")), false);

  const providerBody = fs.readFileSync(packagedProvider, "utf8");
  assert.match(providerBody, /apiKey: secret-from-example/);
});

test("release materialization turns example configs into live files and rewrites MCP URLs", () => {
  const root = makeTempDir("zenmind-release-configs-");
  const configRoot = path.join(root, "configs");
  const scriptPath = path.join(repoRoot, "scripts", "shared", "zenmind-setup-actions.sh");

  writeFile(path.join(configRoot, "models", "demo-model.example.yml"), "key: demo-model\nprovider: demo-provider\n");
  writeFile(path.join(configRoot, "providers", "demo-provider.example.yml"), [
    "key: demo-provider",
    "apiKey: secret-from-example",
    ""
  ].join("\n"));
  writeFile(path.join(configRoot, "mcp-servers", "imagine.example.yml"), [
    "serverKey: imagine",
    "baseUrl: http://127.0.0.1:11962",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(configRoot, "mcp-servers", "mock.example.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(configRoot, "viewport-servers", "mock.example.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));

  writeFile(path.join(configRoot, "mcp-servers", "stale.yml"), "baseUrl: http://stale\n");

  execFileSync("bash", ["-lc", [
    "set -euo pipefail",
    "source \"$SCRIPT_PATH\"",
    "zenmind_release_materialize_example_config_dir \"$MODELS_DIR\"",
    "zenmind_release_materialize_example_config_dir \"$PROVIDERS_DIR\"",
    "zenmind_release_materialize_example_config_dir \"$MCP_DIR\" true",
    "zenmind_release_materialize_example_config_dir \"$VIEWPORT_DIR\" true"
  ].join("; ")], {
    cwd: repoRoot,
    env: {
      ...process.env,
      SCRIPT_DIR: repoRoot,
      SCRIPT_PATH: scriptPath,
      MODELS_DIR: path.join(configRoot, "models"),
      PROVIDERS_DIR: path.join(configRoot, "providers"),
      MCP_DIR: path.join(configRoot, "mcp-servers"),
      VIEWPORT_DIR: path.join(configRoot, "viewport-servers")
    },
    stdio: "pipe"
  });

  assert.equal(fs.existsSync(path.join(configRoot, "models", "demo-model.example.yml")), false);
  assert.equal(fs.existsSync(path.join(configRoot, "providers", "demo-provider.example.yml")), false);
  assert.equal(fs.existsSync(path.join(configRoot, "mcp-servers", "mock.example.yml")), false);
  assert.equal(fs.existsSync(path.join(configRoot, "viewport-servers", "mock.example.yml")), false);
  assert.equal(fs.existsSync(path.join(configRoot, "mcp-servers", "stale.yml")), false);

  assert.equal(fs.existsSync(path.join(configRoot, "models", "demo-model.yml")), true);
  assert.equal(fs.existsSync(path.join(configRoot, "providers", "demo-provider.yml")), true);
  assert.equal(fs.existsSync(path.join(configRoot, "mcp-servers", "imagine.yml")), true);
  assert.equal(fs.existsSync(path.join(configRoot, "mcp-servers", "mock.yml")), true);
  assert.equal(fs.existsSync(path.join(configRoot, "viewport-servers", "mock.yml")), true);

  const providerBody = fs.readFileSync(path.join(configRoot, "providers", "demo-provider.yml"), "utf8");
  assert.match(providerBody, /apiKey: secret-from-example/);

  const imagineBody = fs.readFileSync(path.join(configRoot, "mcp-servers", "imagine.yml"), "utf8");
  const mockBody = fs.readFileSync(path.join(configRoot, "mcp-servers", "mock.yml"), "utf8");
  const viewportMockBody = fs.readFileSync(path.join(configRoot, "viewport-servers", "mock.yml"), "utf8");

  assert.match(imagineBody, /baseUrl: http:\/\/mcp-server-imagine:8080/);
  assert.match(mockBody, /baseUrl: http:\/\/mcp-server-mock:8080/);
  assert.match(viewportMockBody, /baseUrl: http:\/\/mcp-server-mock:8080/);
  assert.match(mockBody, /endpointPath: "\/mcp"/);
});
