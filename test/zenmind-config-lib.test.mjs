import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  applyProfile,
  applyToRelease,
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
    "agent-platform-runner",
    "agent-container-hub",
    "mcp-server-imagine",
    "mcp-server-mock"
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

function makeReleaseVersionDir(root, version = "v1.2.3") {
  const versionDir = path.join(root, "zenmind", "release", version);
  const deployDir = path.join(versionDir, "deploy");
  const envFiles = new Map([
    ["zenmind-app-server", "FRONTEND_PORT=10000\nAUTH_ISSUER=https://old.example.com\nAUTH_ADMIN_PASSWORD_BCRYPT=old-admin\nAUTH_APP_MASTER_PASSWORD_BCRYPT=old-master\n"],
    ["pan-webclient", "NGINX_PORT=10001\nWEB_SESSION_SECRET=old-secret\nAUTH_PASSWORD_HASH_BCRYPT=old-pan\n"],
    ["term-webclient", "FRONTEND_PORT=10002\nAUTH_PASSWORD_HASH_BCRYPT=old-term\nAPP_AUTH_ISSUER=https://old.example.com\n"],
    ["zenmind-gateway", "GATEWAY_PORT=10003\n"],
    ["agent-platform-runner", "HOST_PORT=10004\nAGENT_AUTH_ISSUER=https://old.example.com\n"],
    ["agent-container-hub", "BIND_ADDR=127.0.0.1:10005\nAUTH_TOKEN=old-token\n"],
    ["agent-webclient", "HOST_PORT=10006\nBASE_URL=http://host.docker.internal:9999\nVOICE_BASE_URL=http://host.docker.internal:9998\n"],
    ["agent-weixin-bridge", "HOST_PORT=10007\nRUNNER_BASE_URL=http://agent-platform-runner:8080\nRUNNER_AGENT_KEY=replace-with-runner-agent-key\n"]
  ]);

  for (const [service, content] of envFiles.entries()) {
    const serviceDir = path.join(deployDir, service);
    fs.mkdirSync(path.join(serviceDir, "configs"), { recursive: true });
    fs.writeFileSync(path.join(serviceDir, ".env.example"), content, "utf8");
  }

  return versionDir;
}

function buildConfiguredProfile() {
  const profile = getDefaultProfile();
  profile.website.domain = "demo.example.com";
  profile.images.registry = "registry.demo.local/zenmind";
  profile.images.tag = "2026.03.18";
  profile.cloudflared.tunnelUuid = "demo-tunnel";
  profile.agentPlatformRunner.enabled = true;
  profile.agentPlatformRunner.hostPort = 12949;
  profile.containerHub.enabled = true;
  profile.containerHub.port = 12960;
  profile.containerHub.authToken = "container-hub-token";
  profile.admin.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.admin.appMasterPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.pan.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.term.webPasswordBcrypt = "$2y$10$JVqLor5i8Rbmt3vVCXWFLeuodmL02vQUfIvWFOw.1uggVgWoZM0Xy";
  profile.mcp.enabled = true;
  return profile;
}

