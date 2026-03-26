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

test("apply-install-profile updates aggregate profile and release runtime config", () => {
  const root = makeTempDir("zenmind-apply-install-profile-");
  const workspaceRoot = path.join(root, "zenmind");
  const monorepoRoot = path.join(workspaceRoot, "..");
  const versionDir = path.join(monorepoRoot, "release", "v0.0.1");
  const deployDir = path.join(versionDir, "deploy");
  const installProfilePath = path.join(monorepoRoot, ".zenmind", "install-profile.json");
  const profileLocalPath = path.join(workspaceRoot, "config", "zenmind.profile.local.json");

  writeFile(
    path.join(workspaceRoot, "config", "zenmind.profile.example.json"),
    fs.readFileSync(path.join(repoRoot, "config", "zenmind.profile.example.json"), "utf8")
  );
  writeFile(
    path.join(workspaceRoot, "scripts", "shared", "generate-bcrypt.sh"),
    fs.readFileSync(path.join(repoRoot, "scripts", "shared", "generate-bcrypt.sh"), "utf8")
  );
  fs.chmodSync(path.join(workspaceRoot, "scripts", "shared", "generate-bcrypt.sh"), 0o755);
  writeFile(
    path.join(workspaceRoot, "scripts", "mac", "setup-common.sh"),
    fs.readFileSync(path.join(repoRoot, "scripts", "mac", "setup-common.sh"), "utf8")
  );

  writeFile(installProfilePath, JSON.stringify({
    schemaVersion: 1,
    siteName: "localhost",
    adminUsername: "ops",
    adminPassword: "Secret123!",
    primaryProvider: "bailian",
    primaryModel: "bailian-qwen3_5-plus",
    primaryApiKey: "sk-live-123"
  }, null, 2));

  for (const service of [
    "zenmind-app-server",
    "pan-webclient",
    "term-webclient",
    "zenmind-gateway",
    "agent-platform-runner",
    "agent-container-hub",
    "agent-webclient",
    "agent-weixin-bridge"
  ]) {
    writeFile(path.join(deployDir, service, ".env.example"), "\n");
  }
  writeFile(path.join(deployDir, "agent-platform-runner", "configs", "container-hub.example.yml"), "enabled: false\n");
  writeFile(path.join(deployDir, ".zenmind", "registries", "providers", "bailian.yml"), [
    "key: bailian",
    "baseUrl: https://dashscope.aliyuncs.com/compatible-mode",
    "apiKey: placeholder",
    "defaultModel: old-model",
    ""
  ].join("\n"));
  writeFile(path.join(deployDir, ".zenmind", "registries", "models", "bailian-qwen3_5-plus.yml"), [
    "key: bailian-qwen3_5-plus",
    "provider: legacy-provider",
    "protocol: OPENAI",
    "modelId: qwen3.5-plus",
    ""
  ].join("\n"));
  writeFile(path.join(deployDir, ".zenmind", "agents", "zenmi", "agent.yml"), [
    "key: zenmi",
    "modelKey: old-model",
    ""
  ].join("\n"));

  execFileSync("node", [
    path.join(repoRoot, "scripts", "apply-install-profile.mjs"),
    "--workspace-root", workspaceRoot,
    "--install-profile", installProfilePath,
    "--version-dir", versionDir
  ], {
    cwd: repoRoot,
    stdio: "pipe"
  });

  const savedProfile = JSON.parse(fs.readFileSync(profileLocalPath, "utf8"));
  assert.equal(savedProfile.admin.adminUsername, "ops");
  assert.equal(savedProfile.pan.adminUsername, "ops");
  assert.equal(savedProfile.term.authUsername, "ops");
  assert.equal(savedProfile.llm.primaryProviderKey, "bailian");
  assert.equal(savedProfile.llm.primaryModelKey, "bailian-qwen3_5-plus");
  assert.equal(savedProfile.llm.primaryApiKey, "sk-live-123");
  assert.equal(savedProfile.containerHub.enabled, true);

  const appEnv = fs.readFileSync(path.join(deployDir, "zenmind-app-server", ".env"), "utf8");
  const panEnv = fs.readFileSync(path.join(deployDir, "pan-webclient", ".env"), "utf8");
  const termEnv = fs.readFileSync(path.join(deployDir, "term-webclient", ".env"), "utf8");
  const providerBody = fs.readFileSync(path.join(deployDir, ".zenmind", "registries", "providers", "bailian.yml"), "utf8");
  const modelBody = fs.readFileSync(path.join(deployDir, ".zenmind", "registries", "models", "bailian-qwen3_5-plus.yml"), "utf8");
  const agentBody = fs.readFileSync(path.join(deployDir, ".zenmind", "agents", "zenmi", "agent.yml"), "utf8");

  assert.match(appEnv, /AUTH_ADMIN_USERNAME=ops/);
  assert.match(panEnv, /PAN_ADMIN_USERNAME=ops/);
  assert.match(termEnv, /AUTH_USERNAME=ops/);
  assert.match(providerBody, /apiKey: sk-live-123/);
  assert.match(providerBody, /defaultModel: qwen3\.5-plus/);
  assert.match(modelBody, /provider: bailian/);
  assert.match(agentBody, /modelKey: bailian-qwen3_5-plus/);
});
