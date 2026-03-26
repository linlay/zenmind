#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

export const DEFAULT_REMOTE_MANIFEST_URL = "https://www.zenmind.cc/install/manifest.json";
export const INSTALL_STATE_SCHEMA_VERSION = 2;
export const RELEASE_MANIFEST_SCHEMA_VERSION = 1;

const SOURCE_REPOS = [
  "zenmind",
  "zenmind-app-server",
  "zenmind-voice-server",
  "zenmind-gateway",
  "agent-platform-runner",
  "agent-container-hub",
  "pan-webclient",
  "term-webclient",
  "mcp-server-mock",
  "mcp-server-imagine"
];

const REQUIRED_SOURCE_REPOS = [
  "zenmind-app-server",
  "zenmind-gateway",
  "agent-platform-runner",
  "term-webclient"
];

const RELEASE_BUNDLE_REQUIREMENTS = [
  { service: "agent-container-hub", os: "host", runtime: "host" },
  { service: "term-webclient", os: "host", runtime: "hybrid" },
  { service: "agent-platform-runner", os: "linux", runtime: "image" },
  { service: "mcp-server-imagine", os: "linux", runtime: "image" },
  { service: "mcp-server-mock", os: "linux", runtime: "image" },
  { service: "pan-webclient", os: "linux", runtime: "image" },
  { service: "zenmind-app-server", os: "linux", runtime: "image" },
  { service: "zenmind-voice-server", os: "linux", runtime: "image" },
  { service: "agent-webclient", os: "linux", runtime: "image" },
  { service: "agent-weixin-bridge", os: "linux", runtime: "image" },
  { service: "zenmind-gateway", os: "linux", runtime: "image" },
  { service: "zenmind-data", os: "any", runtime: "runtime" }
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function parseJSON(text, label) {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`invalid JSON in ${label}: ${error.message}`);
  }
}

function readJSONFile(filePath) {
  return parseJSON(fs.readFileSync(filePath, "utf8"), filePath);
}

function detectArtifactDetailsFromName(fileName) {
  if (!fileName) {
    return {};
  }

  const zenmindDataMatch = fileName.match(/^(zenmind-data)-(v\d+\.\d+\.\d+)\.tar\.gz$/);
  if (zenmindDataMatch) {
    return {
      service: "zenmind-data",
      version: zenmindDataMatch[2],
      runtime: "runtime"
    };
  }

  const genericMatch = fileName.match(/^(.*?)-(v\d+\.\d+\.\d+)-(darwin|linux)(?:-(host))?-(amd64|arm64)\.tar\.gz$/);
  if (!genericMatch) {
    return {};
  }

  const service = genericMatch[1];
  const runtime = service === "agent-container-hub"
    ? "host"
    : service === "term-webclient"
      ? "hybrid"
      : "image";

  return {
    service,
    version: genericMatch[2],
    os: genericMatch[3],
    arch: genericMatch[4],
    runtime
  };
}

function trimString(value, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function normalizeStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => trimString(item))
    .filter(Boolean);
}

function normalizePermissionChecks(rawValue) {
  if (!rawValue || typeof rawValue !== "object") {
    return {
      containerHub: "",
      termWebclientServer: ""
    };
  }
  return {
    containerHub: trimString(rawValue.containerHub || ""),
    termWebclientServer: trimString(rawValue.termWebclientServer || "")
  };
}

function normalizeArtifact(rawArtifact) {
  const fileName = trimString(rawArtifact?.fileName || rawArtifact?.name || "");
  const inferred = detectArtifactDetailsFromName(fileName);
  return {
    id: trimString(rawArtifact?.id || rawArtifact?.service || inferred.service || fileName),
    service: trimString(rawArtifact?.service || inferred.service || rawArtifact?.id || fileName),
    runtime: trimString(rawArtifact?.runtime || inferred.runtime || "image"),
    fileName,
    url: trimString(rawArtifact?.url || ""),
    path: trimString(rawArtifact?.path || ""),
    os: trimString(rawArtifact?.os || rawArtifact?.platform?.os || inferred.os || ""),
    arch: trimString(rawArtifact?.arch || rawArtifact?.platform?.arch || inferred.arch || ""),
    sha256: trimString(rawArtifact?.sha256 || "")
  };
}