test("applyProfile writes expected outputs for mixed image and host products", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = buildConfiguredProfile();

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
  const voiceEnv = fs.readFileSync(path.join(reposRoot, "zenmind-voice-server", ".env"), "utf8");
  const runnerEnv = fs.readFileSync(path.join(reposRoot, "agent-platform-runner", ".env"), "utf8");
  const runnerContainerHubConfig = fs.readFileSync(path.join(reposRoot, "agent-platform-runner", "configs", "container-hub.yml"), "utf8");
  const containerHubEnv = fs.readFileSync(path.join(reposRoot, "agent-container-hub", ".env"), "utf8");
  const panKey = fs.readFileSync(path.join(reposRoot, "pan-webclient", "configs", "local-public-key.pem"), "utf8");
  const termEnv = fs.readFileSync(path.join(reposRoot, "term-webclient", ".env"), "utf8");
  const mockEnv = fs.readFileSync(path.join(reposRoot, "mcp-server-mock", ".env"), "utf8");

  assert.match(composeEnv, /PUBLIC_ORIGIN=https:\/\/demo\.example\.com/);
  assert.match(composeEnv, /IMAGE_REGISTRY=registry\.demo\.local\/zenmind/);
  assert.match(composeEnv, /IMAGE_TAG=2026\.03\.18/);
  assert.match(composeEnv, /CLOUDFLARED_HOSTNAME=demo\.example\.com/);
  assert.match(composeEnv, /CLOUDFLARED_TUNNEL_UUID=demo-tunnel/);
  assert.match(composeEnv, /AGENT_PLATFORM_RUNNER_HOST_PORT=12949/);
  assert.match(composeEnv, /CONTAINER_HUB_ENABLED=true/);
  assert.match(composeEnv, /CONTAINER_HUB_PORT=12960/);
  assert.match(composeEnv, /AGENT_PLATFORM_RUNNER_IMAGE=registry\.demo\.local\/zenmind\/agent-platform-runner:2026\.03\.18/);
  assert.doesNotMatch(composeEnv, /MINI_APP/);
  assert.doesNotMatch(composeEnv, /MCP_SERVER_EMAIL/);
  assert.doesNotMatch(composeEnv, /MCP_SERVER_BASH/);

  assert.match(appEnv, /AUTH_ISSUER=https:\/\/demo\.example\.com/);
  assert.match(voiceEnv, /APP_VOICE_TTS_LLM_RUNNER_BASE_URL=http:\/\/agent-platform-runner:8080/);
  assert.match(termEnv, /COPILOT_RUNNER_BASE_URL=http:\/\/agent-platform-runner:8080/);
  assert.match(runnerEnv, /HOST_PORT=12949/);
  assert.match(runnerEnv, /MODELS_DIR=\.\.\/\.zenmind\/models/);
  assert.match(runnerContainerHubConfig, /enabled: true/);
  assert.match(runnerContainerHubConfig, /base-url: http:\/\/host\.docker\.internal:12960/);
  assert.match(runnerContainerHubConfig, /auth-token: "container-hub-token"/);
  assert.match(containerHubEnv, /BIND_ADDR=127\.0\.0\.1:12960/);
  assert.match(containerHubEnv, /AUTH_TOKEN=container-hub-token/);
  assert.match(mockEnv, /MCP_BASH_ALLOWED_COMMANDS=/);

  assert.match(gatewayNginx, /location \^~ \/api\/ap\/ \{/);
  assert.match(gatewayNginx, /proxy_pass http:\/\/agent_platform_runner;/);
  assert.match(gatewayNginx, /location = \/api\/mcp\/mock \{ proxy_pass http:\/\/mcp_server_mock\/mcp; \}/);
  assert.match(gatewayNginx, /location = \/api\/mcp\/imagine \{ proxy_pass http:\/\/mcp_server_imagine\/mcp; \}/);
  assert.doesNotMatch(gatewayNginx, /\/ma\//);
  assert.doesNotMatch(gatewayNginx, /api\/mcp\/email/);
  assert.doesNotMatch(gatewayNginx, /api\/mcp\/bash/);

  assert.match(startupConfig, /gateway  # runtime=image/);
  assert.match(startupConfig, /agent-platform-runner  # runtime=image/);
  assert.match(startupConfig, /agent-container-hub  # runtime=host/);
  assert.doesNotMatch(startupConfig, /mini-app-server/);
  assert.doesNotMatch(startupConfig, /mcp-server-email/);
  assert.doesNotMatch(startupConfig, /mcp-server-bash/);

  assert.equal(fs.existsSync(path.join(reposRoot, "mcp-server-email", ".env")), false);
  assert.equal(panKey, "-----BEGIN PUBLIC KEY-----\nEXAMPLE\n-----END PUBLIC KEY-----\n");
});

test("runner and mcp disabled remove startup entries and return 404 routes", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = buildConfiguredProfile();
  profile.agentPlatformRunner.enabled = false;
  profile.containerHub.enabled = false;
  profile.mcp.enabled = false;

  applyProfile({
    profile,
    workspaceRoot,
    reposRoot,
    bcryptScriptPath: "/bin/echo"
  });

  const gatewayNginx = fs.readFileSync(path.join(workspaceRoot, "generated", "gateway", "nginx.conf"), "utf8");
  const startupConfig = fs.readFileSync(path.join(workspaceRoot, "config", "startup-services.conf"), "utf8");
  const runnerContainerHubConfig = fs.readFileSync(path.join(reposRoot, "agent-platform-runner", "configs", "container-hub.yml"), "utf8");

  assert.match(gatewayNginx, /location \^~ \/api\/ap\/ \{\n            return 404;\n        \}/);
  assert.match(gatewayNginx, /location = \/api\/mcp\/mock \{ return 404; \}/);
  assert.match(gatewayNginx, /location = \/api\/mcp\/imagine \{ return 404; \}/);
  assert.doesNotMatch(startupConfig, /agent-platform-runner/);
  assert.doesNotMatch(startupConfig, /agent-container-hub/);
  assert.doesNotMatch(startupConfig, /mcp-server-imagine/);
  assert.doesNotMatch(startupConfig, /mcp-server-mock/);
  assert.match(runnerContainerHubConfig, /enabled: false/);
  assert.match(runnerContainerHubConfig, /base-url: http:\/\/host\.docker\.internal:12960/);
  assert.equal(fs.existsSync(path.join(reposRoot, "mcp-server-imagine", ".env")), false);
  assert.equal(fs.existsSync(path.join(reposRoot, "mcp-server-mock", ".env")), false);
});

test("loadProfile migrates legacy schema to runner and container hub fields", () => {
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
    sandboxes: {
      enabled: true
    },
    agentPlatformRunner: {
      baseUrl: "http://runner.internal:12049"
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
  assert.equal(profile.agentPlatformRunner.baseUrl, "http://runner.internal:12049");
  assert.equal(profile.agentPlatformRunner.hostPort, 12049);
  assert.equal(profile.containerHub.enabled, true);
  assert.equal(profile.admin.webEnabled, false);
  assert.equal(profile.admin.frontendPort, 12050);
  assert.equal(profile.pan.webSessionSecret, "pan-secret");
  assert.equal(profile.term.enabled, false);
  assert.equal(profile.mcp.enabled, true);
  assert.equal("miniApp" in profile, false);
  assert.equal("sandboxes" in profile, false);
  assert.equal("publicOrigin" in profile.website, false);
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

test("app routes still follow service enablement without separate app switches", () => {
  const { workspaceRoot, reposRoot } = makeWorkspace();
  const profile = buildConfiguredProfile();
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

test("applyToRelease writes local issuer and enabled metadata for release bundles", () => {
  const { root, workspaceRoot } = makeWorkspace();
  const versionDir = makeReleaseVersionDir(root, "v2.0.0");
  const profile = buildConfiguredProfile();
  profile.website.domain = "website.example.com";
  profile.gateway.listenPort = 12945;
  profile.admin.frontendPort = 12950;
  profile.pan.frontendPort = 12946;
  profile.pan.webSessionSecret = "session-local";
  profile.term.frontendPort = 12947;
  profile.agentPlatformRunner.hostPort = 12949;
  profile.containerHub.port = 12960;
  profile.pan.enabled = false;
  profile.term.enabled = false;
  profile.mcp.enabled = false;
  profile.agentPlatformRunner.enabled = false;
  profile.containerHub.enabled = false;

  const result = applyToRelease({
    profile,
    workspaceRoot,
    versionDir,
    bcryptScriptPath: "/bin/echo"
  });

  const appEnv = fs.readFileSync(path.join(versionDir, "deploy", "zenmind-app-server", ".env"), "utf8");
  const panEnv = fs.readFileSync(path.join(versionDir, "deploy", "pan-webclient", ".env"), "utf8");
  const termEnv = fs.readFileSync(path.join(versionDir, "deploy", "term-webclient", ".env"), "utf8");
  const gatewayEnv = fs.readFileSync(path.join(versionDir, "deploy", "zenmind-gateway", ".env"), "utf8");
  const runnerEnv = fs.readFileSync(path.join(versionDir, "deploy", "agent-platform-runner", ".env"), "utf8");
  const runnerHubConfig = fs.readFileSync(path.join(versionDir, "deploy", "agent-platform-runner", "configs", "container-hub.yml"), "utf8");
  const hubEnv = fs.readFileSync(path.join(versionDir, "deploy", "agent-container-hub", ".env"), "utf8");
  const agentWebclientEnv = fs.readFileSync(path.join(versionDir, "deploy", "agent-webclient", ".env"), "utf8");
  const bridgeEnv = fs.readFileSync(path.join(versionDir, "deploy", "agent-weixin-bridge", ".env"), "utf8");

  assert.equal(result.meta.releaseIssuer, "http://127.0.0.1:12945");
  assert.deepEqual(result.meta.enabled, {
    admin: true,
    pan: false,
    term: false,
    mcp: false,
    runner: false,
    containerHub: false
  });
  assert.match(appEnv, /FRONTEND_PORT=12950/);
  assert.match(appEnv, /AUTH_ISSUER=http:\/\/127\.0\.0\.1:12945/);
  assert.match(appEnv, /AUTH_ADMIN_PASSWORD_BCRYPT='\$2y\$10/);
  assert.match(appEnv, /AUTH_APP_MASTER_PASSWORD_BCRYPT='\$2y\$10/);
  assert.match(panEnv, /NGINX_PORT=12946/);
  assert.match(panEnv, /WEB_SESSION_SECRET=session-local/);
  assert.match(termEnv, /FRONTEND_PORT=12947/);
  assert.match(termEnv, /APP_AUTH_ISSUER=http:\/\/127\.0\.0\.1:12945/);
  assert.match(gatewayEnv, /GATEWAY_PORT=12945/);
  assert.match(runnerEnv, /HOST_PORT=12949/);
  assert.match(runnerEnv, /AGENT_AUTH_ISSUER=http:\/\/127\.0\.0\.1:12945/);
  assert.match(runnerHubConfig, /enabled: false/);
  assert.match(runnerHubConfig, /base-url: http:\/\/host\.docker\.internal:12960/);
  assert.match(hubEnv, /BIND_ADDR=127\.0\.0\.1:12960/);
  assert.match(hubEnv, /AUTH_TOKEN=container-hub-token/);
  assert.match(agentWebclientEnv, /BASE_URL=http:\/\/host\.docker\.internal:12949/);
  assert.match(agentWebclientEnv, /VOICE_BASE_URL=http:\/\/host\.docker\.internal:11953/);
  assert.match(bridgeEnv, /RUNNER_BASE_URL=http:\/\/agent-platform-runner:8080/);
  assert.match(bridgeEnv, /RUNNER_AGENT_KEY=replace-with-runner-agent-key/);
});

test("applyToRelease uses https issuer for real domains", () => {
  const { root, workspaceRoot } = makeWorkspace();
  const versionDir = makeReleaseVersionDir(root, "v2.1.0");
  const profile = buildConfiguredProfile();
  profile.website.domain = "app.zenmind.cc";

  applyToRelease({
    profile,
    workspaceRoot,
    versionDir,
    bcryptScriptPath: "/bin/echo"
  });

  const appEnv = fs.readFileSync(path.join(versionDir, "deploy", "zenmind-app-server", ".env"), "utf8");
  const termEnv = fs.readFileSync(path.join(versionDir, "deploy", "term-webclient", ".env"), "utf8");
  const runnerEnv = fs.readFileSync(path.join(versionDir, "deploy", "agent-platform-runner", ".env"), "utf8");

  assert.match(appEnv, /AUTH_ISSUER=https:\/\/app\.zenmind\.cc/);
  assert.match(termEnv, /APP_AUTH_ISSUER=https:\/\/app\.zenmind\.cc/);
  assert.match(runnerEnv, /AGENT_AUTH_ISSUER=https:\/\/app\.zenmind\.cc/);
});

test("applyToRelease keeps existing bridge env values", () => {
  const { root, workspaceRoot } = makeWorkspace();
  const versionDir = makeReleaseVersionDir(root, "v2.2.0");
  const profile = buildConfiguredProfile();
  const bridgeEnvPath = path.join(versionDir, "deploy", "agent-weixin-bridge", ".env");

  fs.writeFileSync(bridgeEnvPath, [
    "HOST_PORT=12958",
    "RUNNER_BASE_URL=http://legacy-runner.internal:18080",
    "RUNNER_AGENT_KEY=wechat-assistant",
    ""
  ].join("\n"));

  applyToRelease({
    profile,
    workspaceRoot,
    versionDir,
    bcryptScriptPath: "/bin/echo"
  });

  const bridgeEnv = fs.readFileSync(bridgeEnvPath, "utf8");
  assert.match(bridgeEnv, /RUNNER_BASE_URL=http:\/\/legacy-runner\.internal:18080/);
  assert.match(bridgeEnv, /RUNNER_AGENT_KEY=wechat-assistant/);
});
