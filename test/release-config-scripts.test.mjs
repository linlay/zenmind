import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

import {
  getDefaultProfile,
  serializeProfileToJSONString
} from "../scripts/zenmind-config-lib.mjs";

const REPO_WORKSPACE_ROOT = path.resolve(import.meta.dirname, "..");

function makeReleaseBundle(version = "v9.9.9") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "zenmind-release-script-test-"));
  const versionDir = path.join(root, "release", version);
  const deployDir = path.join(versionDir, "deploy");
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
    const serviceDir = path.join(deployDir, service);
    fs.mkdirSync(path.join(serviceDir, "configs"), { recursive: true });
    let envExample = "";
    if (service === "agent-webclient") {
      envExample = "BASE_URL=http://host.docker.internal:11949\nVOICE_BASE_URL=http://host.docker.internal:11953\n";
    } else if (service === "agent-weixin-bridge") {
      envExample = "RUNNER_BASE_URL=http://agent-platform-runner:8080\nRUNNER_AGENT_KEY=replace-with-runner-agent-key\n";
    }
    fs.writeFileSync(path.join(serviceDir, ".env.example"), envExample, "utf8");
  }
  return { root, versionDir };
}

test("apply-release-config dry-run prints release writes", () => {
  const { versionDir } = makeReleaseBundle();
  const profilePath = path.join(os.tmpdir(), `zenmind-profile-${Date.now()}.json`);
  const profile = getDefaultProfile();
  profile.website.domain = "localhost";
  profile.gateway.listenPort = 13045;
  profile.agentPlatformRunner.hostPort = 13049;
  profile.pan.webSessionSecret = "session-from-test";
  profile.admin.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.admin.appMasterPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.term.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  fs.writeFileSync(profilePath, serializeProfileToJSONString(profile), "utf8");

  const output = execFileSync("node", [
    path.join(REPO_WORKSPACE_ROOT, "scripts", "apply-release-config.mjs"),
    "--workspace-root", REPO_WORKSPACE_ROOT,
    "--profile", profilePath,
    "--version-dir", versionDir,
    "--dry-run"
  ], { encoding: "utf8" });

  assert.match(output, /zenmind-app-server\/\.env/);
  assert.match(output, /AUTH_ISSUER=http:\/\/127\.0\.0\.1:13045/);
  assert.match(output, /pan-webclient\/\.env/);
  assert.match(output, /WEB_SESSION_SECRET=session-from-test/);
  assert.match(output, /agent-webclient\/\.env/);
  assert.match(output, /BASE_URL=http:\/\/host\.docker\.internal:13049/);
  assert.match(output, /VOICE_BASE_URL=http:\/\/host\.docker\.internal:11953/);
  assert.match(output, /agent-weixin-bridge\/\.env/);
  assert.match(output, /RUNNER_BASE_URL=http:\/\/agent-platform-runner:8080/);
  assert.match(output, /issuer=http:\/\/127\.0\.0\.1:13045/);
});

test("generate-default-profile writes bcrypt-only profile and chmod 600 credentials", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "zenmind-generate-profile-test-"));
  const profilePath = path.join(root, "config", "zenmind.profile.local.json");
  const credentialsFile = path.join(root, ".zenmind-credentials.txt");

  execFileSync("node", [
    path.join(REPO_WORKSPACE_ROOT, "scripts", "generate-default-profile.mjs"),
    "--workspace-root", REPO_WORKSPACE_ROOT,
    "--profile", profilePath,
    "--credentials-file", credentialsFile
  ], { encoding: "utf8" });

  const profile = JSON.parse(fs.readFileSync(profilePath, "utf8"));
  const credentials = fs.readFileSync(credentialsFile, "utf8");
  const mode = fs.statSync(credentialsFile).mode & 0o777;

  assert.match(profile.admin.webPasswordBcrypt, /^\$2[aby]\$/);
  assert.match(profile.admin.appMasterPasswordBcrypt, /^\$2[aby]\$/);
  assert.match(profile.pan.webPasswordBcrypt, /^\$2[aby]\$/);
  assert.match(profile.term.webPasswordBcrypt, /^\$2[aby]\$/);
  assert.match(profile.pan.webSessionSecret, /[A-Za-z0-9_-]{20,}/);
  assert.ok(!("webPassword" in profile.admin));
  assert.match(credentials, /admin_web_password=/);
  assert.match(credentials, /profile_path=/);
  assert.equal(mode, 0o600);
});