function buildDefaultImages(stackVersion) {
  return {
    registry: "registry.example.com/zenmind",
    tag: stackVersion || "latest"
  };
}

function normalizeManifest(rawManifest, source = "") {
  const stackVersion = trimString(rawManifest?.stackVersion || "");
  assert(stackVersion, "manifest stackVersion is required");

  const images = rawManifest?.images && typeof rawManifest.images === "object"
    ? {
        registry: trimString(rawManifest.images.registry || buildDefaultImages(stackVersion).registry),
        tag: trimString(rawManifest.images.tag || buildDefaultImages(stackVersion).tag)
      }
    : buildDefaultImages(stackVersion);

  const artifacts = Array.isArray(rawManifest?.artifacts)
    ? rawManifest.artifacts.map(normalizeArtifact)
    : [];

  return {
    schemaVersion: Number.isInteger(rawManifest?.schemaVersion)
      ? rawManifest.schemaVersion
      : RELEASE_MANIFEST_SCHEMA_VERSION,
    channel: trimString(rawManifest?.channel || "stable"),
    releaseLine: trimString(rawManifest?.releaseLine || ""),
    stackVersion,
    publishedAt: trimString(rawManifest?.publishedAt || ""),
    sourceTag: trimString(rawManifest?.sourceTag || stackVersion),
    images,
    artifacts,
    upgradeNotes: trimString(rawManifest?.upgradeNotes || ""),
    breaking: Boolean(rawManifest?.breaking),
    __source: source
  };
}

function isHttpUrl(value) {
  return /^https?:\/\//.test(value);
}

export function getWorkspaceRoot(input = process.cwd()) {
  return path.resolve(input);
}

export function getMonorepoRoot(workspaceRoot) {
  return path.resolve(getWorkspaceRoot(workspaceRoot), "..");
}

export function getInstallStatePath(workspaceRoot) {
  return path.join(getMonorepoRoot(workspaceRoot), ".zenmind", "install-state.json");
}

export function getReleaseRootPath(workspaceRoot) {
  return path.join(getMonorepoRoot(workspaceRoot), "release");
}

export function resolveManifestReference(workspaceRoot, manifestArg = "") {
  const rawValue = trimString(manifestArg || "");
  if (!rawValue) {
    return { kind: "url", source: DEFAULT_REMOTE_MANIFEST_URL };
  }

  if (isHttpUrl(rawValue)) {
    return { kind: "url", source: rawValue };
  }

  const resolvedPath = path.resolve(rawValue);
  const stats = fs.existsSync(resolvedPath) ? fs.statSync(resolvedPath) : null;
  if (stats?.isDirectory()) {
    return {
      kind: "file",
      source: path.join(resolvedPath, "release-manifest.json")
    };
  }

  if (resolvedPath.endsWith(".json")) {
    return { kind: "file", source: resolvedPath };
  }

  if (fs.existsSync(path.join(resolvedPath, "release-manifest.json"))) {
    return {
      kind: "file",
      source: path.join(resolvedPath, "release-manifest.json")
    };
  }

  return {
    kind: "file",
    source: path.resolve(getWorkspaceRoot(workspaceRoot), rawValue)
  };
}

async function readManifestJson(reference) {
  if (reference.kind === "file") {
    assert(fs.existsSync(reference.source), `manifest not found: ${reference.source}`);
    return readJSONFile(reference.source);
  }

  const response = await fetch(reference.source);
  if (!response.ok) {
    throw new Error(`failed to fetch manifest: ${reference.source} (${response.status})`);
  }
  return parseJSON(await response.text(), reference.source);
}

