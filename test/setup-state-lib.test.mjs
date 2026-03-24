import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  getInstallStatePath,
  inferSourceInstallState,
  normalizeInstallState,
  resolveArtifactSource,
  resolveManifestReference,
  selectReleaseArtifacts,
  writeInstallState
} from "../scripts/setup-state-lib.mjs";

function makeWorkspace() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "zenmind-state-test-"));
  const workspaceRoot = path.join(root, "zenmind");
  fs.mkdirSync(workspaceRoot, { recursive: true });
  fs.writeFileSync(path.join(workspaceRoot, "VERSION"), "v0.2.0\n", "utf8");
  for (const repo of [
    "zenmind-app-server",
    "zenmind-gateway",
    "agent-platform-runner",
    "term-webclient"
  ]) {
    fs.mkdirSync(path.join(root, repo), { recursive: true });
  }
  return { root, workspaceRoot };
}

test("inferSourceInstallState builds source mode state under monorepo .zenmind", () => {
  const { workspaceRoot } = makeWorkspace();
  const state = inferSourceInstallState(workspaceRoot, {
    manifestSource: "/tmp/release-manifest.json"
  });

  assert.ok(state);
  assert.equal(state.installMode, "source");
  assert.equal(state.currentVersion, "v0.2.0");
  assert.equal(state.source.reposRoot, path.resolve(workspaceRoot, ".."));
  assert.equal(state.manifestSource, "/tmp/release-manifest.json");
});

test("writeInstallState persists normalized file in monorepo .zenmind", () => {
  const { workspaceRoot, root } = makeWorkspace();
  const statePath = writeInstallState(workspaceRoot, {
    schemaVersion: 1,
    installMode: "release",
    channel: "stable",
    currentVersion: "v0.2.0",
    previousVersion: "v0.1.0",
    manifestSource: "https://example.com/manifest.json",
    release: {
      installRoot: path.join(root, "release"),
      activeVersionDir: path.join(root, "release", "v0.2.0"),
      stagedVersionDir: ""
    }
  });

  assert.equal(statePath, getInstallStatePath(workspaceRoot));
  const saved = normalizeInstallState(JSON.parse(fs.readFileSync(statePath, "utf8")));
  assert.equal(saved.installMode, "release");
  assert.equal(saved.release.activeVersionDir, path.join(root, "release", "v0.2.0"));
});

test("resolveManifestReference accepts local version directories", () => {
  const { workspaceRoot, root } = makeWorkspace();
  const manifestDir = path.join(root, "dist", "v0.2.0");
  fs.mkdirSync(manifestDir, { recursive: true });
  fs.writeFileSync(path.join(manifestDir, "release-manifest.json"), "{}\n", "utf8");

  const resolved = resolveManifestReference(workspaceRoot, manifestDir);
  assert.equal(resolved.kind, "file");
  assert.equal(resolved.source, path.join(manifestDir, "release-manifest.json"));
});

test("selectReleaseArtifacts chooses host and linux bundle mix", () => {
  const manifest = {
    __source: "/tmp/release-manifest.json",
    artifacts: [
      { service: "agent-container-hub", os: "darwin", arch: "arm64", runtime: "host", fileName: "agent-container-hub-v0.2.0-darwin-arm64.tar.gz" },
      { service: "term-webclient", os: "darwin", arch: "arm64", runtime: "hybrid", fileName: "term-webclient-v0.2.0-darwin-arm64.tar.gz" },
      { service: "agent-platform-runner", os: "linux", arch: "arm64", runtime: "image", fileName: "agent-platform-runner-v0.2.0-linux-arm64.tar.gz" },
      { service: "mcp-server-imagine", os: "linux", arch: "arm64", runtime: "image", fileName: "mcp-server-imagine-v0.2.0-linux-arm64.tar.gz" },
      { service: "mcp-server-mock", os: "linux", arch: "arm64", runtime: "image", fileName: "mcp-server-mock-v0.2.0-linux-arm64.tar.gz" },
      { service: "pan-webclient", os: "linux", arch: "arm64", runtime: "image", fileName: "pan-webclient-v0.2.0-linux-arm64.tar.gz" },
      { service: "zenmind-app-server", os: "linux", arch: "arm64", runtime: "image", fileName: "zenmind-app-server-v0.2.0-linux-arm64.tar.gz" },
      { service: "zenmind-gateway", os: "linux", arch: "arm64", runtime: "image", fileName: "zenmind-gateway-v0.2.0-linux-arm64.tar.gz" },
      { service: "zenmind-voice-server", os: "linux", arch: "arm64", runtime: "image", fileName: "zenmind-voice-server-v0.2.0-linux-arm64.tar.gz" },
      { service: "zenmind-data", runtime: "runtime", fileName: "zenmind-data-v0.2.0.tar.gz" }
    ]
  };

  const artifacts = selectReleaseArtifacts(manifest, "darwin", "arm64");
  assert.equal(artifacts.length, 10);
  assert.equal(artifacts[0].service, "agent-container-hub");
  assert.equal(artifacts[1].service, "term-webclient");
  assert.equal(artifacts.at(-1).service, "zenmind-data");
});

test("resolveArtifactSource keeps local artifacts relative to manifest file", () => {
  const manifest = {
    __source: "/tmp/dist/v0.2.0/release-manifest.json"
  };
  const artifact = {
    service: "zenmind-gateway",
    fileName: "zenmind-gateway-v0.2.0-linux-arm64.tar.gz"
  };

  const resolved = resolveArtifactSource(manifest, artifact);
  assert.equal(resolved.kind, "file");
  assert.equal(resolved.source, "/tmp/dist/v0.2.0/zenmind-gateway-v0.2.0-linux-arm64.tar.gz");
});

test("resolveArtifactSource keeps nested release-line artifacts relative to manifest file", () => {
  const manifest = {
    __source: "/tmp/releases/v0.2/release-manifest.json"
  };
  const artifact = {
    service: "zenmind-gateway",
    url: "patches/v0.2.3/zenmind-gateway-v0.2.3-linux-arm64.tar.gz"
  };

  const resolved = resolveArtifactSource(manifest, artifact);
  assert.equal(resolved.kind, "file");
  assert.equal(resolved.source, "/tmp/releases/v0.2/patches/v0.2.3/zenmind-gateway-v0.2.3-linux-arm64.tar.gz");
});
