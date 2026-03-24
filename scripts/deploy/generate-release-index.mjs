#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import {
  RELEASE_MANIFEST_SCHEMA_VERSION
} from "../setup-state-lib.mjs";

function parseArgs(argv) {
  const args = {
    releasesRoot: "",
    stableReleaseLine: "",
    stableVersion: "",
    output: ""
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--releases-root":
        args.releasesRoot = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--stable-release-line":
        args.stableReleaseLine = argv[index + 1];
        index += 1;
        break;
      case "--stable-version":
        args.stableVersion = argv[index + 1];
        index += 1;
        break;
      case "--output":
        args.output = path.resolve(argv[index + 1]);
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.releasesRoot || !args.stableReleaseLine || !args.stableVersion || !args.output) {
    throw new Error("--releases-root, --stable-release-line, --stable-version, and --output are required");
  }

  return args;
}

function readLineManifest(releasesRoot, releaseLine) {
  const manifestPath = path.join(releasesRoot, releaseLine, "release-manifest.json");
  return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const releaseLines = fs.readdirSync(args.releasesRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^v\d+\.\d+$/.test(entry.name))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right, undefined, { numeric: true }));

  const entries = releaseLines.map((releaseLine) => {
    const body = readLineManifest(args.releasesRoot, releaseLine);
    return {
      releaseLine,
      latestVersion: body.stackVersion,
      manifest: `${releaseLine}/release-manifest.json`,
      status: releaseLine === args.stableReleaseLine ? "stable" : "supported"
    };
  });

  const indexBody = {
    schemaVersion: RELEASE_MANIFEST_SCHEMA_VERSION,
    stableReleaseLine: args.stableReleaseLine,
    stableVersion: args.stableVersion,
    releaseLines: entries
  };

  fs.writeFileSync(args.output, `${JSON.stringify(indexBody, null, 2)}\n`, "utf8");
}

main();
