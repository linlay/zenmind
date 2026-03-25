import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function makeTempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, "utf8");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

test("package-zenmind-data bundles filtered zenmind data", () => {
  const root = makeTempDir("zenmind-package-data-");
  const zenmindRepo = path.join(root, "zenmind");
  const runtimeRoot = path.join(root, ".zenmind");
  const scriptSource = path.join(repoRoot, "scripts", "deploy", "package-zenmind-data.sh");
  const scriptTarget = path.join(zenmindRepo, "scripts", "deploy", "package-zenmind-data.sh");

  writeFile(path.join(zenmindRepo, "VERSION"), "v0.0.1\n");
  fs.mkdirSync(path.dirname(scriptTarget), { recursive: true });
  fs.copyFileSync(scriptSource, scriptTarget);

  writeFile(path.join(runtimeRoot, "agents", "normalAgent", "agent.yml"), "name: Normal Agent\n");
  writeFile(path.join(runtimeRoot, "agents", "showcase.example", "agent.yml"), "name: Example Agent\n");
  writeFile(path.join(runtimeRoot, "agents", "skip.demo", "agent.yml"), "name: Demo Agent\n");

  writeFile(path.join(runtimeRoot, "chats", "keep.example.jsonl"), "{\"role\":\"assistant\"}\n");
  writeFile(path.join(runtimeRoot, "chats", "skip.jsonl"), "{\"role\":\"assistant\"}\n");
  writeFile(path.join(runtimeRoot, "chats", "thread.example", "message.jsonl"), "{\"role\":\"assistant\"}\n");
  writeFile(path.join(runtimeRoot, "chats", "thread", "message.jsonl"), "{\"role\":\"assistant\"}\n");

  writeFile(path.join(runtimeRoot, "owner.example", "OWNER.md"), "name: packaged-owner\n");
  writeFile(path.join(runtimeRoot, "owner.example", "BOOTSTRAP.md"), "bootstrap: true\n");
  writeFile(path.join(runtimeRoot, "owner", "OWNER.md"), "name: stale-owner\n");

  writeFile(path.join(runtimeRoot, "registries.example", "models", "demo-model.yml"), "key: demo-model\n");
  writeFile(path.join(runtimeRoot, "registries.example", "providers", "demo-provider.yml"), "apiKey: secret-from-example\n");
  writeFile(path.join(runtimeRoot, "registries.example", "mcp-servers", "mock.yml"), "baseUrl: http://localhost:11969\n");
  writeFile(path.join(runtimeRoot, "registries.example", "viewport-servers", "mock.yml"), "baseUrl: http://localhost:11969\n");
  writeFile(path.join(runtimeRoot, "registries", "providers", "demo-provider.yml"), "apiKey: should-not-package\n");

  writeFile(path.join(runtimeRoot, "root", ".env.example"), "ROOT_EXAMPLE=1\n");
  writeFile(path.join(runtimeRoot, "root", ".config.example", "settings.json"), "{ \"ok\": true }\n");
  writeFile(path.join(runtimeRoot, "root", "skip.txt"), "skip\n");
  writeFile(path.join(runtimeRoot, "root", ".cache"), "skip\n");

  writeFile(path.join(runtimeRoot, "schedules", "daily.yml"), "cron: daily\n");
  writeFile(path.join(runtimeRoot, "schedules", "daily.example.yml"), "cron: example\n");
  writeFile(path.join(runtimeRoot, "schedules", "daily.demo.yml"), "cron: demo\n");
  writeFile(path.join(runtimeRoot, "schedules", "weekly.yaml"), "cron: weekly\n");

  writeFile(path.join(runtimeRoot, "skills-market", "sharedSkill", "SKILL.md"), "# Shared\n");
  writeFile(path.join(runtimeRoot, "skills-market", "sharedSkill.example", "SKILL.md"), "# Example\n");
  writeFile(path.join(runtimeRoot, "skills-market", "sharedSkill.demo", "SKILL.md"), "# Demo\n");

  writeFile(path.join(runtimeRoot, "teams", "main.yml"), "name: main\n");
  writeFile(path.join(runtimeRoot, "teams", "main.example.yml"), "name: main example\n");
  writeFile(path.join(runtimeRoot, "teams", "main.demo.yml"), "name: main demo\n");
  writeFile(path.join(runtimeRoot, "teams", "backup.yaml"), "name: backup\n");

  writeFile(path.join(runtimeRoot, "tools", "tool.yml"), "name: should-not-package\n");

  execFileSync("bash", [scriptTarget], {
    cwd: zenmindRepo,
    env: { ...process.env, VERSION: "v0.0.1" },
    stdio: "pipe"
  });

  const archivePath = path.join(runtimeRoot, "dist", "v0.0.1", "zenmind-data-v0.0.1.tar.gz");
  const extractedRoot = path.join(root, "extracted");
  fs.mkdirSync(extractedRoot, { recursive: true });
  execFileSync("tar", ["-xzf", archivePath, "-C", extractedRoot]);

  const packageRoot = path.join(extractedRoot, "zenmind-data");

  assert.equal(fs.existsSync(path.join(packageRoot, "agents", "normalAgent", "agent.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "agents", "showcase.example", "agent.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "agents", "skip.demo", "agent.yml")), false);

  assert.equal(fs.existsSync(path.join(packageRoot, "chats", "keep.example.jsonl")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "chats", "skip.jsonl")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "chats", "thread.example", "message.jsonl")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "chats", "thread", "message.jsonl")), false);

  assert.equal(fs.existsSync(path.join(packageRoot, "owner", "OWNER.md")), true);
  assert.equal(fs.readFileSync(path.join(packageRoot, "owner", "OWNER.md"), "utf8"), "name: packaged-owner\n");

  assert.equal(fs.existsSync(path.join(packageRoot, "registries", "models", "demo-model.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "registries", "providers", "demo-provider.yml")), true);
  assert.match(fs.readFileSync(path.join(packageRoot, "registries", "providers", "demo-provider.yml"), "utf8"), /secret-from-example/);
  assert.doesNotMatch(fs.readFileSync(path.join(packageRoot, "registries", "providers", "demo-provider.yml"), "utf8"), /should-not-package/);

  assert.equal(fs.existsSync(path.join(packageRoot, "root", ".env.example")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "root", ".config.example", "settings.json")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "root", "skip.txt")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "root", ".cache")), false);

  assert.equal(fs.existsSync(path.join(packageRoot, "schedules", "daily.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "schedules", "daily.example.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "schedules", "daily.demo.yml")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "schedules", "weekly.yaml")), true);

  assert.equal(fs.existsSync(path.join(packageRoot, "skills-market", "sharedSkill", "SKILL.md")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "skills-market", "sharedSkill.example", "SKILL.md")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "skills-market", "sharedSkill.demo", "SKILL.md")), false);

  assert.equal(fs.existsSync(path.join(packageRoot, "teams", "main.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "teams", "main.example.yml")), true);
  assert.equal(fs.existsSync(path.join(packageRoot, "teams", "main.demo.yml")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "teams", "backup.yaml")), true);

  assert.equal(fs.existsSync(path.join(packageRoot, "tools")), false);
});

