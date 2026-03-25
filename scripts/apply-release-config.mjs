#!/usr/bin/env node
import path from "node:path";
import process from "node:process";
import {
  applyToRelease,
  ensureLocalProfileExists,
  getProfileLocations,
  loadProfile
} from "./zenmind-config-lib.mjs";

function parseArgs(argv) {
  const args = {
    dryRun: false,
    workspaceRoot: process.cwd(),
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

function main() {
  const args = parseArgs(process.argv.slice(2));
  const locations = getProfileLocations(args.workspaceRoot);
  const profilePath = args.profilePath || ensureLocalProfileExists(args.workspaceRoot);
  const profile = loadProfile(profilePath);
  const result = applyToRelease({
    profile,
    workspaceRoot: args.workspaceRoot,
    versionDir: args.versionDir,
    bcryptScriptPath: locations.bcryptScriptPath,
    dryRun: args.dryRun
  });

  if (args.dryRun) {
    for (const write of result.writes) {
      process.stdout.write(`=== ${write.path}\n${write.content}\n`);
    }
    process.stdout.write(`issuer=${result.meta.releaseIssuer}\n`);
    process.stdout.write(`enabled=${JSON.stringify(result.meta.enabled)}\n`);
    return;
  }

  process.stdout.write(`Applied release profile: ${profilePath}\n`);
  process.stdout.write(`Version dir: ${args.versionDir}\n`);
  process.stdout.write(`Issuer: ${result.meta.releaseIssuer}\n`);
}

main();