export async function loadManifest(workspaceRoot, manifestArg = "") {
  const reference = resolveManifestReference(workspaceRoot, manifestArg);
  const raw = await readManifestJson(reference);
  return normalizeManifest(raw, reference.source);
}

export function resolveArtifactSource(manifest, artifact) {
  const manifestSource = trimString(manifest?.__source || "");
  const candidate = trimString(artifact.path || artifact.url || artifact.fileName || "");
  assert(candidate, `artifact location missing for ${artifact.service || artifact.id}`);

  if (isHttpUrl(candidate)) {
    return { kind: "url", source: candidate };
  }

  if (isHttpUrl(manifestSource)) {
    return {
      kind: "url",
      source: new URL(candidate, manifestSource).href
    };
  }

  const baseDir = manifestSource
    ? path.dirname(manifestSource)
    : getWorkspaceRoot();
  return {
    kind: "file",
    source: path.resolve(baseDir, candidate)
  };
}

export function selectReleaseArtifacts(manifest, hostOs, hostArch) {
  const selected = [];

  for (const requirement of RELEASE_BUNDLE_REQUIREMENTS) {
    const desiredOs = requirement.os === "host" ? hostOs : requirement.os;
    const desiredArch = requirement.service === "zenmind-data" ? "" : hostArch;
    const artifact = manifest.artifacts.find((item) => {
      if (item.service !== requirement.service) {
        return false;
      }
      if (requirement.service === "zenmind-data") {
        return true;
      }
      return item.os === desiredOs && item.arch === desiredArch;
    });
    assert(
      artifact,
      `manifest is missing artifact for ${requirement.service} (${desiredOs || "any"}/${desiredArch || "any"})`
    );
    selected.push({
      ...artifact,
      source: resolveArtifactSource(manifest, artifact)
    });
  }

  return selected;
}

export function normalizeInstallState(rawState) {
  assert(rawState && typeof rawState === "object", "install state must be an object");
  const installMode = trimString(rawState.installMode);
  assert(installMode === "source" || installMode === "release", "installMode must be source or release");
  const currentVersion = trimString(rawState.currentVersion || "");
  const explicitPhase = trimString(rawState.phase || "");
  const explicitBrowserSetupCompleted = rawState.browserSetupCompleted;
  const hasCompletedReleaseInstall = installMode === "release" && Boolean(currentVersion);
  const phase = explicitPhase || (hasCompletedReleaseInstall ? "complete" : "");
  const browserSetupCompleted = typeof explicitBrowserSetupCompleted === "boolean"
    ? explicitBrowserSetupCompleted
    : hasCompletedReleaseInstall;

  return {
    schemaVersion: Number.isInteger(rawState.schemaVersion)
      ? rawState.schemaVersion
      : INSTALL_STATE_SCHEMA_VERSION,
    installMode,
    channel: trimString(rawState.channel || "stable"),
    currentVersion,
    previousVersion: trimString(rawState.previousVersion || ""),
    manifestSource: trimString(rawState.manifestSource || ""),
    lastCheckedAt: trimString(rawState.lastCheckedAt || ""),
    lastInstalledAt: trimString(rawState.lastInstalledAt || ""),
    lastUpgradedAt: trimString(rawState.lastUpgradedAt || ""),
    phase,
    isFreshInstall: typeof rawState.isFreshInstall === "boolean"
      ? rawState.isFreshInstall
      : !trimString(rawState.previousVersion || ""),
    browserSetupCompleted,
    permissionChecks: normalizePermissionChecks(rawState.permissionChecks),
    profilePath: trimString(rawState.profilePath || ""),
    installProfilePath: trimString(rawState.installProfilePath || ""),
    completedSteps: normalizeStringArray(rawState.completedSteps),
    lastError: trimString(rawState.lastError || ""),
    source: installMode === "source" && rawState.source && typeof rawState.source === "object"
      ? {
          reposRoot: trimString(rawState.source.reposRoot || ""),
          targetTag: trimString(rawState.source.targetTag || rawState.currentVersion || ""),
          repoRefs: rawState.source.repoRefs && typeof rawState.source.repoRefs === "object"
            ? rawState.source.repoRefs
            : {}
        }
      : null,
    release: installMode === "release" && rawState.release && typeof rawState.release === "object"
      ? {
          installRoot: trimString(rawState.release.installRoot || ""),
          activeVersionDir: trimString(rawState.release.activeVersionDir || ""),
          stagedVersionDir: trimString(rawState.release.stagedVersionDir || "")
        }
      : null
  };
}

