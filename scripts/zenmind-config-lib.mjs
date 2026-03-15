import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const MANAGED_PRODUCTS = [
  "gateway",
  "zenmind-app-server",
  "zenmind-voice-server",
  "pan-webclient",
  "term-webclient",
  "mini-app-server",
  "mcp-server-imagine",
  "mcp-server-bash",
  "mcp-server-mock",
  "mcp-server-email"
];

export const SERVICE_EXPANSIONS = {
  gateway: ["gateway"],
  "zenmind-app-server": ["zenmind-app-server-backend", "zenmind-app-server-frontend"],
  "zenmind-voice-server": ["zenmind-voice-server"],
  "pan-webclient": ["pan-webclient-api", "pan-webclient-frontend"],
  "term-webclient": ["term-webclient-backend", "term-webclient-frontend"],
  "mini-app-server": ["mini-app-server"],
  "mcp-server-imagine": ["mcp-server-imagine"],
  "mcp-server-bash": ["mcp-server-bash"],
  "mcp-server-mock": ["mcp-server-mock"],
  "mcp-server-email": ["mcp-server-email"]
};

const DEFAULT_PROFILE = {
  profileVersion: 2,
  website: {
    domain: "website.example.com"
  },
  cloudflared: {
    tunnelUuid: "replace-with-your-tunnel-uuid"
  },
  gateway: {
    listenPort: 11945
  },
  agentPlatformRunner: {
    baseUrl: "http://host.docker.internal:11949"
  },
  admin: {
    enabled: true,
    publicEnabled: true,
    frontendPort: 11950,
    adminPassword: { plain: "", bcrypt: "" },
    appMasterPassword: { plain: "", bcrypt: "" }
  },
  pan: {
    enabled: true,
    webEnabled: true,
    appEnabled: true,
    frontendPort: 11946,
    webPassword: { plain: "", bcrypt: "" },
    webSessionSecret: ""
  },
  term: {
    enabled: true,
    webEnabled: true,
    appEnabled: true,
    frontendPort: 11947,
    webPassword: { plain: "", bcrypt: "" }
  },
  miniApp: {
    enabled: true,
    defaultAppMode: "dev",
    publicBase: "/ma",
    port: 11948
  },
  sandboxes: {
    enabled: false
  },
  mcp: {
    enabled: true
  }
};

const INTERNAL_DEFAULTS = {
  profileVersion: 1,
  website: {
    domain: "website.example.com",
    publicOrigin: "https://website.example.com"
  },
  gateway: {
    listenIp: "127.0.0.1",
    listenPort: 11945
  },
  cloudflared: {
    hostname: "website.example.com",
    tunnelUuid: "",
    credentialsFile: "~/.cloudflared/replace-with-your-tunnel-uuid.json",
    configFile: "~/.cloudflared/config.yml"
  },
  access: {
    adminPublicEnabled: true,
    panWebEnabled: true,
    panAppEnabled: true,
    termWebEnabled: true,
    termAppEnabled: true
  },
  agentPlatformRunner: {
    baseUrl: "http://host.docker.internal:11949"
  },
  services: {
    zenmindAppServer: {
      enabled: true,
      frontendPort: 11950,
      issuer: "https://website.example.com",
      adminUsername: "admin",
      appUsername: "app",
      viteBasePath: "/admin/",
      adminPassword: { plain: "", bcrypt: "" },
      appMasterPassword: { plain: "", bcrypt: "" }
    },
    voiceServer: {
      enabled: true,
      port: 11953,
      dashscopeApiKey: "",
      dashscopeTtsApiKey: "",
      runnerBaseUrl: "http://host.docker.internal:11949",
      runnerAgentKey: "",
      runnerAuthorizationToken: ""
    },
    panWebclient: {
      enabled: true,
      frontendPort: 11946,
      adminUsername: "admin",
      webSessionSecret: "",
      webPassword: { plain: "", bcrypt: "" },
      jwtPublicKeyPem: "",
      dataDir: "./data",
      maxUploadBytes: 104857600,
      maxEditFileBytes: 1048576,
      mounts: []
    },
    termWebclient: {
      enabled: true,
      frontendPort: 11947,
      authEnabled: true,
      authUsername: "admin",
      webPassword: { plain: "", bcrypt: "" },
      appAuthEnabled: true,
      jwtPublicKeyPem: "",
      appAuthIssuer: "https://website.example.com",
      appAuthAudience: "appterm",
      appAuthJwksUri: "",
      copilotRunnerBaseUrl: "http://host.docker.internal:11949",
      copilotRunnerAuthorizationBearer: "",
      terminalFilesEnabled: true,
      terminalSshMasterKey: "",
      agentsYaml: "",
      assistYaml: "",
      assistApiKey: "",
      mounts: []
    },
    miniAppServer: {
      enabled: true,
      port: 11948,
      defaultAppMode: "dev",
      platformBase: "/__platform",
      publicBase: "/ma",
      host: "0.0.0.0"
    },
    mcpServerImagine: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11962,
      serverPort: 8080,
      runnerDataRoot: "../mcp-server-imagine/data",
      providerConfigs: []
    },
    mcpServerBash: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11963,
      serverPort: 8080,
      workingDirectory: ".",
      allowedPaths: ".,/tmp",
      allowedCommands: "ls,pwd,cat,head,tail,top,free,df,git,rg,find"
    },
    mcpServerMock: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11969,
      serverPort: 8080
    },
    mcpServerEmail: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11967,
      serverPort: 8080,
      accounts: []
    }
  }
};