test("release bundle deployment writes registries and zenmind data directories", () => {
  const root = makeTempDir("zenmind-release-data-");
  const scriptPath = path.join(repoRoot, "scripts", "shared", "zenmind-setup-actions.sh");
  const bundleRoot = path.join(root, "bundle", "zenmind-data");
  const bundlePath = path.join(root, "zenmind-data-v0.0.1.tar.gz");
  const versionRoot = path.join(root, "release", "v0.0.1");
  const deployRoot = path.join(versionRoot, "deploy");
  const runnerDir = path.join(deployRoot, "agent-platform-runner");
  const deployZenmindDir = path.join(deployRoot, ".zenmind");

  writeFile(path.join(bundleRoot, "agents", "testAgent", "agent.yml"), "name: Test Agent\nmodelKey: demo-model\n");
  writeFile(path.join(bundleRoot, "chats", "keep.example.jsonl"), "{\"role\":\"assistant\"}\n");
  writeFile(path.join(bundleRoot, "owner", "OWNER.md"), "name: deployed-owner\n");
  writeFile(path.join(bundleRoot, "owner", "BOOTSTRAP.md"), "bootstrap: true\n");
  writeFile(path.join(bundleRoot, "registries", "models", "demo-model.yml"), "key: demo-model\nprovider: demo-provider\n");
  writeFile(path.join(bundleRoot, "registries", "providers", "demo-provider.yml"), [
    "key: demo-provider",
    "apiKey: secret-from-example",
    ""
  ].join("\n"));
  writeFile(path.join(bundleRoot, "registries", "mcp-servers", "imagine.yml"), [
    "serverKey: imagine",
    "baseUrl: http://127.0.0.1:11962",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(bundleRoot, "registries", "mcp-servers", "mock.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(bundleRoot, "registries", "mcp-servers", "bash.yml"), "serverKey: bash\nenabled: true\n");
  writeFile(path.join(bundleRoot, "registries", "mcp-servers", "database.yml"), "serverKey: database\nenabled: true\n");
  writeFile(path.join(bundleRoot, "registries", "mcp-servers", "email.yml"), "serverKey: email\nenabled: true\n");
  writeFile(path.join(bundleRoot, "registries", "viewport-servers", "mock.yml"), [
    "serverKey: mock",
    "baseUrl: http://localhost:11969",
    "endpointPath: \"/mcp\"",
    ""
  ].join("\n"));
  writeFile(path.join(bundleRoot, "root", ".env.example"), "ROOT_EXAMPLE=1\n");
  writeFile(path.join(bundleRoot, "schedules", "daily.yml"), "cron: daily\n");
  writeFile(path.join(bundleRoot, "skills-market", "sharedSkill", "SKILL.md"), "# Shared\n");
  writeFile(path.join(bundleRoot, "teams", "main.yml"), "name: main\n");
  execFileSync("tar", ["-czf", bundlePath, "-C", path.join(root, "bundle"), "zenmind-data"]);

  writeFile(path.join(runnerDir, ".env"), [
    "AGENTS_DIR=./runtime/agents",
    `MODELS_DIR=${path.join(deployZenmindDir, "configs", "models")}`,
    `PROVIDERS_DIR=${path.join(deployZenmindDir, "configs", "providers")}`,
    `MCP_SERVERS_DIR=${path.join(deployZenmindDir, "configs", "mcp-servers")}`,
    `VIEWPORT_SERVERS_DIR=${path.join(deployZenmindDir, "configs", "viewport-servers")}`,
    ""
  ].join("\n"));
  writeFile(path.join(runnerDir, "configs", "container-hub.example.yml"), "kind: example\n");
  writeFile(path.join(runnerDir, "configs", "bash.example.yml"), "kind: example\n");
  writeFile(path.join(runnerDir, "configs", "cors.example.yml"), "kind: example\n");

  execFileSync("bash", ["-lc", [
    "set -euo pipefail",
    "zenmind_repo_root_path() { printf '%s\\n' \"$REPO_ROOT\"; }",
    "zenmind_summary_add_fail() { printf '%s\\n' \"$*\" >&2; return 1; }",
    "source \"$SCRIPT_PATH\"",
    "zenmind_release_prepare_agents_bundle \"$VERSION_DIR\" \"$BUNDLE_PATH\"",
    "zenmind_release_prepare_runner_runtime \"$VERSION_DIR\""
  ].join("; ")], {
    cwd: repoRoot,
    env: {
      ...process.env,
      REPO_ROOT: root,
      SCRIPT_DIR: root,
      SCRIPT_PATH: scriptPath,
      VERSION_DIR: versionRoot,
      BUNDLE_PATH: bundlePath
    },
    stdio: "pipe"
  });

  assert.equal(fs.existsSync(path.join(deployZenmindDir, "configs")), false);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "owner", "OWNER.md")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "owner", "BOOTSTRAP.md")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "registries", "models", "demo-model.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "registries", "providers", "demo-provider.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "registries", "mcp-servers", "imagine.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "registries", "mcp-servers", "mock.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "registries", "viewport-servers", "mock.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "chats", "keep.example.jsonl")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "root", ".env.example")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "schedules", "daily.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "skills-market", "sharedSkill", "SKILL.md")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "teams", "main.yml")), true);
  assert.equal(fs.existsSync(path.join(deployZenmindDir, "tools")), false);

  const providerBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "providers", "demo-provider.yml"), "utf8");
  const ownerBody = fs.readFileSync(path.join(deployZenmindDir, "owner", "OWNER.md"), "utf8");
  assert.match(providerBody, /apiKey: secret-from-example/);
  assert.match(ownerBody, /name: deployed-owner/);

  const imagineBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "mcp-servers", "imagine.yml"), "utf8");
  const mockBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "mcp-servers", "mock.yml"), "utf8");
  const viewportMockBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "viewport-servers", "mock.yml"), "utf8");
  const disabledBashBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "mcp-servers", "bash.yml"), "utf8");
  const disabledDatabaseBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "mcp-servers", "database.yml"), "utf8");
  const disabledEmailBody = fs.readFileSync(path.join(deployZenmindDir, "registries", "mcp-servers", "email.yml"), "utf8");
  const runnerEnv = fs.readFileSync(path.join(runnerDir, ".env"), "utf8");

  assert.match(imagineBody, /baseUrl: http:\/\/mcp-server-imagine:8080/);
  assert.match(mockBody, /baseUrl: http:\/\/mcp-server-mock:8080/);
  assert.match(viewportMockBody, /baseUrl: http:\/\/mcp-server-mock:8080/);
  assert.match(mockBody, /endpointPath: "\/mcp"/);
  assert.match(disabledBashBody, /enabled: false/);
  assert.match(disabledDatabaseBody, /enabled: false/);
  assert.match(disabledEmailBody, /enabled: false/);
  assert.match(runnerEnv, new RegExp(`AGENTS_DIR=${escapeRegExp(path.join(deployZenmindDir, "agents"))}`));
  assert.match(runnerEnv, new RegExp(`MODELS_DIR=${escapeRegExp(path.join(deployZenmindDir, "registries", "models"))}`));
  assert.match(runnerEnv, new RegExp(`PROVIDERS_DIR=${escapeRegExp(path.join(deployZenmindDir, "registries", "providers"))}`));
  assert.match(runnerEnv, new RegExp(`MCP_SERVERS_DIR=${escapeRegExp(path.join(deployZenmindDir, "registries", "mcp-servers"))}`));
  assert.match(runnerEnv, new RegExp(`VIEWPORT_SERVERS_DIR=${escapeRegExp(path.join(deployZenmindDir, "registries", "viewport-servers"))}`));
});