export function readInstallState(workspaceRoot) {
  const statePath = getInstallStatePath(workspaceRoot);
  if (!fs.existsSync(statePath)) {
    return null;
  }
  return normalizeInstallState(readJSONFile(statePath));
}

export function writeInstallState(workspaceRoot, state) {
  const normalized = normalizeInstallState(state);
  const statePath = getInstallStatePath(workspaceRoot);
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  fs.writeFileSync(statePath, `${JSON.stringify(normalized, null, 2)}\n`, "utf8");
  return statePath;
}

function gitOutput(repoDir, args) {
  try {
    return execFileSync("git", ["-C", repoDir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim();
  } catch {
    return "";
  }
}

function collectRepoRef(repoDir) {
  if (!fs.existsSync(path.join(repoDir, ".git"))) {
    return "";
  }
  const exactTag = gitOutput(repoDir, ["describe", "--tags", "--exact-match"]);
  if (exactTag) {
    return exactTag;
  }
  return gitOutput(repoDir, ["rev-parse", "HEAD"]);
}

export function collectSourceRepoRefs(workspaceRoot) {
  const repoRoot = getMonorepoRoot(workspaceRoot);
  const refs = {};
  for (const repoName of SOURCE_REPOS) {
    const repoDir = repoName === "zenmind"
      ? getWorkspaceRoot(workspaceRoot)
      : path.join(repoRoot, repoName);
    const ref = collectRepoRef(repoDir);
    if (ref) {
      refs[repoName] = ref;
    }
  }
  return refs;
}

function readVersionFile(workspaceRoot) {
  const versionFile = path.join(getWorkspaceRoot(workspaceRoot), "VERSION");
  if (!fs.existsSync(versionFile)) {
    return "";
  }
  return trimString(fs.readFileSync(versionFile, "utf8"));
}

export function inferSourceInstallState(workspaceRoot, options = {}) {
  const repoRoot = getMonorepoRoot(workspaceRoot);
  const sourceReady = REQUIRED_SOURCE_REPOS.every((repoName) => fs.existsSync(path.join(repoRoot, repoName)));
  if (!sourceReady) {
    return null;
  }

  const currentVersion = trimString(options.currentVersion || readVersionFile(workspaceRoot) || "");
  const targetTag = trimString(options.targetTag || currentVersion || "");

  return normalizeInstallState({
    schemaVersion: INSTALL_STATE_SCHEMA_VERSION,
    installMode: "source",
    channel: "stable",
    currentVersion,
    previousVersion: "",
    manifestSource: trimString(options.manifestSource || ""),
    lastCheckedAt: trimString(options.lastCheckedAt || ""),
    lastInstalledAt: trimString(options.lastInstalledAt || ""),
    lastUpgradedAt: trimString(options.lastUpgradedAt || ""),
    source: {
      reposRoot: repoRoot,
      targetTag,
      repoRefs: collectSourceRepoRefs(workspaceRoot)
    }
  });
}

export function getHostPlatform() {
  const osValue = os.platform() === "darwin" ? "darwin" : "linux";
  const archValue = os.arch() === "x64" ? "amd64" : "arm64";
  return { os: osValue, arch: archValue };
}
