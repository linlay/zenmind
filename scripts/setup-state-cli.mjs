#!/usr/bin/env node
import fs from "node:fs";
import process from "node:process";

import {
  collectSourceRepoRefs,
  getHostPlatform,
  inferSourceInstallState,
  loadManifest,
  readInstallState,
  selectReleaseArtifacts,
  writeInstallState
} from "./setup-state-lib.mjs";

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--workspace-root":
        args.workspaceRoot = argv[index + 1];
        index += 1;
        break;
      case "--manifest":
        args.manifest = argv[index + 1];
        index += 1;
        break;
      case "--target-tag":
        args.targetTag = argv[index + 1];
        index += 1;
        break;
      case "--manifest-source":
        args.manifestSource = argv[index + 1];
        index += 1;
        break;
      case "--current-version":
        args.currentVersion = argv[index + 1];
        index += 1;
        break;
      case "--os":
        args.os = argv[index + 1];
        index += 1;
        break;
      case "--arch":
        args.arch = argv[index + 1];
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return args;
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  const workspaceRoot = args.workspaceRoot || process.cwd();

  switch (command) {
    case "manifest-json": {
      const manifest = await loadManifest(workspaceRoot, args.manifest || "");
      process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
      return;
    }
    case "manifest-artifacts": {
      const manifest = await loadManifest(workspaceRoot, args.manifest || "");
      const platform = {
        ...getHostPlatform(),
        ...(args.os ? { os: args.os } : {}),
        ...(args.arch ? { arch: args.arch } : {})
      };
      process.stdout.write(`${JSON.stringify(selectReleaseArtifacts(manifest, platform.os, platform.arch), null, 2)}\n`);
      return;
    }
    case "state-read": {
      const state = readInstallState(workspaceRoot);
      if (!state) {
        process.exitCode = 1;
        return;
      }
      process.stdout.write(`${JSON.stringify(state, null, 2)}\n`);
      return;
    }
    case "state-write": {
      const input = fs.readFileSync(process.stdin.fd, "utf8");
      const state = JSON.parse(input);
      const statePath = writeInstallState(workspaceRoot, state);
      process.stdout.write(`${statePath}\n`);
      return;
    }
    case "state-infer-source": {
      const state = inferSourceInstallState(workspaceRoot, {
        manifestSource: args.manifestSource || "",
        targetTag: args.targetTag || "",
        currentVersion: args.currentVersion || ""
      });
      if (!state) {
        process.exitCode = 1;
        return;
      }
      process.stdout.write(`${JSON.stringify(state, null, 2)}\n`);
      return;
    }
    case "source-refs": {
      process.stdout.write(`${JSON.stringify(collectSourceRepoRefs(workspaceRoot), null, 2)}\n`);
      return;
    }
    default:
      throw new Error(`unknown command: ${command || "<missing>"}`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