test("release copy_previous_state preserves bridge runtime and optional start skips placeholder agent key", () => {
  const root = makeTempDir("zenmind-release-bridge-state-");
  const scriptPath = path.join(repoRoot, "scripts", "shared", "zenmind-setup-actions.sh");
  const previousVersionDir = path.join(root, "release", "v0.0.1");
  const nextVersionDir = path.join(root, "release", "v0.0.2");
  const previousDeploy = path.join(previousVersionDir, "deploy");
  const nextDeploy = path.join(nextVersionDir, "deploy");
  const previousBridgeDir = path.join(previousDeploy, "agent-weixin-bridge");
  const nextBridgeDir = path.join(nextDeploy, "agent-weixin-bridge");
  const nextWebclientDir = path.join(nextDeploy, "agent-webclient");

  writeFile(path.join(previousBridgeDir, ".env"), "RUNNER_AGENT_KEY=wechat-assistant\n");
  writeFile(path.join(previousBridgeDir, "runtime", "weixin-state", "credential.json"), "{\"token\":true}\n");
  writeFile(path.join(previousDeploy, "agent-webclient", ".env"), "BASE_URL=http://host.docker.internal:11949\n");
  writeFile(path.join(nextBridgeDir, ".env.example"), "RUNNER_AGENT_KEY=replace-with-runner-agent-key\n");
  writeFile(path.join(nextWebclientDir, ".env.example"), "BASE_URL=http://host.docker.internal:11949\nVOICE_BASE_URL=http://host.docker.internal:11953\n");

  const output = execFileSync("bash", ["-lc", [
    "set -euo pipefail",
    "zenmind_repo_root_path() { printf '%s\\n' \"$REPO_ROOT\"; }",
    "WARNINGS=()",
    "STARTED=()",
    "zenmind_summary_add_fail() { printf '%s\\n' \"$*\" >&2; return 1; }",
    "source \"$SCRIPT_PATH\"",
    "zenmind_summary_add_warn() { WARNINGS+=(\"$*\"); }",
    "zenmind_release_copy_previous_state \"$PREVIOUS_VERSION_DIR\" \"$NEXT_VERSION_DIR\"",
    "copied_env=$(cat \"$NEXT_DEPLOY/agent-webclient/.env\")",
    "copied_state=$(cat \"$NEXT_DEPLOY/agent-weixin-bridge/runtime/weixin-state/credential.json\")",
    "printf 'copied_env=%s\\n' \"$copied_env\"",
    "printf 'copied_state=%s\\n' \"$copied_state\"",
    "printf 'copied_bridge_env=%s\\n' \"$(cat \"$NEXT_DEPLOY/agent-weixin-bridge/.env\")\"",
    "printf 'RUNNER_AGENT_KEY=replace-with-runner-agent-key\\n' >\"$NEXT_DEPLOY/agent-weixin-bridge/.env\"",
    "zenmind_release_start_service() { STARTED+=(\"$2\"); }",
    "zenmind_release_start_weixin_bridge_if_configured \"$NEXT_VERSION_DIR\"",
    "printf 'warnings=%s\\n' \"${WARNINGS[*]}\"",
    "printf 'started=%s\\n' \"${STARTED[*]-}\""
  ].join("; ")], {
    cwd: repoRoot,
    env: {
      ...process.env,
      REPO_ROOT: root,
      SCRIPT_PATH: scriptPath,
      PREVIOUS_VERSION_DIR: previousVersionDir,
      NEXT_VERSION_DIR: nextVersionDir,
      NEXT_DEPLOY: nextDeploy
    },
    encoding: "utf8"
  });

  assert.match(output, /copied_env=BASE_URL=http:\/\/host\.docker\.internal:11949/);
  assert.match(output, /copied_state=\{"token":true\}/);
  assert.match(output, /copied_bridge_env=RUNNER_AGENT_KEY=wechat-assistant/);
  assert.match(output, /warnings=skipping agent-weixin-bridge auto-start: RUNNER_AGENT_KEY is not configured/);
  assert.match(output, /started=\s*$/);
});
