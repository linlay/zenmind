import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  applyProfile,
  getDefaultProfile,
  loadProfile
} from "../scripts/zenmind-config-lib.mjs";

function makeWorkspace() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "zenmind-config-test-"));
  const workspaceRoot = path.join(root, "zenmind");
  const reposRoot = root;
  fs.mkdirSync(workspaceRoot, { recursive: true });
  for (const repo of [
    "zenmind-app-server",
    "zenmind-voice-server",
    "pan-webclient",
    "term-webclient",
    "mini-app-server",
    "mcp-server-imagine",
    "mcp-server-bash",
    "mcp-server-mock",
    "mcp-server-email"
  ]) {
    fs.mkdirSync(path.join(reposRoot, repo, "configs"), { recursive: true });
  }
  fs.mkdirSync(path.join(workspaceRoot, "generated", "gateway"), { recursive: true });
  fs.mkdirSync(path.join(workspaceRoot, "config"), { recursive: true });
  fs.writeFileSync(
    path.join(reposRoot, "pan-webclient", "configs", "local-public-key.example.pem"),
    "-----BEGIN PUBLIC KEY-----\nEXAMPLE\n-----END PUBLIC KEY-----\n",
    "utf8"
  );
  return { root, workspaceRoot, reposRoot };
}

test("applyProfile writes expected outputs for v2 profile", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = getDefaultProfile();
  profile.website.domain = "demo.example.com";
  profile.images.registry = "registry.demo.local/zenmind";
  profile.images.tag = "2026.03.18";
  profile.cloudflared.tunnelUuid = "demo-tunnel";
  profile.admin.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.admin.appMasterPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.term.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.mcp.enabled = true;

  applyProfile({
    profile,
    workspaceRoot,
    reposRoot,
    bcryptScriptPath: "/bin/echo"
  });

  const composeEnv = fs.readFileSync(path.join(workspaceRoot, "generated", "docker-compose.env"), "utf8");
  const gatewayNginx = fs.readFileSync(path.join(workspaceRoot, "generated", "gateway", "nginx.conf"), "utf8");
  const startupConfig = fs.readFileSync(path.join(workspaceRoot, "config", "startup-services.conf"), "utf8");
  const appEnv = fs.readFileSync(path.join(reposRoot, "zenmind-app-server", ".env"), "utf8");
  const panKey = fs.readFileSync(path.join(reposRoot, "pan-webclient", "configs", "local-public-key.pem"), "utf8");
  const termEnv = fs.readFileSync(path.join(reposRoot, "term-webclient", ".env"), "utf8");
  const mcpEnv = fs.readFileSync(path.join(reposRoot, "mcp-server-email", ".env"), "utf8");

  assert.match(composeEnv, /PUBLIC_ORIGIN=https:\/\/demo\.example\.com/);
  assert.match(composeEnv, /IMAGE_REGISTRY=registry\.demo\.local\/zenmind/);
  assert.match(composeEnv, /IMAGE_TAG=2026\.03\.18/);
  assert.match(composeEnv, /CLOUDFLARED_HOSTNAME=demo\.example\.com/);
  assert.match(composeEnv, /CLOUDFLARED_TUNNEL_UUID=demo-tunnel/);
  assert.match(composeEnv, /ZENMIND_APP_SERVER_BACKEND_IMAGE=registry\.demo\.local\/zenmind\/zenmind-app-server-backend:2026\.03\.18/);
  assert.match(composeEnv, /TERM_WEBCLIENT_FRONTEND_IMAGE=registry\.demo\.local\/zenmind\/term-webclient-frontend:2026\.03\.18/);
  assert.match(appEnv, /AUTH_ISSUER=https:\/\/demo\.example\.com/);
  assert.match(termEnv, /APP_AUTH_ISSUER=https:\/\/demo\.example\.com/);
  assert.match(gatewayNginx, /location \^~ \/apppan\/ \{ proxy_pass http:\/\/pan_webclient_frontend; \}/);
  assert.match(gatewayNginx, /location \^~ \/appterm\/ \{ proxy_pass http:\/\/term_webclient_frontend; \}/);
  assert.match(gatewayNginx, /location = \/api\/mcp\/imagine \{ proxy_pass http:\/\/mcp_server_imagine\/mcp; \}/);
  assert.match(startupConfig, /zenmind-voice-server/);
  assert.match(startupConfig, /mcp-server-email/);
  assert.match(mcpEnv, /MAIL_ACCOUNTS_CONFIG_PATH=\.\/configs/);
  assert.equal(panKey, "-----BEGIN PUBLIC KEY-----\nEXAMPLE\n-----END PUBLIC KEY-----\n");
});

test("mcp disabled removes MCP startup and routes", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = getDefaultProfile();
  profile.admin.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.admin.appMasterPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.term.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.mcp.enabled = false;

  applyProfile({
    profile,
    workspaceRoot,
    reposRoot,
    bcryptScriptPath: "/bin/echo"
  });

  const gatewayNginx = fs.readFileSync(path.join(workspaceRoot, "generated", "gateway", "nginx.conf"), "utf8");
  const startupConfig = fs.readFileSync(path.join(workspaceRoot, "config", "startup-services.conf"), "utf8");

  assert.match(gatewayNginx, /location = \/api\/mcp\/imagine \{ return 404; \}/);
  assert.doesNotMatch(startupConfig, /mcp-server-imagine/);
  assert.equal(fs.existsSync(path.join(reposRoot, "mcp-server-email", ".env")), false);
});

