#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

import {
  getDefaultProfile,
  getProfileLocations,
  serializeProfileToJSONString
} from "./zenmind-config-lib.mjs";

function parseArgs(argv) {
  const args = {
    workspaceRoot: process.cwd(),
    profilePath: "",
    credentialsFile: path.join(process.env.HOME || process.cwd(), ".zenmind-credentials.txt")
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
      case "--credentials-file":
        args.credentialsFile = path.resolve(argv[index + 1]);
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  return args;
}

function randomSecret(bytes = 18) {
  return crypto.randomBytes(bytes).toString("base64url");
}

function bcryptFor(plainValue, bcryptScriptPath) {
  return execFileSync(bcryptScriptPath, [plainValue], { encoding: "utf8" }).trim();
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const locations = getProfileLocations(args.workspaceRoot);
  const profilePath = args.profilePath || locations.profileLocalPath;
  const credentialsFile = args.credentialsFile;

  const adminWebPassword = randomSecret();
  const adminAppMasterPassword = randomSecret();
  const panWebPassword = randomSecret();
  const termWebPassword = randomSecret();
  const panSessionSecret = randomSecret(24);

  const profile = getDefaultProfile();
  profile.admin.webPasswordBcrypt = bcryptFor(adminWebPassword, locations.bcryptScriptPath);
  profile.admin.appMasterPasswordBcrypt = bcryptFor(adminAppMasterPassword, locations.bcryptScriptPath);
  profile.pan.webPasswordBcrypt = bcryptFor(panWebPassword, locations.bcryptScriptPath);
  profile.pan.webSessionSecret = panSessionSecret;
  profile.term.webPasswordBcrypt = bcryptFor(termWebPassword, locations.bcryptScriptPath);

  ensureParent(profilePath);
  fs.writeFileSync(profilePath, serializeProfileToJSONString(profile), "utf8");

  ensureParent(credentialsFile);
  fs.writeFileSync(credentialsFile, [
    "ZenMind generated credentials",
    `admin_web_password=${adminWebPassword}`,
    `admin_app_master_password=${adminAppMasterPassword}`,
    `pan_web_password=${panWebPassword}`,
    `term_web_password=${termWebPassword}`,
    `pan_session_secret=${panSessionSecret}`,
    `profile_path=${profilePath}`
  ].join("\n") + "\n", { encoding: "utf8", mode: 0o600 });
  fs.chmodSync(credentialsFile, 0o600);

  process.stdout.write(`Generated profile: ${profilePath}\n`);
  process.stdout.write(`Credentials file: ${credentialsFile}\n`);
}

main();
