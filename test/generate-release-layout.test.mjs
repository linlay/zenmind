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

test("collect-dist builds exact patch, release-line aliases, and stable index", () => {
  const root = makeTempDir("zenmind-collect-dist-");
  const monoRoot = path.join(root, "mono");
  const zenmindRoot = path.join(monoRoot, "zenmind");
  const scriptSource = path.join(repoRoot, "scripts", "deploy", "collect-dist.sh");
  const manifestScriptSource = path.join(repoRoot, "scripts", "deploy", "generate-release-manifest.mjs");
  const indexScriptSource = path.join(repoRoot, "scripts", "deploy", "generate-release-index.mjs");
  const stateLibSource = path.join(repoRoot, "scripts", "setup-state-lib.mjs");
  const targetRoot = path.join(root, "releases");
  const patchDir = path.join(targetRoot, "v0.1", "patches", "v0.1.3");

  fs.mkdirSync(path.join(zenmindRoot, "scripts", "deploy"), { recursive: true });
  fs.mkdirSync(path.join(zenmindRoot, "scripts"), { recursive: true });
  fs.copyFileSync(scriptSource, path.join(zenmindRoot, "scripts", "deploy", "collect-dist.sh"));
  fs.copyFileSync(manifestScriptSource, path.join(zenmindRoot, "scripts", "deploy", "generate-release-manifest.mjs"));
  fs.copyFileSync(indexScriptSource, path.join(zenmindRoot, "scripts", "deploy", "generate-release-index.mjs"));
  fs.copyFileSync(stateLibSource, path.join(zenmindRoot, "scripts", "setup-state-lib.mjs"));

  for (const project of [
    "zenmind",
    "zenmind-gateway",
    "zenmind-app-server",
    "zenmind-voice-server",
    "pan-webclient",
    "term-webclient",
    "agent-container-hub",
    "agent-platform-runner",
    "mcp-server-imagine",
    "mcp-server-mock"
  ]) {
    const distRoot = project === "zenmind"
      ? path.join(monoRoot, ".zenmind", "dist")
      : path.join(monoRoot, project, "dist");
    let artifactName = "";
    switch (project) {
      case "zenmind":
        artifactName = "zenmind-data-v0.1.3.tar.gz";
        break;
      case "term-webclient":
        artifactName = "term-webclient-v0.1.3-darwin-host-arm64.tar.gz";
        break;
      case "agent-container-hub":
        artifactName = "agent-container-hub-v0.1.3-darwin-arm64.tar.gz";
        break;
      default:
        artifactName = `${project}-v0.1.3-linux-arm64.tar.gz`;
        break;
    }
    writeFile(path.join(distRoot, artifactName), `${project}\n`);
  }

  execFileSync("bash", [path.join(zenmindRoot, "scripts", "deploy", "collect-dist.sh"), "v0.1.3"], {
    cwd: zenmindRoot,
    env: {
      ...process.env,
      SOURCE_ROOT: monoRoot,
      TARGET_ROOT: targetRoot
    },
    stdio: "pipe"
  });

  const exactManifest = JSON.parse(fs.readFileSync(path.join(patchDir, "release-manifest.json"), "utf8"));
  const lineManifest = JSON.parse(fs.readFileSync(path.join(targetRoot, "v0.1", "release-manifest.json"), "utf8"));
  const stableManifest = JSON.parse(fs.readFileSync(path.join(targetRoot, "manifest.json"), "utf8"));
  const indexBody = JSON.parse(fs.readFileSync(path.join(targetRoot, "index.json"), "utf8"));

  assert.equal(exactManifest.stackVersion, "v0.1.3");
  assert.equal(exactManifest.releaseLine, "v0.1");
  assert.match(exactManifest.artifacts[0].url, /^[^/]+\.tar\.gz$/);
  assert.equal(fs.existsSync(path.join(patchDir, "SHA256SUMS")), true);

  assert.equal(lineManifest.stackVersion, "v0.1.3");
  assert.equal(lineManifest.releaseLine, "v0.1");
  assert.match(lineManifest.artifacts[0].url, /^patches\/v0\.1\.3\//);

  assert.equal(stableManifest.stackVersion, "v0.1.3");
  assert.equal(stableManifest.releaseLine, "v0.1");
  assert.match(stableManifest.artifacts[0].url, /^v0\.1\/patches\/v0\.1\.3\//);

  assert.equal(indexBody.stableReleaseLine, "v0.1");
  assert.equal(indexBody.stableVersion, "v0.1.3");
  assert.deepEqual(indexBody.releaseLines, [
    {
      releaseLine: "v0.1",
      latestVersion: "v0.1.3",
      manifest: "v0.1/release-manifest.json",
      status: "stable"
    }
  ]);
});
