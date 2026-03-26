#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import {
  applyToRelease,
  getProfileLocations,
  getDefaultProfile,
  loadProfile,
  serializeProfileToJSONString
} from "./zenmind-config-lib.mjs";
import {
  getInstallProfilePath,
  loadInstallProfile,
  mergeInstallProfileIntoProfile
} from "./install-profile-lib.mjs";

function parseArgs(argv) {
  const args = {
    dryRun: false,
    workspaceRoot: process.cwd(),
    installProfilePath: "",
    profilePath: "",
    versionDir: ""
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--workspace-root":
        args.workspaceRoot = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--install-profile":
        args.installProfilePath = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--profile":
        args.profilePath = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--version-dir":
        args.versionDir = path.resolve(argv[index + 1]);
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.versionDir) {
    throw new Error("--version-dir is required");
  }

  return args;
}

function readYamlScalar(content, key) {
  const match = String(content || "").match(new RegExp(`^${key}:\\s*(.+)$`, "m"));
  return match ? match[1].trim().replace(/^['"]|['"]$/g, "") : "";
}

function writeYamlScalar(content, key, value) {
  const normalizedValue = String(value ?? "").replace(/\r/g, "");
  if (new RegExp(`^${key}:\\s*`, "m").test(content)) {
    return content.replace(new RegExp(`^${key}:\\s*.*$`, "m"), `${key}: ${normalizedValue}`);
  }
  const trimmed = String(content || "").replace(/\s*$/, "");
  return `${trimmed}\n${key}: ${normalizedValue}\n`;
}

function findRegistryFile(registryDir, desiredKey) {
  const files = fs.readdirSync(registryDir)
    .filter((fileName) => fileName.endsWith(".yml") || fileName.endsWith(".yaml"))
    .map((fileName) => path.join(registryDir, fileName));

  for (const filePath of files) {
    const body = fs.readFileSync(filePath, "utf8");
    const key = readYamlScalar(body, "key");
    if (key === desiredKey || path.basename(filePath, path.extname(filePath)) === desiredKey) {
      return filePath;
    }
  }

  throw new Error(`registry entry not found for key '${desiredKey}' in ${registryDir}`);
}

function collectRuntimeWrites(versionDir, installProfile) {
  const deployZenmindDir = path.join(versionDir, "deploy", ".zenmind");
  const providersDir = path.join(deployZenmindDir, "registries", "providers");
  const modelsDir = path.join(deployZenmindDir, "registries", "models");
  const agentsDir = path.join(deployZenmindDir, "agents");

  const providerFile = findRegistryFile(providersDir, installProfile.primaryProvider);
  const modelFile = findRegistryFile(modelsDir, installProfile.primaryModel);
  const providerBody = fs.readFileSync(providerFile, "utf8");
  const modelBody = fs.readFileSync(modelFile, "utf8");
  const modelId = readYamlScalar(modelBody, "modelId");

  const writes = [];
  writes.push({
    path: providerFile,
    content: writeYamlScalar(
      writeYamlScalar(providerBody, "apiKey", installProfile.primaryApiKey),
      "defaultModel",
      modelId || installProfile.primaryModel
    )
  });
  writes.push({
    path: modelFile,
    content: writeYamlScalar(modelBody, "provider", installProfile.primaryProvider)
  });

  const agentFiles = [];
  if (fs.existsSync(agentsDir)) {
    const stack = [agentsDir];
    while (stack.length > 0) {
      const current = stack.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const fullPath = path.join(current, entry.name);
        if (entry.isDirectory()) {
          stack.push(fullPath);
          continue;
        }
        if (entry.isFile() && entry.name === "agent.yml") {
          agentFiles.push(fullPath);
        }
      }
    }
  }

  for (const filePath of agentFiles) {
    const body = fs.readFileSync(filePath, "utf8");
    if (!/^modelKey:\s*/m.test(body)) {
      continue;
    }
    writes.push({
      path: filePath,
      content: body.replace(/^modelKey:\s*.*$/m, `modelKey: ${installProfile.primaryModel}`)
    });
  }

  return writes;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const locations = getProfileLocations(args.workspaceRoot);
  const installProfilePath = args.installProfilePath || getInstallProfilePath(args.workspaceRoot);
  const profilePath = args.profilePath || locations.profileLocalPath;
  const installProfile = loadInstallProfile(installProfilePath);
  const baseProfile = fs.existsSync(profilePath) ? loadProfile(profilePath) : getDefaultProfile();
  const mergedProfile = mergeInstallProfileIntoProfile(baseProfile, installProfile, locations.bcryptScriptPath);
  const releaseResult = applyToRelease({
    profile: mergedProfile,
    workspaceRoot: args.workspaceRoot,
    versionDir: args.versionDir,
    bcryptScriptPath: locations.bcryptScriptPath,
    dryRun: args.dryRun
  });
  const runtimeWrites = collectRuntimeWrites(args.versionDir, installProfile);

  if (args.dryRun) {
    process.stdout.write(`=== ${profilePath}\n${serializeProfileToJSONString(mergedProfile)}`);
    for (const write of [...releaseResult.writes, ...runtimeWrites]) {
      process.stdout.write(`=== ${write.path}\n${write.content}\n`);
    }
    return;
  }

  fs.mkdirSync(path.dirname(profilePath), { recursive: true });
  fs.writeFileSync(profilePath, serializeProfileToJSONString(mergedProfile), "utf8");
  for (const write of runtimeWrites) {
    fs.mkdirSync(path.dirname(write.path), { recursive: true });
    fs.writeFileSync(write.path, write.content, "utf8");
  }

  process.stdout.write(`Applied install profile: ${installProfilePath}\n`);
  process.stdout.write(`Updated aggregate profile: ${profilePath}\n`);
  process.stdout.write(`Updated release version: ${args.versionDir}\n`);
}

main();
