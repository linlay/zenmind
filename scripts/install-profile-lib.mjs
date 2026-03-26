#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

import { getDefaultProfile } from "./zenmind-config-lib.mjs";

export const INSTALL_PROFILE_SCHEMA_VERSION = 1;

const DEFAULT_INSTALL_PROFILE = {
  schemaVersion: INSTALL_PROFILE_SCHEMA_VERSION,
  siteName: "",
  adminUsername: "admin",
  adminPassword: "",
  primaryProvider: "",
  primaryModel: "",
  primaryApiKey: ""
};

function trimString(value, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function generateSecret() {
  return crypto.randomBytes(24).toString("hex");
}

function generatePasswordHash(password, bcryptScriptPath) {
  return execFileSync(bcryptScriptPath, [password], {
    encoding: "utf8"
  }).trim();
}

export function getInstallProfilePath(workspaceRoot) {
  return path.join(path.resolve(workspaceRoot, ".."), ".zenmind", "install-profile.json");
}

export function normalizeInstallProfile(rawProfile) {
  return {
    schemaVersion: Number.isInteger(rawProfile?.schemaVersion)
      ? rawProfile.schemaVersion
      : INSTALL_PROFILE_SCHEMA_VERSION,
    siteName: trimString(rawProfile?.siteName || rawProfile?.website?.domain || ""),
    adminUsername: trimString(rawProfile?.adminUsername || "admin") || "admin",
    adminPassword: trimString(rawProfile?.adminPassword || ""),
    primaryProvider: trimString(rawProfile?.primaryProvider || rawProfile?.primaryProviderKey || ""),
    primaryModel: trimString(rawProfile?.primaryModel || rawProfile?.primaryModelKey || ""),
    primaryApiKey: trimString(rawProfile?.primaryApiKey || "")
  };
}

export function validateInstallProfile(profile) {
  const normalized = normalizeInstallProfile(profile);
  assert(normalized.siteName, "siteName is required");
  assert(normalized.adminUsername, "adminUsername is required");
  assert(normalized.adminPassword, "adminPassword is required");
  assert(normalized.primaryProvider, "primaryProvider is required");
  assert(normalized.primaryModel, "primaryModel is required");
  assert(normalized.primaryApiKey, "primaryApiKey is required");
  return normalized;
}

export function loadInstallProfile(filePath) {
  return validateInstallProfile(JSON.parse(fs.readFileSync(filePath, "utf8")));
}

export function writeInstallProfile(workspaceRoot, profile, overridePath = "") {
  const targetPath = overridePath ? path.resolve(overridePath) : getInstallProfilePath(workspaceRoot);
  const normalized = validateInstallProfile(profile);
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, `${JSON.stringify(normalized, null, 2)}\n`, "utf8");
  return targetPath;
}

export function mergeInstallProfileIntoProfile(profile, installProfile, bcryptScriptPath) {
  const merged = clone(profile || getDefaultProfile());
  const normalized = validateInstallProfile(installProfile);
  const passwordHash = generatePasswordHash(normalized.adminPassword, bcryptScriptPath);

  merged.website = merged.website || {};
  merged.admin = merged.admin || {};
  merged.pan = merged.pan || {};
  merged.term = merged.term || {};
  merged.containerHub = merged.containerHub || {};
  merged.agentPlatformRunner = merged.agentPlatformRunner || {};
  merged.mcp = merged.mcp || {};
  merged.llm = merged.llm || {};

  merged.website.domain = normalized.siteName;
  merged.admin.enabled = true;
  merged.admin.webEnabled = true;
  merged.admin.adminUsername = normalized.adminUsername;
  merged.admin.webPasswordBcrypt = passwordHash;
  merged.admin.appMasterPasswordBcrypt = passwordHash;

  merged.pan.enabled = true;
  merged.pan.webEnabled = true;
  merged.pan.adminUsername = normalized.adminUsername;
  merged.pan.webPasswordBcrypt = passwordHash;
  merged.pan.webSessionSecret = trimString(merged.pan.webSessionSecret || "") || generateSecret();

  merged.term.enabled = true;
  merged.term.webEnabled = true;
  merged.term.authUsername = normalized.adminUsername;
  merged.term.webPasswordBcrypt = passwordHash;

  merged.agentPlatformRunner.enabled = true;
  merged.containerHub.enabled = true;
  merged.containerHub.authToken = trimString(merged.containerHub.authToken || "") || generateSecret();
  merged.mcp.enabled = true;
  merged.llm.primaryProviderKey = normalized.primaryProvider;
  merged.llm.primaryModelKey = normalized.primaryModel;
  merged.llm.primaryApiKey = normalized.primaryApiKey;

  return merged;
}
