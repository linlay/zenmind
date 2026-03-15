#!/usr/bin/env node
import path from "node:path";
import process from "node:process";
import {
  applyProfile,
  ensureLocalProfileExists,
  getProfileLocations,
  loadProfile
} from "./zenmind-config-lib.mjs";

function parseArgs(argv) {
  const args = {
    dryRun: false,
    rootOnly: false,
    workspaceRoot: process.cwd(),
    profilePath: ""
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
      case "--root-only":
        args.rootOnly = true;
        break;
      case "--profile":
        args.profilePath = path.resolve(argv[index + 1]);
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const locations = getProfileLocations(args.workspaceRoot);
  const profilePath = args.profilePath || ensureLocalProfileExists(args.workspaceRoot);
  const profile = loadProfile(profilePath);
  const result = applyProfile({
    profile,
    workspaceRoot: args.workspaceRoot,
    reposRoot: locations.reposRoot,
    bcryptScriptPath: locations.bcryptScriptPath,
    dryRun: args.dryRun,
    rootOnly: args.rootOnly
  });

  if (args.dryRun) {
    for (const write of [...result.writes, ...result.extraSteps]) {
      process.stdout.write(`=== ${write.path}\n${write.content}\n`);
    }
    return;
  }

  process.stdout.write(`Applied profile: ${profilePath}\n`);
  process.stdout.write(`Generated compose env: ${path.join(args.workspaceRoot, "generated", "docker-compose.env")}\n`);
  process.stdout.write(`Generated gateway nginx: ${path.join(args.workspaceRoot, "generated", "gateway", "nginx.conf")}\n`);
}

main();
