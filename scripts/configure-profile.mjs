#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";

import {
  ensureLocalProfileExists,
  loadProfile,
  serializeProfileToJSONString
} from "./zenmind-config-lib.mjs";

function parseArgs(argv) {
  const args = {
    workspaceRoot: process.cwd(),
    profilePath: ""
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--workspace-root":
        args.workspaceRoot = path.resolve(argv[index + 1]);
        index += 1;
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

function normalizeYesNo(input, defaultValue) {
  const trimmed = String(input || "").trim().toLowerCase();
  if (!trimmed) {
    return defaultValue;
  }
  if (["y", "yes", "1", "true"].includes(trimmed)) {
    return true;
  }
  if (["n", "no", "0", "false"].includes(trimmed)) {
    return false;
  }
  return defaultValue;
}

function generateSecret() {
  return crypto.randomBytes(24).toString("hex");
}

async function promptText(rl, label, currentValue, { optional = false } = {}) {
  while (true) {
    const suffix = currentValue ? ` [${currentValue}]` : optional ? " [optional]" : "";
    const answer = (await rl.question(`${label}${suffix}: `)).trim();
    if (answer) {
      return answer;
    }
    if (currentValue) {
      return currentValue;
    }
    if (optional) {
      return "";
    }
  }
}

async function promptInteger(rl, label, currentValue) {
  while (true) {
    const answer = (await rl.question(`${label} [${currentValue}]: `)).trim();
    const value = answer || String(currentValue);
    const parsed = Number.parseInt(value, 10);
    if (Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535) {
      return parsed;
    }
    process.stdout.write(`Invalid port: ${value}\n`);
  }
}

async function promptBoolean(rl, label, currentValue) {
  const answer = await rl.question(`${label} [${currentValue ? "Y/n" : "y/N"}]: `);
  return normalizeYesNo(answer, currentValue);
}

async function main() {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error("interactive CLI configure requires a TTY");
  }

  const args = parseArgs(process.argv.slice(2));
  const profilePath = args.profilePath || ensureLocalProfileExists(args.workspaceRoot);
  const profile = loadProfile(profilePath);
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  try {
    process.stdout.write("== ZenMind CLI Configure ==\n");
    process.stdout.write("Only the aggregate JSON will be updated. Generated files are not touched in this step.\n\n");

    profile.website.domain = await promptText(rl, "Website domain", profile.website.domain);
    profile.images.registry = await promptText(rl, "Image registry/namespace", profile.images.registry);
    profile.images.tag = await promptText(rl, "Image tag", profile.images.tag);
    profile.cloudflared.tunnelUuid = await promptText(rl, "Cloudflare Tunnel UUID", profile.cloudflared.tunnelUuid, { optional: true });
    profile.gateway.listenPort = await promptInteger(rl, "Gateway listen port", profile.gateway.listenPort);
    profile.agentPlatformRunner.baseUrl = await promptText(rl, "Runner base URL", profile.agentPlatformRunner.baseUrl);

    process.stdout.write("\n== Services ==\n");

    profile.admin.enabled = await promptBoolean(rl, "Enable admin service", profile.admin.enabled);
    if (profile.admin.enabled) {
      profile.admin.webEnabled = await promptBoolean(rl, "Expose /admin on web", profile.admin.webEnabled);
      profile.admin.frontendPort = await promptInteger(rl, "Admin frontend port", profile.admin.frontendPort);
    } else {
      profile.admin.webEnabled = false;
    }

    profile.pan.enabled = await promptBoolean(rl, "Enable pan service", profile.pan.enabled);
    if (profile.pan.enabled) {
      profile.pan.webEnabled = await promptBoolean(rl, "Expose /pan on web", profile.pan.webEnabled);
      profile.pan.frontendPort = await promptInteger(rl, "Pan frontend port", profile.pan.frontendPort);
      if (!String(profile.pan.webSessionSecret || "").trim()) {
        profile.pan.webSessionSecret = generateSecret();
      }
    } else {
      profile.pan.webEnabled = false;
    }

    profile.term.enabled = await promptBoolean(rl, "Enable term service", profile.term.enabled);
    if (profile.term.enabled) {
      profile.term.webEnabled = await promptBoolean(rl, "Expose /term on web", profile.term.webEnabled);
      profile.term.frontendPort = await promptInteger(rl, "Term frontend port", profile.term.frontendPort);
    } else {
      profile.term.webEnabled = false;
    }

    profile.miniApp.enabled = await promptBoolean(rl, "Enable mini app service", profile.miniApp.enabled);
    if (profile.miniApp.enabled) {
      profile.miniApp.defaultAppMode = await promptText(rl, "Mini app default mode", profile.miniApp.defaultAppMode);
      profile.miniApp.publicBase = await promptText(rl, "Mini app public base", profile.miniApp.publicBase);
      profile.miniApp.port = await promptInteger(rl, "Mini app port", profile.miniApp.port);
    }

    profile.sandboxes.enabled = await promptBoolean(rl, "Enable sandboxes group", profile.sandboxes.enabled);
    profile.mcp.enabled = await promptBoolean(rl, "Enable MCP services", profile.mcp.enabled);

    fs.writeFileSync(profilePath, serializeProfileToJSONString(profile), "utf8");

    process.stdout.write("\nSaved profile:\n");
    process.stdout.write(`${profilePath}\n`);
    process.stdout.write("Password hashes were preserved as-is. Run setup-mac.sh --action configure --sync-only before start if you only want to regenerate derived files.\n");
  } finally {
    rl.close();
  }
}

main();