const FIXED_STARTUP_PRODUCTS = [...MANAGED_PRODUCTS];

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function deepMerge(base, override) {
  if (Array.isArray(base)) {
    return Array.isArray(override) ? clone(override) : clone(base);
  }
  if (!base || typeof base !== "object") {
    return override === undefined ? base : override;
  }
  const result = {};
  const keys = new Set([...Object.keys(base), ...Object.keys(override || {})]);
  for (const key of keys) {
    const baseValue = base[key];
    const overrideValue = override?.[key];
    if (overrideValue === undefined) {
      result[key] = clone(baseValue);
      continue;
    }
    if (baseValue && typeof baseValue === "object" && !Array.isArray(baseValue) && overrideValue && typeof overrideValue === "object" && !Array.isArray(overrideValue)) {
      result[key] = deepMerge(baseValue, overrideValue);
      continue;
    }
    if (Array.isArray(baseValue)) {
      result[key] = Array.isArray(overrideValue) ? clone(overrideValue) : clone(baseValue);
      continue;
    }
    result[key] = clone(overrideValue);
  }
  return result;
}

function stripProtocol(value) {
  return String(value || "")
    .trim()
    .replace(/^https?:\/\//i, "")
    .replace(/\/.*$/, "")
    .replace(/^\.+|\.+$/g, "");
}

function normalizeDomain(value) {
  return stripProtocol(value).toLowerCase();
}

function deriveOrigin(domain) {
  return `https://${domain}`;
}

function normalizeSecret(secret) {
  if (secret && typeof secret === "object") {
    return {
      plain: String(secret.plain || ""),
      bcrypt: String(secret.bcrypt || "")
    };
  }
  if (typeof secret === "string") {
    return { plain: secret, bcrypt: "" };
  }
  return { plain: "", bcrypt: "" };
}

function normalizePathValue(value) {
  if (typeof value !== "string") {
    return "";
  }
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return value;
}

function parseJSONFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensurePort(value, label) {
  assert(Number.isInteger(value) && value >= 1 && value <= 65535, `${label} must be an integer in range 1-65535`);
}

function normalizeProfile(rawProfile) {
  if (rawProfile?.profileVersion === 2) {
    const merged = deepMerge(DEFAULT_PROFILE, rawProfile);
    merged.profileVersion = 2;
    merged.website.domain = normalizeDomain(merged.website.domain);
    merged.admin.adminPassword = normalizeSecret(merged.admin.adminPassword);
    merged.admin.appMasterPassword = normalizeSecret(merged.admin.appMasterPassword);
    merged.pan.webPassword = normalizeSecret(merged.pan.webPassword);
    merged.term.webPassword = normalizeSecret(merged.term.webPassword);
    return merged;
  }

  const websiteDomain = normalizeDomain(
    rawProfile?.website?.domain || rawProfile?.website?.publicOrigin || rawProfile?.cloudflared?.hostname || DEFAULT_PROFILE.website.domain
  );
  const legacyMcpEnabled = [
    rawProfile?.services?.mcpServerImagine?.enabled,
    rawProfile?.services?.mcpServerBash?.enabled,
    rawProfile?.services?.mcpServerMock?.enabled,
    rawProfile?.services?.mcpServerEmail?.enabled
  ].some((value) => value === true);

  return {
    profileVersion: 2,
    website: {
      domain: websiteDomain || DEFAULT_PROFILE.website.domain
    },
    cloudflared: {
      tunnelUuid: String(rawProfile?.cloudflared?.tunnelUuid || DEFAULT_PROFILE.cloudflared.tunnelUuid)
    },
    gateway: {
      listenPort: rawProfile?.gateway?.listenPort ?? DEFAULT_PROFILE.gateway.listenPort
    },
    agentPlatformRunner: {
      baseUrl: String(rawProfile?.agentPlatformRunner?.baseUrl || rawProfile?.services?.voiceServer?.runnerBaseUrl || DEFAULT_PROFILE.agentPlatformRunner.baseUrl)
    },
    admin: {
      enabled: Boolean(rawProfile?.services?.zenmindAppServer?.enabled ?? DEFAULT_PROFILE.admin.enabled),
      publicEnabled: Boolean(rawProfile?.access?.adminPublicEnabled ?? DEFAULT_PROFILE.admin.publicEnabled),
      frontendPort: rawProfile?.services?.zenmindAppServer?.frontendPort ?? DEFAULT_PROFILE.admin.frontendPort,
      adminPassword: normalizeSecret(rawProfile?.services?.zenmindAppServer?.adminPassword),
      appMasterPassword: normalizeSecret(rawProfile?.services?.zenmindAppServer?.appMasterPassword)
    },
    pan: {
      enabled: Boolean(rawProfile?.services?.panWebclient?.enabled ?? DEFAULT_PROFILE.pan.enabled),
      webEnabled: Boolean(rawProfile?.access?.panWebEnabled ?? DEFAULT_PROFILE.pan.webEnabled),
      appEnabled: Boolean(rawProfile?.access?.panAppEnabled ?? DEFAULT_PROFILE.pan.appEnabled),
      frontendPort: rawProfile?.services?.panWebclient?.frontendPort ?? DEFAULT_PROFILE.pan.frontendPort,
      webPassword: normalizeSecret(rawProfile?.services?.panWebclient?.webPassword),
      webSessionSecret: String(rawProfile?.services?.panWebclient?.webSessionSecret || "")
    },
    term: {
      enabled: Boolean(rawProfile?.services?.termWebclient?.enabled ?? DEFAULT_PROFILE.term.enabled),
      webEnabled: Boolean(rawProfile?.access?.termWebEnabled ?? DEFAULT_PROFILE.term.webEnabled),
      appEnabled: Boolean(rawProfile?.access?.termAppEnabled ?? DEFAULT_PROFILE.term.appEnabled),
      frontendPort: rawProfile?.services?.termWebclient?.frontendPort ?? DEFAULT_PROFILE.term.frontendPort,
      webPassword: normalizeSecret(rawProfile?.services?.termWebclient?.webPassword)
    },
    miniApp: {
      enabled: Boolean(rawProfile?.services?.miniAppServer?.enabled ?? DEFAULT_PROFILE.miniApp.enabled),
      defaultAppMode: String(rawProfile?.services?.miniAppServer?.defaultAppMode || DEFAULT_PROFILE.miniApp.defaultAppMode),
      publicBase: String(rawProfile?.services?.miniAppServer?.publicBase || DEFAULT_PROFILE.miniApp.publicBase),
      port: rawProfile?.services?.miniAppServer?.port ?? DEFAULT_PROFILE.miniApp.port
    },
    sandboxes: {
      enabled: Boolean(rawProfile?.sandboxes?.enabled ?? DEFAULT_PROFILE.sandboxes.enabled)
    },
    mcp: {
      enabled: legacyMcpEnabled || rawProfile?.mcp?.enabled === true || (
        rawProfile?.services?.mcpServerImagine === undefined &&
        rawProfile?.services?.mcpServerBash === undefined &&
        rawProfile?.services?.mcpServerMock === undefined &&
        rawProfile?.services?.mcpServerEmail === undefined &&
        DEFAULT_PROFILE.mcp.enabled
      )
    }
  };
}

function serializeProfile(profile) {
  const normalized = normalizeProfile(profile);
  return {
    profileVersion: 2,
    website: {
      domain: normalized.website.domain
    },
    cloudflared: {
      tunnelUuid: normalized.cloudflared.tunnelUuid
    },
    gateway: {
      listenPort: normalized.gateway.listenPort
    },
    agentPlatformRunner: {
      baseUrl: normalized.agentPlatformRunner.baseUrl
    },
    admin: {
      enabled: normalized.admin.enabled,
      publicEnabled: normalized.admin.publicEnabled,
      frontendPort: normalized.admin.frontendPort,
      adminPassword: normalizeSecret(normalized.admin.adminPassword),
      appMasterPassword: normalizeSecret(normalized.admin.appMasterPassword)
    },
    pan: {
      enabled: normalized.pan.enabled,
      webEnabled: normalized.pan.webEnabled,
      appEnabled: normalized.pan.appEnabled,
      frontendPort: normalized.pan.frontendPort,
      webPassword: normalizeSecret(normalized.pan.webPassword),
      webSessionSecret: normalized.pan.webSessionSecret
    },
    term: {
      enabled: normalized.term.enabled,
      webEnabled: normalized.term.webEnabled,
      appEnabled: normalized.term.appEnabled,
      frontendPort: normalized.term.frontendPort,
      webPassword: normalizeSecret(normalized.term.webPassword)
    },
    miniApp: {
      enabled: normalized.miniApp.enabled,
      defaultAppMode: normalized.miniApp.defaultAppMode,
      publicBase: normalized.miniApp.publicBase,
      port: normalized.miniApp.port
    },
    sandboxes: {
      enabled: normalized.sandboxes.enabled
    },
    mcp: {
      enabled: normalized.mcp.enabled
    }
  };
}

function readFirstExistingFile(candidatePaths) {
  for (const candidatePath of candidatePaths) {
    if (!candidatePath || !fs.existsSync(candidatePath)) {
      continue;
    }
    const content = fs.readFileSync(candidatePath, "utf8").trim();
    if (content) {
      return `${content.replace(/\r\n/g, "\n").replace(/\r/g, "\n")}\n`;
    }
  }
  return "";
}

function resolveManagedPublicKeyPem(reposRoot) {
  return readFirstExistingFile([
    repoPath(reposRoot, "zenmind-app-server", "data", "keys", "jwk-public.pem"),
    repoPath(reposRoot, "zenmind-app-server", "release", "data", "keys", "jwk-public.pem"),
    repoPath(reposRoot, "pan-webclient", "configs", "local-public-key.pem"),
    repoPath(reposRoot, "term-webclient", "configs", "local-public-key.pem"),
    repoPath(reposRoot, "pan-webclient", "configs", "local-public-key.example.pem"),
    repoPath(reposRoot, "term-webclient", "configs", "local-public-key.example.pem")
  ]);
}

function expandProfile(profile, reposRoot) {
  const normalized = normalizeProfile(profile);
  const detailed = deepMerge(INTERNAL_DEFAULTS, {});
  const websiteOrigin = deriveOrigin(normalized.website.domain);
  const managedPublicKey = resolveManagedPublicKeyPem(reposRoot);

  detailed.website.domain = normalized.website.domain;
  detailed.website.publicOrigin = websiteOrigin;
  detailed.gateway.listenPort = normalized.gateway.listenPort;
  detailed.cloudflared.hostname = normalized.website.domain;
  detailed.cloudflared.tunnelUuid = normalized.cloudflared.tunnelUuid;
  detailed.agentPlatformRunner.baseUrl = normalized.agentPlatformRunner.baseUrl;

  detailed.access.adminPublicEnabled = normalized.admin.enabled ? normalized.admin.publicEnabled : false;
  detailed.access.panWebEnabled = normalized.pan.enabled ? normalized.pan.webEnabled : false;
  detailed.access.panAppEnabled = normalized.pan.enabled ? normalized.pan.appEnabled : false;
  detailed.access.termWebEnabled = normalized.term.enabled ? normalized.term.webEnabled : false;
  detailed.access.termAppEnabled = normalized.term.enabled ? normalized.term.appEnabled : false;

  detailed.services.zenmindAppServer.enabled = normalized.admin.enabled;
  detailed.services.zenmindAppServer.frontendPort = normalized.admin.frontendPort;
  detailed.services.zenmindAppServer.issuer = websiteOrigin;
  detailed.services.zenmindAppServer.adminPassword = normalizeSecret(normalized.admin.adminPassword);
  detailed.services.zenmindAppServer.appMasterPassword = normalizeSecret(normalized.admin.appMasterPassword);

  detailed.services.voiceServer.runnerBaseUrl = normalized.agentPlatformRunner.baseUrl;

  detailed.services.panWebclient.enabled = normalized.pan.enabled;
  detailed.services.panWebclient.frontendPort = normalized.pan.frontendPort;
  detailed.services.panWebclient.webPassword = normalizeSecret(normalized.pan.webPassword);
  detailed.services.panWebclient.webSessionSecret = normalized.pan.webSessionSecret;
  detailed.services.panWebclient.jwtPublicKeyPem = managedPublicKey;
  detailed.services.panWebclient.mounts = [];

  detailed.services.termWebclient.enabled = normalized.term.enabled;
  detailed.services.termWebclient.frontendPort = normalized.term.frontendPort;
  detailed.services.termWebclient.webPassword = normalizeSecret(normalized.term.webPassword);
  detailed.services.termWebclient.appAuthIssuer = websiteOrigin;
  detailed.services.termWebclient.jwtPublicKeyPem = managedPublicKey;
  detailed.services.termWebclient.mounts = [];
  detailed.services.termWebclient.agentsYaml = "";
  detailed.services.termWebclient.assistYaml = "";
  detailed.services.termWebclient.assistApiKey = "";

  detailed.services.miniAppServer.enabled = normalized.miniApp.enabled;
  detailed.services.miniAppServer.defaultAppMode = normalized.miniApp.defaultAppMode;
  detailed.services.miniAppServer.publicBase = normalized.miniApp.publicBase;
  detailed.services.miniAppServer.port = normalized.miniApp.port;

  for (const serviceKey of ["mcpServerImagine", "mcpServerBash", "mcpServerMock", "mcpServerEmail"]) {
    detailed.services[serviceKey].enabled = normalized.mcp.enabled;
    detailed.services[serviceKey].hostPortEnabled = normalized.mcp.enabled && detailed.services[serviceKey].hostPortEnabled;
  }

  detailed.__groups = {
    mcpEnabled: normalized.mcp.enabled,
    sandboxesEnabled: normalized.sandboxes.enabled
  };

  return detailed;
}

export function getDefaultProfile() {
  return clone(DEFAULT_PROFILE);
}

export function loadProfile(profilePath) {
  const normalized = normalizeProfile(parseJSONFile(profilePath));
  validateProfile(normalized);
  return normalized;
}

export function validateProfile(profile) {
  const normalized = normalizeProfile(profile);
  assert(normalized.profileVersion === 2, "profileVersion must be 2");
  assert(typeof normalized.website?.domain === "string" && normalized.website.domain.trim(), "website.domain is required");
  assert(typeof normalized.agentPlatformRunner?.baseUrl === "string" && normalized.agentPlatformRunner.baseUrl.trim(), "agentPlatformRunner.baseUrl is required");
  ensurePort(normalized.gateway.listenPort, "gateway.listenPort");
  ensurePort(normalized.admin.frontendPort, "admin.frontendPort");
  ensurePort(normalized.pan.frontendPort, "pan.frontendPort");
  ensurePort(normalized.term.frontendPort, "term.frontendPort");
  ensurePort(normalized.miniApp.port, "miniApp.port");
}

function normalizeMultiline(value) {
  return String(value || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\n?$/, "\n");
}

function quoteEnv(value) {
  const normalized = String(value ?? "").replace(/\r/g, "").replace(/\n/g, "");
  if (/^[A-Za-z0-9_./:-]+$/.test(normalized)) {
    return normalized;
  }
  return `'${normalized.replace(/'/g, "'\"'\"'")}'`;
}

function normalizeBcrypt(hash) {
  const trimmed = String(hash || "").trim().replace(/^['"]|['"]$/g, "");
  if (trimmed.startsWith("$2b$")) {
    return `$2y$${trimmed.slice(4)}`;
  }
  return trimmed;
}

function resolveSecretHash(secret, bcryptScriptPath) {
  const direct = normalizeBcrypt(secret?.bcrypt || "");
  if (direct) {
    return direct;
  }
  const plain = String(secret?.plain || "").trim();
  if (!plain) {
    return "";
  }
  return execFileSync(bcryptScriptPath, [plain], { encoding: "utf8" }).trim();
}

function commentHeader(message) {
  return `# Generated by zenmind apply-config\n# ${message}\n`;
}

function renderEnv(lines) {
  return `${lines.join("\n")}\n`;
}

function renderJSON(data) {
  return `${JSON.stringify(data, null, 2)}\n`;
}

function serviceEnabled(profile, product) {
  switch (product) {
    case "gateway":
      return true;
    case "zenmind-app-server":
      return profile.services.zenmindAppServer.enabled;
    case "zenmind-voice-server":
      return true;
    case "pan-webclient":
      return profile.services.panWebclient.enabled;
    case "term-webclient":
      return profile.services.termWebclient.enabled;
    case "mini-app-server":
      return profile.services.miniAppServer.enabled;
    case "mcp-server-imagine":
      return profile.services.mcpServerImagine.enabled;
    case "mcp-server-bash":
      return profile.services.mcpServerBash.enabled;
    case "mcp-server-mock":
      return profile.services.mcpServerMock.enabled;
    case "mcp-server-email":
      return profile.services.mcpServerEmail.enabled;
    default:
      return false;
  }
}

function renderComposeEnv(profile) {
  return renderEnv([
    commentHeader("Root docker compose variables").trimEnd(),
    `PUBLIC_ORIGIN=${profile.website.publicOrigin}`,
    `CLOUDFLARED_HOSTNAME=${profile.cloudflared.hostname}`,
    `CLOUDFLARED_TUNNEL_UUID=${profile.cloudflared.tunnelUuid}`,
    `CLOUDFLARED_CREDENTIALS_FILE=${normalizePathValue(profile.cloudflared.credentialsFile)}`,
    `CLOUDFLARED_CONFIG_FILE=${normalizePathValue(profile.cloudflared.configFile)}`,
    `GATEWAY_LISTEN_IP=${profile.gateway.listenIp}`,
    `GATEWAY_PORT=${profile.gateway.listenPort}`,
    `APP_SERVER_FRONTEND_PORT=${profile.services.zenmindAppServer.frontendPort}`,
    `VOICE_SERVER_PORT=${profile.services.voiceServer.port}`,
    `PAN_FRONTEND_PORT=${profile.services.panWebclient.frontendPort}`,
    `TERM_FRONTEND_PORT=${profile.services.termWebclient.frontendPort}`,
    `MINI_APP_PORT=${profile.services.miniAppServer.port}`,
    `MCP_IMAGINE_HOST_PORT=${profile.services.mcpServerImagine.hostPort}`,
    `MCP_BASH_HOST_PORT=${profile.services.mcpServerBash.hostPort}`,
    `MCP_EMAIL_HOST_PORT=${profile.services.mcpServerEmail.hostPort}`,
    `MCP_MOCK_HOST_PORT=${profile.services.mcpServerMock.hostPort}`,
    `APP_SERVER_VITE_BASE_PATH=${profile.services.zenmindAppServer.viteBasePath}`,
    `MCP_IMAGINE_RUNNER_DATA_ROOT=${profile.services.mcpServerImagine.runnerDataRoot}`
  ]);
}

function renderComposeOverride(profile) {
  const lines = ["services:"];
  const addPortBlock = (serviceName, envVar, enabled) => {
    lines.push(`  ${serviceName}:`);
    if (enabled) {
      lines.push("    ports:");
      lines.push(`      - "\${${envVar}}:8080"`);
    } else {
      lines.push("    ports: []");
    }
  };

  addPortBlock("mcp-server-imagine", "MCP_IMAGINE_HOST_PORT", profile.services.mcpServerImagine.hostPortEnabled);
  addPortBlock("mcp-server-bash", "MCP_BASH_HOST_PORT", profile.services.mcpServerBash.hostPortEnabled);
  addPortBlock("mcp-server-email", "MCP_EMAIL_HOST_PORT", profile.services.mcpServerEmail.hostPortEnabled);
  addPortBlock("mcp-server-mock", "MCP_MOCK_HOST_PORT", profile.services.mcpServerMock.hostPortEnabled);
  return `${lines.join("\n")}\n`;
}

function renderStartupConfig(profile) {
  const enabled = FIXED_STARTUP_PRODUCTS.filter((product) => serviceEnabled(profile, product));
  return `${commentHeader("One product per line. Order defines startup sequence.")}${enabled.join("\n")}\n`;
}

function renderGatewayNginx(profile) {
  const runnerBase = new URL(profile.agentPlatformRunner.baseUrl);
  const runnerBackend = `${runnerBase.hostname}:${runnerBase.port || (runnerBase.protocol === "https:" ? 443 : 80)}`;
  const adminGate = profile.access.adminPublicEnabled
    ? [
        "        location ^~ /admin/api {",
        "            proxy_pass http://zenmind_app_server_backend;",
        "        }",
        "",
        "        location ^~ /admin {",
        "            proxy_pass http://zenmind_app_server_frontend;",
        "        }"
      ]
    : [
        "        location ^~ /admin/api {",
        "            return 404;",
        "        }",
        "",
        "        location ^~ /admin {",
        "            return 404;",
        "        }"
      ];
  const panWebGate = profile.access.panWebEnabled
    ? [
        "        location = /pan { return 301 /pan/; }",
        "        location ^~ /pan/ { proxy_pass http://pan_webclient_frontend; }"
      ]
    : [
        "        location = /pan { return 404; }",
        "        location ^~ /pan/ { return 404; }"
      ];
  const panAppGate = profile.access.panAppEnabled
    ? [
        "        location = /apppan { return 301 /apppan/; }",
        "        location ^~ /apppan/ { proxy_pass http://pan_webclient_frontend; }"
      ]
    : [
        "        location = /apppan { return 404; }",
        "        location ^~ /apppan/ { return 404; }"
      ];
  const termWebGate = profile.access.termWebEnabled
    ? [
        "        location = /term { return 301 /term/; }",
        "        location ^~ /term/ { proxy_pass http://term_webclient_frontend; }"
      ]
    : [
        "        location = /term { return 404; }",
        "        location ^~ /term/ { return 404; }"
      ];
  const termAppGate = profile.access.termAppEnabled
    ? [
        "        location = /appterm { return 301 /appterm/; }",
        "        location ^~ /appterm/ { proxy_pass http://term_webclient_frontend; }"
      ]
    : [
        "        location = /appterm { return 404; }",
        "        location ^~ /appterm/ { return 404; }"
      ];
  const mcpRoutes = profile.__groups?.mcpEnabled
    ? [
        "        location = /api/mcp/mock { proxy_pass http://mcp_server_mock/mcp; }",
        "        location = /api/mcp/email { proxy_pass http://mcp_server_email/mcp; }",
        "        location = /api/mcp/bash { proxy_pass http://mcp_server_bash/mcp; }",
        "        location = /api/mcp/imagine { proxy_pass http://mcp_server_imagine/mcp; }"
      ]
    : [
        "        location = /api/mcp/mock { return 404; }",
        "        location = /api/mcp/email { return 404; }",
        "        location = /api/mcp/bash { return 404; }",
        "        location = /api/mcp/imagine { return 404; }"
      ];

  return [
    "worker_processes auto;",
    "",
    "events {",
    "    worker_connections 1024;",
    "}",
    "",
    "http {",
    "    include /etc/nginx/mime.types;",
    "    default_type application/octet-stream;",
    "    sendfile on;",
    "    tcp_nopush on;",
    "    tcp_nodelay on;",
    "    keepalive_timeout 65;",
    "    resolver 127.0.0.11 ipv6=off valid=30s;",
    "",
    "    map $http_upgrade $connection_upgrade {",
    "        default upgrade;",
    "        '' close;",
    "    }",
    "",
    "    map $http_x_forwarded_proto $proxy_x_forwarded_proto {",
    "        default $http_x_forwarded_proto;",
    "        '' $scheme;",
    "    }",
    "",
    "    upstream zenmind_app_server_backend { server zenmind-app-server-backend:8080; }",
    "    upstream zenmind_app_server_frontend { server zenmind-app-server-frontend:80; }",
    "    upstream zenmind_voice_server { server zenmind-voice-server:11953; }",
    "    upstream pan_webclient_frontend { server pan-webclient-frontend:80; }",
    "    upstream term_webclient_frontend { server term-webclient-frontend:11947; }",
    "    upstream mini_app_server { server mini-app-server:11948; }",
    "    upstream agent_platform_runner { server " + runnerBackend + "; }",
    "    upstream mcp_server_mock { server mcp-server-mock:8080; }",
    "    upstream mcp_server_email { server mcp-server-email:8080; }",
    "    upstream mcp_server_bash { server mcp-server-bash:8080; }",
    "    upstream mcp_server_imagine { server mcp-server-imagine:8080; }",
    "",
    "    server {",
    "        listen 80;",
    "        server_name _;",
    "",
    "        proxy_set_header Host $host;",
    "        proxy_set_header X-Real-IP $remote_addr;",
    "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
    "        proxy_set_header X-Forwarded-Proto $proxy_x_forwarded_proto;",
    "        proxy_http_version 1.1;",
    "        proxy_set_header Upgrade $http_upgrade;",
    "        proxy_set_header Connection $connection_upgrade;",
    "",
    "        location = /healthz {",
    "            add_header Content-Type text/plain;",
    "            return 200 \"ok\";",
    "        }",
    "",
    "        location ^~ /api/auth { proxy_pass http://zenmind_app_server_backend; }",
    "        location ^~ /api/app { proxy_pass http://zenmind_app_server_backend; }",
    "        location ^~ /oauth2 { proxy_pass http://zenmind_app_server_backend; }",
    "        location ^~ /openid { proxy_pass http://zenmind_app_server_backend; }",
    "",
    ...adminGate,
    "",
    "        location ^~ /api/voice/ { proxy_pass http://zenmind_voice_server; }",
    "        location ^~ /api/ap/ {",
    "            proxy_buffering off;",
    "            proxy_cache off;",
    "            proxy_read_timeout 3600s;",
    "            proxy_send_timeout 3600s;",
    "            add_header X-Accel-Buffering no;",
    "            proxy_pass http://agent_platform_runner;",
    "        }",
    "",
    ...mcpRoutes,
    "",
    ...panWebGate,
    ...panAppGate,
    ...termWebGate,
    ...termAppGate,
    "",
    "        location ^~ /ma/ {",
    "            proxy_set_header X-Forwarded-Prefix /ma;",
    "            rewrite ^/ma/(.*)$ /$1 break;",
    "            proxy_redirect ~^(/.*)$ /ma$1;",
    "            proxy_pass http://mini_app_server;",
    "        }",
    "",
    "        location = /ma { return 301 /ma/; }",
    "",
    "        location / {",
    "            return 404;",
    "        }",
    "    }",
    "}"
  ].join("\n") + "\n";
}

function renderAppServerEnv(profile, bcryptScriptPath) {
  const service = profile.services.zenmindAppServer;
  return renderEnv([
    commentHeader("zenmind-app-server deployment contract").trimEnd(),
    `FRONTEND_PORT=${service.frontendPort}`,
    `AUTH_ISSUER=${quoteEnv(service.issuer)}`,
    `AUTH_ADMIN_USERNAME=${quoteEnv(service.adminUsername)}`,
    `AUTH_APP_USERNAME=${quoteEnv(service.appUsername)}`,
    `VITE_BASE_PATH=${quoteEnv(service.viteBasePath)}`,
    `AUTH_ADMIN_PASSWORD_BCRYPT=${quoteEnv(resolveSecretHash(service.adminPassword, bcryptScriptPath))}`,
    `AUTH_APP_MASTER_PASSWORD_BCRYPT=${quoteEnv(resolveSecretHash(service.appMasterPassword, bcryptScriptPath))}`
  ]);
}

function renderVoiceEnv(profile) {
  const service = profile.services.voiceServer;
  return renderEnv([
    commentHeader("zenmind-voice-server deployment contract").trimEnd(),
    `DASHSCOPE_API_KEY=${quoteEnv(service.dashscopeApiKey)}`,
    `DASHSCOPE_TTS_API_KEY=${quoteEnv(service.dashscopeTtsApiKey)}`,
    `APP_VOICE_TTS_LLM_RUNNER_BASE_URL=${quoteEnv(service.runnerBaseUrl)}`,
    `APP_VOICE_TTS_LLM_RUNNER_AGENT_KEY=${quoteEnv(service.runnerAgentKey)}`,
    `APP_VOICE_TTS_LLM_RUNNER_AUTHORIZATION_TOKEN=${quoteEnv(service.runnerAuthorizationToken)}`,
    `SERVER_PORT=${service.port}`
  ]);
}

function renderPanEnv(profile, bcryptScriptPath) {
  const service = profile.services.panWebclient;
  return renderEnv([
    commentHeader("pan-webclient deployment contract").trimEnd(),
    `NGINX_PORT=${service.frontendPort}`,
    "API_PORT=8080",
    "NODE_ENV=production",
    `PAN_ADMIN_USERNAME=${quoteEnv(service.adminUsername)}`,
    `WEB_SESSION_SECRET=${quoteEnv(service.webSessionSecret)}`,
    `AUTH_PASSWORD_HASH_BCRYPT=${quoteEnv(resolveSecretHash(service.webPassword, bcryptScriptPath))}`,
    "APP_AUTH_LOCAL_PUBLIC_KEY_FILE=./configs/local-public-key.pem",
    `PAN_DATA_DIR=${quoteEnv(service.dataDir)}`,
    `MAX_UPLOAD_BYTES=${service.maxUploadBytes}`,
    `MAX_EDIT_FILE_BYTES=${service.maxEditFileBytes}`
  ]);
}

function renderTermEnv(profile, bcryptScriptPath) {
  const service = profile.services.termWebclient;
  return renderEnv([
    commentHeader("term-webclient deployment contract").trimEnd(),
    "BACKEND_HOST=0.0.0.0",
    "BACKEND_PORT=11937",
    "FRONTEND_HOST=0.0.0.0",
    `FRONTEND_PORT=${service.frontendPort}`,
    "CONFIG_PATH=./configs/config.docker-host.yml",
    `COPILOT_RUNNER_BASE_URL=${quoteEnv(service.copilotRunnerBaseUrl)}`,
    `COPILOT_RUNNER_AUTHORIZATION_BEARER=${quoteEnv(service.copilotRunnerAuthorizationBearer)}`,
    `AUTH_ENABLED=${service.authEnabled ? "true" : "false"}`,
    `AUTH_USERNAME=${quoteEnv(service.authUsername)}`,
    `AUTH_PASSWORD_HASH_BCRYPT=${quoteEnv(resolveSecretHash(service.webPassword, bcryptScriptPath))}`,
    `APP_AUTH_ENABLED=${service.appAuthEnabled ? "true" : "false"}`,
    "APP_AUTH_LOCAL_PUBLIC_KEY_FILE=./configs/local-public-key.pem",
    `APP_AUTH_JWKS_URI=${quoteEnv(service.appAuthJwksUri)}`,
    `APP_AUTH_ISSUER=${quoteEnv(service.appAuthIssuer)}`,
    `APP_AUTH_AUDIENCE=${quoteEnv(service.appAuthAudience)}`,
    `TERMINAL_FILES_ENABLED=${service.terminalFilesEnabled ? "true" : "false"}`,
    "TERMINAL_SSH_CREDENTIALS_FILE=data/ssh-credentials.json",
    `TERMINAL_SSH_MASTER_KEY=${quoteEnv(service.terminalSshMasterKey)}`,
    `ASSIST_API_KEY=${quoteEnv(service.assistApiKey)}`
  ]);
}

function renderMiniAppEnv(profile) {
  const service = profile.services.miniAppServer;
  return renderEnv([
    commentHeader("mini-app-server deployment contract").trimEnd(),
    `DEFAULT_APP_MODE=${quoteEnv(service.defaultAppMode)}`,
    `PLATFORM_BASE=${quoteEnv(service.platformBase)}`,
    `PUBLIC_BASE=${quoteEnv(service.publicBase)}`,
    `PORT=${service.port}`,
    `HOST=${quoteEnv(service.host)}`
  ]);
}

function renderImagineEnv(profile) {
  const service = profile.services.mcpServerImagine;
  return renderEnv([
    commentHeader("mcp-server-imagine deployment contract").trimEnd(),
    `HOST_PORT=${service.hostPort}`,
    `RUNNER_DATA_ROOT=${quoteEnv(service.runnerDataRoot)}`,
    "CONFIG_PATH=",
    `SERVER_PORT=${service.serverPort}`,
    "MCP_TOOLS_SPEC_LOCATION_PATTERN=./tools/*.yml",
    "MCP_HTTP_MAX_BODY_BYTES=1048576",
    "MCP_OBSERVABILITY_LOG_ENABLED=true",
    "MCP_OBSERVABILITY_LOG_MAX_BODY_LENGTH=2000",
    "MCP_OBSERVABILITY_LOG_INCLUDE_HEADERS=false"
  ]);
}

function renderBashEnv(profile) {
  const service = profile.services.mcpServerBash;
  return renderEnv([
    commentHeader("mcp-server-bash deployment contract").trimEnd(),
    `HOST_PORT=${service.hostPort}`,
    `SERVER_PORT=${service.serverPort}`,
    "MCP_TOOLS_SPEC_LOCATION_PATTERN=./tools/*.yml",
    "MCP_HTTP_MAX_BODY_BYTES=1048576",
    "MCP_OBSERVABILITY_LOG_ENABLED=true",
    "MCP_OBSERVABILITY_LOG_MAX_BODY_LENGTH=2000",
    "MCP_OBSERVABILITY_LOG_INCLUDE_HEADERS=false",
    `BASH_WORKING_DIRECTORY=${quoteEnv(service.workingDirectory)}`,
    `BASH_ALLOWED_PATHS=${quoteEnv(service.allowedPaths)}`,
    `BASH_ALLOWED_COMMANDS=${quoteEnv(service.allowedCommands)}`,
    "BASH_PATH_CHECKED_COMMANDS=ls,cat,head,tail,git,rg,find",
    "BASH_PATH_CHECK_BYPASS_COMMANDS=git",
    "BASH_SHELL_FEATURES_ENABLED=false",
    "BASH_SHELL_EXECUTABLE=bash",
    "BASH_SHELL_TIMEOUT_MS=10000",
    "BASH_MAX_COMMAND_CHARS=16000",
    "BASH_MAX_OUTPUT_CHARS=8000",
    "BASH_VARIABLE_SUBSTITUTION_ENABLED=false",
    "BASH_VARIABLE_STORE_FILE=./data/bash-variables.json"
  ]);
}

function renderMockEnv(profile) {
  const service = profile.services.mcpServerMock;
  return renderEnv([
    commentHeader("mcp-server-mock deployment contract").trimEnd(),
    `HOST_PORT=${service.hostPort}`,
    "CONFIG_PATH=",
    `SERVER_PORT=${service.serverPort}`,
    "MCP_TOOLS_SPEC_LOCATION_PATTERN=./tools/*.yml",
    "MCP_VIEWPORTS_DIR=./viewports",
    "MCP_HTTP_MAX_BODY_BYTES=1048576",
    "MCP_OBSERVABILITY_LOG_ENABLED=true",
    "MCP_OBSERVABILITY_LOG_MAX_BODY_LENGTH=2000",
    "MCP_OBSERVABILITY_LOG_INCLUDE_HEADERS=false",
    "MCP_BASH_WORKING_DIRECTORY=.",
    "MCP_BASH_ALLOWED_ROOTS=.,./tools,./viewports,/tmp",
    "MCP_BASH_ALLOWED_COMMANDS=pwd,ls,cat,head,tail,echo,env,find",
    "MCP_BASH_TIMEOUT_MS=10000",
    "MCP_BASH_MAX_COMMAND_CHARS=4000",
    "MCP_BASH_MAX_OUTPUT_CHARS=8000"
  ]);
}

function renderEmailEnv(profile) {
  const service = profile.services.mcpServerEmail;
  return renderEnv([
    commentHeader("mcp-server-email deployment contract").trimEnd(),
    `HOST_PORT=${service.hostPort}`,
    `SERVER_PORT=${service.serverPort}`,
    "SERVER_SHUTDOWN_TIMEOUT_SECONDS=10",
    "MCP_TRANSPORT=http",
    "MCP_HTTP_MAX_BODY_BYTES=1048576",
    "MCP_RATE_LIMIT_ENABLED=false",
    "MCP_RATE_LIMIT_RPS=5",
    "MCP_RATE_LIMIT_BURST=10",
    "MCP_TOOLS_SPEC_LOCATION_PATTERN=./tools/*.yml",
    "MCP_OBSERVABILITY_LOG_ENABLED=true",
    "MCP_OBSERVABILITY_LOG_MAX_BODY_LENGTH=2000",
    "MCP_OBSERVABILITY_LOG_INCLUDE_HEADERS=false",
    "MAIL_ACCOUNTS_CONFIG_PATH=./configs",
    "MAIL_DEFAULT_FOLDER=INBOX",
    "MAIL_DIAL_TIMEOUT_SECONDS=10"
  ]);
}

function repoPath(reposRoot, name, ...segments) {
  return path.join(reposRoot, name, ...segments);
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function collectWrites(profile, workspaceRoot, reposRoot, bcryptScriptPath) {
  const normalized = normalizeProfile(profile);
  const detailed = expandProfile(normalized, reposRoot);
  const rootWrites = [];
  const siblingWrites = [];
  const generatedRoot = path.join(workspaceRoot, "generated");

  rootWrites.push({ path: path.join(generatedRoot, "docker-compose.env"), content: renderComposeEnv(detailed) });
  rootWrites.push({ path: path.join(generatedRoot, "docker-compose.override.yml"), content: renderComposeOverride(detailed) });
  rootWrites.push({ path: path.join(generatedRoot, "gateway", "nginx.conf"), content: renderGatewayNginx(detailed) });
  rootWrites.push({ path: path.join(workspaceRoot, "config", "startup-services.conf"), content: renderStartupConfig(detailed) });

  siblingWrites.push({ path: repoPath(reposRoot, "zenmind-app-server", ".env"), content: renderAppServerEnv(detailed, bcryptScriptPath) });
  siblingWrites.push({ path: repoPath(reposRoot, "zenmind-voice-server", ".env"), content: renderVoiceEnv(detailed) });
  siblingWrites.push({ path: repoPath(reposRoot, "pan-webclient", ".env"), content: renderPanEnv(detailed, bcryptScriptPath) });
  siblingWrites.push({ path: repoPath(reposRoot, "pan-webclient", "configs", "local-public-key.pem"), content: normalizeMultiline(detailed.services.panWebclient.jwtPublicKeyPem) });
  siblingWrites.push({ path: repoPath(reposRoot, "term-webclient", ".env"), content: renderTermEnv(detailed, bcryptScriptPath) });
  siblingWrites.push({ path: repoPath(reposRoot, "term-webclient", "configs", "local-public-key.pem"), content: normalizeMultiline(detailed.services.termWebclient.jwtPublicKeyPem) });
  siblingWrites.push({ path: repoPath(reposRoot, "mini-app-server", ".env"), content: renderMiniAppEnv(detailed) });

  if (normalized.mcp.enabled) {
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-imagine", ".env"), content: renderImagineEnv(detailed) });
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-bash", ".env"), content: renderBashEnv(detailed) });
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-mock", ".env"), content: renderMockEnv(detailed) });
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-email", ".env"), content: renderEmailEnv(detailed) });
  }

  return { rootWrites, siblingWrites };
}

export function applyProfile({ profile, workspaceRoot, reposRoot, bcryptScriptPath, dryRun = false, rootOnly = false }) {
  const { rootWrites, siblingWrites } = collectWrites(profile, workspaceRoot, reposRoot, bcryptScriptPath);
  const writes = rootOnly ? rootWrites : [...rootWrites, ...siblingWrites];

  if (!dryRun) {
    for (const write of writes) {
      ensureDir(path.dirname(write.path));
      fs.writeFileSync(write.path, write.content, "utf8");
    }
  }

  return { writes, extraSteps: [] };
}

export function getProfileLocations(workspaceRoot) {
  return {
    workspaceRoot,
    reposRoot: path.resolve(workspaceRoot, ".."),
    profileExamplePath: path.join(workspaceRoot, "config", "zenmind.profile.example.json"),
    profileLocalPath: path.join(workspaceRoot, "config", "zenmind.profile.local.json"),
    bcryptScriptPath: path.join(workspaceRoot, "scripts", "shared", "generate-bcrypt.sh")
  };
}

export function ensureLocalProfileExists(workspaceRoot) {
  const locations = getProfileLocations(workspaceRoot);
  if (!fs.existsSync(locations.profileLocalPath)) {
    ensureDir(path.dirname(locations.profileLocalPath));
    fs.copyFileSync(locations.profileExamplePath, locations.profileLocalPath);
  }
  return locations.profileLocalPath;
}

export function loadProfileFromWorkspace(workspaceRoot, overrideProfilePath) {
  const locations = getProfileLocations(workspaceRoot);
  const profilePath = overrideProfilePath || ensureLocalProfileExists(workspaceRoot);
  return { profilePath, profile: loadProfile(profilePath), locations };
}

export function serializeProfileToJSONString(profile) {
  return `${JSON.stringify(serializeProfile(profile), null, 2)}\n`;
}