test("loadProfile migrates v1 schema to v2", () => {
  const { workspaceRoot } = makeWorkspace();
  const legacyProfilePath = path.join(workspaceRoot, "config", "legacy.json");
  fs.writeFileSync(legacyProfilePath, JSON.stringify({
    profileVersion: 1,
    website: {
      publicOrigin: "https://legacy.example.com"
    },
    cloudflared: {
      tunnelUuid: "legacy-tunnel"
    },
    gateway: {
      listenPort: 12000
    },
    access: {
      adminPublicEnabled: false,
      panWebEnabled: true,
      panAppEnabled: false,
      termWebEnabled: true,
      termAppEnabled: false
    },
    agentPlatformRunner: {
      baseUrl: "http://runner.internal:11949"
    },
    services: {
      zenmindAppServer: {
        enabled: true,
        frontendPort: 12050,
        adminPassword: { plain: "admin" },
        appMasterPassword: { plain: "master" }
      },
      panWebclient: {
        enabled: true,
        frontendPort: 12046,
        webPassword: { plain: "pan" },
        webSessionSecret: "pan-secret"
      },
      termWebclient: {
        enabled: false,
        frontendPort: 12047,
        webPassword: { plain: "term" }
      },
      miniAppServer: {
        enabled: true,
        defaultAppMode: "prod",
        publicBase: "/mini",
        port: 12048
      },
      mcpServerImagine: {
        enabled: true
      }
    }
  }, null, 2));

  const profile = loadProfile(legacyProfilePath);

  assert.equal(profile.profileVersion, 2);
  assert.equal(profile.website.domain, "legacy.example.com");
  assert.equal(profile.images.registry, "registry.example.com/zenmind");
  assert.equal(profile.images.tag, "latest");
  assert.equal(profile.cloudflared.tunnelUuid, "legacy-tunnel");
  assert.equal(profile.gateway.listenPort, 12000);
  assert.equal(profile.agentPlatformRunner.baseUrl, "http://runner.internal:11949");
  assert.equal(profile.admin.webEnabled, false);
  assert.equal(profile.admin.frontendPort, 12050);
  assert.equal(profile.pan.webSessionSecret, "pan-secret");
  assert.equal(profile.term.enabled, false);
  assert.equal(profile.miniApp.publicBase, "/mini");
  assert.equal(profile.mcp.enabled, true);
  assert.equal("publicOrigin" in profile.website, false);
  assert.equal("publicEnabled" in profile.admin, false);
  assert.equal("appEnabled" in profile.pan, false);
  assert.equal("appEnabled" in profile.term, false);
});

test("legacy plaintext secrets still flow into env generation", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const legacyProfilePath = path.join(workspaceRoot, "config", "legacy-plain.json");
  fs.writeFileSync(legacyProfilePath, JSON.stringify({
    profileVersion: 1,
    website: {
      publicOrigin: "https://legacy-secret.example.com"
    },
    services: {
      zenmindAppServer: {
        enabled: true,
        adminPassword: { plain: "admin-plain" },
        appMasterPassword: { plain: "master-plain" }
      },
      panWebclient: {
        enabled: true,
        webPassword: { plain: "pan-plain" }
      },
      termWebclient: {
        enabled: true,
        webPassword: { plain: "term-plain" }
      }
    }
  }, null, 2));

  const profile = loadProfile(legacyProfilePath);
  applyProfile({
    profile,
    workspaceRoot,
    reposRoot,
    bcryptScriptPath: "/bin/echo"
  });

  const appEnv = fs.readFileSync(path.join(reposRoot, "zenmind-app-server", ".env"), "utf8");
  const panEnv = fs.readFileSync(path.join(reposRoot, "pan-webclient", ".env"), "utf8");
  const termEnv = fs.readFileSync(path.join(reposRoot, "term-webclient", ".env"), "utf8");

  assert.match(appEnv, /AUTH_ADMIN_PASSWORD_BCRYPT=admin-plain/);
  assert.match(appEnv, /AUTH_APP_MASTER_PASSWORD_BCRYPT=master-plain/);
  assert.match(panEnv, /AUTH_PASSWORD_HASH_BCRYPT=pan-plain/);
  assert.match(termEnv, /AUTH_PASSWORD_HASH_BCRYPT=term-plain/);
});

test("app routes follow service enablement instead of a separate app switch", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = getDefaultProfile();
  profile.admin.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.admin.appMasterPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.term.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webEnabled = false;
  profile.term.webEnabled = false;

  applyProfile({
    profile,
    workspaceRoot,
    reposRoot,
    bcryptScriptPath: "/bin/echo"
  });

  const gatewayNginx = fs.readFileSync(path.join(workspaceRoot, "generated", "gateway", "nginx.conf"), "utf8");

  assert.match(gatewayNginx, /location = \/pan \{ return 404; \}/);
  assert.match(gatewayNginx, /location \^~ \/pan\/ \{ return 404; \}/);
  assert.match(gatewayNginx, /location = \/apppan \{ return 301 \/apppan\/; \}/);
  assert.match(gatewayNginx, /location \^~ \/apppan\/ \{ proxy_pass http:\/\/pan_webclient_frontend; \}/);
  assert.match(gatewayNginx, /location = \/term \{ return 404; \}/);
  assert.match(gatewayNginx, /location \^~ \/term\/ \{ return 404; \}/);
  assert.match(gatewayNginx, /location = \/appterm \{ return 301 \/appterm\/; \}/);
  assert.match(gatewayNginx, /location \^~ \/appterm\/ \{ proxy_pass http:\/\/term_webclient_frontend; \}/);
});
