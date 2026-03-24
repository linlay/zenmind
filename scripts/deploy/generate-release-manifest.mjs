#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import crypto from "node:crypto";

import {
  RELEASE_MANIFEST_SCHEMA_VERSION
} from "../setup-state-lib.mjs";

function parseArgs(argv) {
  const args = {
    distDir: "",
    version: "",
    releaseLine: "",
    channel: "stable",
    sourceTag: "",
    imageRegistry: "registry.example.com/zenmind",
    imageTag: "",
    artifactBasePath: "",
    output: "",
    writeSums: true
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--dist-dir":
        args.distDir = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--version":
        args.version = argv[index + 1];
        index += 1;
        break;
      case "--release-line":
        args.releaseLine = argv[index + 1];
        index += 1;
        break;
      case "--channel":
        args.channel = argv[index + 1];
        index += 1;
        break;
      case "--source-tag":
        args.sourceTag = argv[index + 1];
        index += 1;
        break;
      case "--image-registry":
        args.imageRegistry = argv[index + 1];
        index += 1;
        break;
      case "--image-tag":
        args.imageTag = argv[index + 1];
        index += 1;
        break;
      case "--artifact-base-path":
        args.artifactBasePath = argv[index + 1];
        index += 1;
        break;
      case "--output":
        args.output = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--no-sums":
        args.writeSums = false;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.distDir || !args.version) {
    throw new Error("--dist-dir and --version are required");
  }

  return args;
}

function detectArtifact(fileName) {
  const zenmindDataMatch = fileName.match(/^(zenmind-data)-(v\d+\.\d+\.\d+)\.tar\.gz$/);
  if (zenmindDataMatch) {
    return {
      id: "zenmind-data",
      service: "zenmind-data",
      runtime: "runtime",
      fileName
    };
  }

  const match = fileName.match(/^(.*?)-(v\d+\.\d+\.\d+)-(darwin|linux)(?:-(host))?-(amd64|arm64)\.tar\.gz$/);
  if (!match) {
    return null;
  }

  const service = match[1];
  const runtime = service === "agent-container-hub"
    ? "host"
    : service === "term-webclient"
      ? "hybrid"
      : "image";

  return {
    id: service,
    service,
    runtime,
    fileName,
    os: match[3],
    arch: match[5]
  };
}

function sha256(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const outputPath = args.output || path.join(args.distDir, "release-manifest.json");
  const files = fs.readdirSync(args.distDir)
    .filter((name) => name.endsWith(".tar.gz"))
    .sort();

  const artifacts = [];
  const sums = [];

  for (const fileName of files) {
    const artifact = detectArtifact(fileName);
    if (!artifact) {
      continue;
    }
    const filePath = path.join(args.distDir, fileName);
    const sum = sha256(filePath);
    const relativeUrl = args.artifactBasePath
      ? path.posix.join(args.artifactBasePath, fileName)
      : fileName;
    artifacts.push({
      ...artifact,
      url: relativeUrl,
      sha256: sum
    });
    sums.push(`${sum}  ${fileName}`);
  }

  const manifest = {
    schemaVersion: RELEASE_MANIFEST_SCHEMA_VERSION,
    channel: args.channel,
    stackVersion: args.version,
    releaseLine: args.releaseLine || "",
    publishedAt: new Date().toISOString(),
    sourceTag: args.sourceTag || args.version,
    images: {
      registry: args.imageRegistry,
      tag: args.imageTag || args.version
    },
    artifacts,
    upgradeNotes: "",
    breaking: false
  };

  fs.writeFileSync(
    outputPath,
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8"
  );
  if (args.writeSums) {
    fs.writeFileSync(
      path.join(args.distDir, "SHA256SUMS"),
      `${sums.join("\n")}\n`,
      "utf8"
    );
  }
}

main();
