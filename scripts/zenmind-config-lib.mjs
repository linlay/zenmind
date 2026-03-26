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
  "mcp-server-imagine",
  "mcp-server-mock",
  "agent-platform-runner",
  "agent-container-hub"
];

export const SERVICE_EXPANSIONS = {
  gateway: ["gateway"],
  "zenmind-app-server": ["zenmind-app-server-backend", "zenmind-app-server-frontend"],
  "zenmind-voice-server": ["zenmind-voice-server"],
  "pan-webclient": ["pan-webclient-api", "pan-webclient-frontend"],
  "term-webclient": ["term-webclient-backend", "term-webclient-frontend"],
  "mcp-server-imagine": ["mcp-server-imagine"],
  "mcp-server-mock": ["mcp-server-mock"],
  "agent-platform-runner": ["agent-platform-runner"],
  "agent-container-hub": []
};

export const PRODUCT_RUNTIME_TYPES = {
  gateway: "image",
  "zenmind-app-server": "image",
  "zenmind-voice-server": "image",
  "pan-webclient": "image",
  "term-webclient": "image",
  "mcp-server-imagine": "image",
  "mcp-server-mock": "image",
  "agent-platform-runner": "image",
  "agent-container-hub": "host"
};

const DEFAULT_PROFILE = {
  profileVersion: 2,
  website: {
    domain: "website.example.com"
  },
  images: {
    registry: "registry.example.com/zenmind",
    tag: "latest"
  },
  cloudflared: {
    tunnelUuid: "replace-with-your-tunnel-uuid"
  },
  gateway: {
    listenPort: 11945
  },
  agentPlatformRunner: {
    enabled: true,
    hostPort: 11949,
    baseUrl: "http://127.0.0.1:11949"
  },
  containerHub: {
    enabled: false,
    port: 11960,
    authToken: ""
  },
  admin: {
    enabled: true,
    webEnabled: true,
    adminUsername: "admin",
    frontendPort: 11950,
    webPasswordBcrypt: "",
    appMasterPasswordBcrypt: ""
  },
  pan: {
    enabled: true,
    webEnabled: true,
    adminUsername: "admin",
    frontendPort: 11946,
    webPasswordBcrypt: "",
    webSessionSecret: ""
  },
  term: {
    enabled: true,
    webEnabled: true,
    authUsername: "admin",
    frontendPort: 11947,
    webPasswordBcrypt: ""
  },
  llm: {
    primaryProviderKey: "",
    primaryModelKey: "",
    primaryApiKey: ""
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
  images: {
    registry: "registry.example.com/zenmind",
    tag: "latest"
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
    enabled: true,
    hostPort: 11949,
    baseUrl: "http://127.0.0.1:11949"
  },
  containerHub: {
    enabled: false,
    port: 11960,
    authToken: ""
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
    mcpServerImagine: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11962,
      serverPort: 8080,
      runnerDataRoot: "../mcp-server-imagine/data",
      providerConfigs: []
    },
    mcpServerMock: {
      enabled: true,
      hostPortEnabled: true,
      hostPort: 11969,
      serverPort: 8080
    },
    agentPlatformRunner: {
      enabled: true,
      hostPort: 11949,
      baseUrl: "http://agent-platform-runner:8080",
      publicBaseUrl: "http://127.0.0.1:11949",
      authEnabled: true,
      chatImageTokenSecret: "",
      runtimeRoot: "../.zenmind",
      dirs: {
        agents: "../.zenmind/agents",
        teams: "../.zenmind/teams",
        models: "../.zenmind/models",
        providers: "../.zenmind/providers",
        tools: "../.zenmind/tools",
        mcpServers: "../.zenmind/mcp-servers",
        viewportServers: "../.zenmind/viewport-servers",
        viewports: "../.zenmind/viewports",
        skillsMarket: "../.zenmind/skills-market",
        schedules: "../.zenmind/schedules",
        chats: "../.zenmind/chats",
        root: "../.zenmind/root",
        pan: "../.zenmind/pan"
      }
    },
    containerHub: {
      enabled: false,
      port: 11960,
      authToken: "",
      bindAddr: "127.0.0.1:11960",
      configRoot: "./configs",
      rootfsRoot: "./data/rootfs",
      buildRoot: "./data/builds",
      sessionMountTemplateRoot: ""
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

function usesLocalReleaseIssuer(domain) {
  const normalized = normalizeDomain(domain);
  if (!normalized) {
    return true;
  }
  if (normalized === "localhost" || normalized === "127.0.0.1") {
    return true;
  }
  if (normalized === DEFAULT_PROFILE.website.domain) {
    return true;
  }
  if (normalized.endsWith(".example.com")) {
    return true;
  }
  return false;
}

function deriveReleaseIssuer(domain, gatewayPort) {
  if (usesLocalReleaseIssuer(domain)) {
    return `http://127.0.0.1:${gatewayPort}`;
  }
  return deriveOrigin(domain);
}

function derivePublicRunnerBaseUrl(hostPort) {
  return `http://127.0.0.1:${hostPort}`;
}

function deriveContainerRunnerBaseUrl() {
  return "http://agent-platform-runner:8080";
}

function parsePortFromUrl(value, fallbackPort) {
  try {
    const parsed = new URL(String(value || ""));
    if (parsed.port) {
      return Number.parseInt(parsed.port, 10);
    }
    if (parsed.protocol === "https:") {
      return 443;
    }
    if (parsed.protocol === "http:") {
      return 80;
    }
  } catch {
    return fallbackPort;
  }
  return fallbackPort;
}

function getBcryptValue(secret) {
  if (typeof secret === "string") {
    return normalizeBcrypt(secret);
  }
  if (secret && typeof secret === "object") {
    return normalizeBcrypt(secret.bcrypt || "");
  }
  return "";
}

function captureLegacySecret(secret) {
  if (!secret || typeof secret !== "object") {
    return null;
  }
  const plain = String(secret.plain || "");
  const bcrypt = normalizeBcrypt(secret.bcrypt || "");
  if (!plain.trim() && !bcrypt) {
    return null;
  }
  return { plain, bcrypt };
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
    const runnerHostPort = rawProfile?.agentPlatformRunner?.hostPort
      ?? parsePortFromUrl(rawProfile?.agentPlatformRunner?.baseUrl, DEFAULT_PROFILE.agentPlatformRunner.hostPort);
    const containerHubPort = rawProfile?.containerHub?.port ?? DEFAULT_PROFILE.containerHub.port;
    return {
      profileVersion: 2,
      website: {
        domain: normalizeDomain(rawProfile?.website?.domain || DEFAULT_PROFILE.website.domain)
      },
      images: {
        registry: String(rawProfile?.images?.registry || DEFAULT_PROFILE.images.registry).trim(),
        tag: String(rawProfile?.images?.tag || DEFAULT_PROFILE.images.tag).trim()
      },
      cloudflared: {
        tunnelUuid: String(rawProfile?.cloudflared?.tunnelUuid || DEFAULT_PROFILE.cloudflared.tunnelUuid)
      },
      gateway: {
        listenPort: rawProfile?.gateway?.listenPort ?? DEFAULT_PROFILE.gateway.listenPort
      },
      agentPlatformRunner: {
        enabled: Boolean(rawProfile?.agentPlatformRunner?.enabled ?? DEFAULT_PROFILE.agentPlatformRunner.enabled),
        hostPort: runnerHostPort,
        baseUrl: String(rawProfile?.agentPlatformRunner?.baseUrl || derivePublicRunnerBaseUrl(runnerHostPort))
      },
      containerHub: {
        enabled: Boolean(rawProfile?.containerHub?.enabled ?? rawProfile?.sandboxes?.enabled ?? DEFAULT_PROFILE.containerHub.enabled),
        port: containerHubPort,
        authToken: String(rawProfile?.containerHub?.authToken || DEFAULT_PROFILE.containerHub.authToken)
      },
      admin: {
        enabled: Boolean(rawProfile?.admin?.enabled ?? DEFAULT_PROFILE.admin.enabled),
        webEnabled: Boolean(rawProfile?.admin?.webEnabled ?? rawProfile?.admin?.publicEnabled ?? DEFAULT_PROFILE.admin.webEnabled),
        adminUsername: String(rawProfile?.admin?.adminUsername || DEFAULT_PROFILE.admin.adminUsername).trim() || DEFAULT_PROFILE.admin.adminUsername,
        frontendPort: rawProfile?.admin?.frontendPort ?? DEFAULT_PROFILE.admin.frontendPort,
        webPasswordBcrypt: getBcryptValue(rawProfile?.admin?.webPasswordBcrypt || rawProfile?.admin?.adminPassword),
        appMasterPasswordBcrypt: getBcryptValue(rawProfile?.admin?.appMasterPasswordBcrypt || rawProfile?.admin?.appMasterPassword)
      },
      pan: {
        enabled: Boolean(rawProfile?.pan?.enabled ?? DEFAULT_PROFILE.pan.enabled),
        webEnabled: Boolean(rawProfile?.pan?.webEnabled ?? DEFAULT_PROFILE.pan.webEnabled),
        adminUsername: String(rawProfile?.pan?.adminUsername || rawProfile?.admin?.adminUsername || DEFAULT_PROFILE.pan.adminUsername).trim() || DEFAULT_PROFILE.pan.adminUsername,
        frontendPort: rawProfile?.pan?.frontendPort ?? DEFAULT_PROFILE.pan.frontendPort,
        webPasswordBcrypt: getBcryptValue(rawProfile?.pan?.webPasswordBcrypt || rawProfile?.pan?.webPassword),
        webSessionSecret: String(rawProfile?.pan?.webSessionSecret || "")
      },
      term: {
        enabled: Boolean(rawProfile?.term?.enabled ?? DEFAULT_PROFILE.term.enabled),
        webEnabled: Boolean(rawProfile?.term?.webEnabled ?? DEFAULT_PROFILE.term.webEnabled),
        authUsername: String(rawProfile?.term?.authUsername || rawProfile?.admin?.adminUsername || DEFAULT_PROFILE.term.authUsername).trim() || DEFAULT_PROFILE.term.authUsername,
        frontendPort: rawProfile?.term?.frontendPort ?? DEFAULT_PROFILE.term.frontendPort,
        webPasswordBcrypt: getBcryptValue(rawProfile?.term?.webPasswordBcrypt || rawProfile?.term?.webPassword)
      },
      llm: {
        primaryProviderKey: String(rawProfile?.llm?.primaryProviderKey || "").trim(),
        primaryModelKey: String(rawProfile?.llm?.primaryModelKey || "").trim(),
        primaryApiKey: String(rawProfile?.llm?.primaryApiKey || "")
      },
      mcp: {
        enabled: Boolean(rawProfile?.mcp?.enabled ?? DEFAULT_PROFILE.mcp.enabled)
      },
      __legacySecrets: {
        adminWebPassword: captureLegacySecret(rawProfile?.__legacySecrets?.adminWebPassword) || captureLegacySecret(rawProfile?.admin?.adminPassword),
        adminAppMasterPassword: captureLegacySecret(rawProfile?.__legacySecrets?.adminAppMasterPassword) || captureLegacySecret(rawProfile?.admin?.appMasterPassword),
        panWebPassword: captureLegacySecret(rawProfile?.__legacySecrets?.panWebPassword) || captureLegacySecret(rawProfile?.pan?.webPassword),
        termWebPassword: captureLegacySecret(rawProfile?.__legacySecrets?.termWebPassword) || captureLegacySecret(rawProfile?.term?.webPassword)
      }
    };
  }

  const websiteDomain = normalizeDomain(
    rawProfile?.website?.domain || rawProfile?.website?.publicOrigin || rawProfile?.cloudflared?.hostname || DEFAULT_PROFILE.website.domain
  );
  const runnerHostPort = rawProfile?.agentPlatformRunner?.hostPort
    ?? parsePortFromUrl(rawProfile?.agentPlatformRunner?.baseUrl || rawProfile?.services?.voiceServer?.runnerBaseUrl, DEFAULT_PROFILE.agentPlatformRunner.hostPort);
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
    images: {
      registry: String(rawProfile?.images?.registry || DEFAULT_PROFILE.images.registry).trim(),
      tag: String(rawProfile?.images?.tag || DEFAULT_PROFILE.images.tag).trim()
    },
    cloudflared: {
      tunnelUuid: String(rawProfile?.cloudflared?.tunnelUuid || DEFAULT_PROFILE.cloudflared.tunnelUuid)
    },
    gateway: {
      listenPort: rawProfile?.gateway?.listenPort ?? DEFAULT_PROFILE.gateway.listenPort
    },
    agentPlatformRunner: {
      enabled: Boolean(rawProfile?.agentPlatformRunner?.enabled ?? true),
      hostPort: runnerHostPort,
      baseUrl: String(
        rawProfile?.agentPlatformRunner?.baseUrl
        || rawProfile?.services?.voiceServer?.runnerBaseUrl
        || derivePublicRunnerBaseUrl(runnerHostPort)
      )
    },
    containerHub: {
      enabled: Boolean(rawProfile?.containerHub?.enabled ?? rawProfile?.sandboxes?.enabled ?? DEFAULT_PROFILE.containerHub.enabled),
      port: rawProfile?.containerHub?.port ?? DEFAULT_PROFILE.containerHub.port,
      authToken: String(rawProfile?.containerHub?.authToken || DEFAULT_PROFILE.containerHub.authToken)
    },
    admin: {
      enabled: Boolean(rawProfile?.services?.zenmindAppServer?.enabled ?? DEFAULT_PROFILE.admin.enabled),
      webEnabled: Boolean(rawProfile?.access?.adminPublicEnabled ?? DEFAULT_PROFILE.admin.webEnabled),
      adminUsername: String(rawProfile?.services?.zenmindAppServer?.adminUsername || DEFAULT_PROFILE.admin.adminUsername).trim() || DEFAULT_PROFILE.admin.adminUsername,
      frontendPort: rawProfile?.services?.zenmindAppServer?.frontendPort ?? DEFAULT_PROFILE.admin.frontendPort,
      webPasswordBcrypt: getBcryptValue(rawProfile?.services?.zenmindAppServer?.adminPassword),
      appMasterPasswordBcrypt: getBcryptValue(rawProfile?.services?.zenmindAppServer?.appMasterPassword)
    },
    pan: {
      enabled: Boolean(rawProfile?.services?.panWebclient?.enabled ?? DEFAULT_PROFILE.pan.enabled),
      webEnabled: Boolean(rawProfile?.access?.panWebEnabled ?? DEFAULT_PROFILE.pan.webEnabled),
      adminUsername: String(rawProfile?.services?.panWebclient?.adminUsername || rawProfile?.services?.zenmindAppServer?.adminUsername || DEFAULT_PROFILE.pan.adminUsername).trim() || DEFAULT_PROFILE.pan.adminUsername,
      frontendPort: rawProfile?.services?.panWebclient?.frontendPort ?? DEFAULT_PROFILE.pan.frontendPort,
      webPasswordBcrypt: getBcryptValue(rawProfile?.services?.panWebclient?.webPassword),
      webSessionSecret: String(rawProfile?.services?.panWebclient?.webSessionSecret || "")
    },
    term: {
      enabled: Boolean(rawProfile?.services?.termWebclient?.enabled ?? DEFAULT_PROFILE.term.enabled),
      webEnabled: Boolean(rawProfile?.access?.termWebEnabled ?? DEFAULT_PROFILE.term.webEnabled),
      authUsername: String(rawProfile?.services?.termWebclient?.authUsername || rawProfile?.services?.zenmindAppServer?.adminUsername || DEFAULT_PROFILE.term.authUsername).trim() || DEFAULT_PROFILE.term.authUsername,
      frontendPort: rawProfile?.services?.termWebclient?.frontendPort ?? DEFAULT_PROFILE.term.frontendPort,
      webPasswordBcrypt: getBcryptValue(rawProfile?.services?.termWebclient?.webPassword)
    },
    llm: {
      primaryProviderKey: String(rawProfile?.llm?.primaryProviderKey || "").trim(),
      primaryModelKey: String(rawProfile?.llm?.primaryModelKey || "").trim(),
      primaryApiKey: String(rawProfile?.llm?.primaryApiKey || "")
    },
    mcp: {
      enabled: legacyMcpEnabled || rawProfile?.mcp?.enabled === true || (
        rawProfile?.services?.mcpServerImagine === undefined &&
        rawProfile?.services?.mcpServerBash === undefined &&
        rawProfile?.services?.mcpServerMock === undefined &&
        rawProfile?.services?.mcpServerEmail === undefined &&
        DEFAULT_PROFILE.mcp.enabled
      )
    },
    __legacySecrets: {
      adminWebPassword: captureLegacySecret(rawProfile?.services?.zenmindAppServer?.adminPassword),
      adminAppMasterPassword: captureLegacySecret(rawProfile?.services?.zenmindAppServer?.appMasterPassword),
      panWebPassword: captureLegacySecret(rawProfile?.services?.panWebclient?.webPassword),
      termWebPassword: captureLegacySecret(rawProfile?.services?.termWebclient?.webPassword)
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
    images: {
      registry: normalized.images.registry,
      tag: normalized.images.tag
    },
    cloudflared: {
      tunnelUuid: normalized.cloudflared.tunnelUuid
    },
    gateway: {
      listenPort: normalized.gateway.listenPort
    },
    agentPlatformRunner: {
      enabled: normalized.agentPlatformRunner.enabled,
      hostPort: normalized.agentPlatformRunner.hostPort,
      baseUrl: derivePublicRunnerBaseUrl(normalized.agentPlatformRunner.hostPort)
    },
    containerHub: {
      enabled: normalized.containerHub.enabled,
      port: normalized.containerHub.port,
      authToken: normalized.containerHub.authToken
    },
    admin: {
      enabled: normalized.admin.enabled,
      webEnabled: normalized.admin.webEnabled,
      adminUsername: normalized.admin.adminUsername,
      frontendPort: normalized.admin.frontendPort,
      webPasswordBcrypt: normalized.admin.webPasswordBcrypt,
      appMasterPasswordBcrypt: normalized.admin.appMasterPasswordBcrypt
    },
    pan: {
      enabled: normalized.pan.enabled,
      webEnabled: normalized.pan.webEnabled,
      adminUsername: normalized.pan.adminUsername,
      frontendPort: normalized.pan.frontendPort,
      webPasswordBcrypt: normalized.pan.webPasswordBcrypt,
      webSessionSecret: normalized.pan.webSessionSecret
    },
    term: {
      enabled: normalized.term.enabled,
      webEnabled: normalized.term.webEnabled,
      authUsername: normalized.term.authUsername,
      frontendPort: normalized.term.frontendPort,
      webPasswordBcrypt: normalized.term.webPasswordBcrypt
    },
    llm: {
      primaryProviderKey: normalized.llm.primaryProviderKey,
      primaryModelKey: normalized.llm.primaryModelKey,
      primaryApiKey: normalized.llm.primaryApiKey
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
  const legacySecrets = normalized.__legacySecrets || {};

  detailed.website.domain = normalized.website.domain;
  detailed.website.publicOrigin = websiteOrigin;
  detailed.images.registry = normalized.images.registry;
  detailed.images.tag = normalized.images.tag;
  detailed.gateway.listenPort = normalized.gateway.listenPort;
  detailed.cloudflared.hostname = normalized.website.domain;
  detailed.cloudflared.tunnelUuid = normalized.cloudflared.tunnelUuid;
  detailed.agentPlatformRunner.enabled = normalized.agentPlatformRunner.enabled;
  detailed.agentPlatformRunner.hostPort = normalized.agentPlatformRunner.hostPort;
  detailed.agentPlatformRunner.publicBaseUrl = derivePublicRunnerBaseUrl(normalized.agentPlatformRunner.hostPort);
  detailed.agentPlatformRunner.baseUrl = normalized.agentPlatformRunner.enabled
    ? deriveContainerRunnerBaseUrl()
    : detailed.agentPlatformRunner.publicBaseUrl;
  detailed.containerHub.enabled = normalized.containerHub.enabled;
  detailed.containerHub.port = normalized.containerHub.port;
  detailed.containerHub.authToken = normalized.containerHub.authToken;
  detailed.containerHub.bindAddr = `127.0.0.1:${normalized.containerHub.port}`;
  detailed.services.agentPlatformRunner.enabled = normalized.agentPlatformRunner.enabled;
  detailed.services.agentPlatformRunner.hostPort = normalized.agentPlatformRunner.hostPort;
  detailed.services.agentPlatformRunner.baseUrl = detailed.agentPlatformRunner.baseUrl;
  detailed.services.agentPlatformRunner.publicBaseUrl = detailed.agentPlatformRunner.publicBaseUrl;
  detailed.services.containerHub.enabled = normalized.containerHub.enabled;
  detailed.services.containerHub.port = normalized.containerHub.port;
  detailed.services.containerHub.authToken = normalized.containerHub.authToken;
  detailed.services.containerHub.bindAddr = detailed.containerHub.bindAddr;

  detailed.access.adminPublicEnabled = normalized.admin.enabled ? normalized.admin.webEnabled : false;
  detailed.access.panWebEnabled = normalized.pan.enabled ? normalized.pan.webEnabled : false;
  detailed.access.panAppEnabled = normalized.pan.enabled;
  detailed.access.termWebEnabled = normalized.term.enabled ? normalized.term.webEnabled : false;
  detailed.access.termAppEnabled = normalized.term.enabled;

  detailed.services.zenmindAppServer.enabled = normalized.admin.enabled;
  detailed.services.zenmindAppServer.frontendPort = normalized.admin.frontendPort;
  detailed.services.zenmindAppServer.issuer = websiteOrigin;
  detailed.services.zenmindAppServer.adminUsername = normalized.admin.adminUsername;
  detailed.services.zenmindAppServer.adminPassword = normalized.admin.webPasswordBcrypt || legacySecrets.adminWebPassword || "";
  detailed.services.zenmindAppServer.appMasterPassword = normalized.admin.appMasterPasswordBcrypt || legacySecrets.adminAppMasterPassword || "";

  detailed.services.voiceServer.runnerBaseUrl = detailed.agentPlatformRunner.baseUrl;

  detailed.services.panWebclient.enabled = normalized.pan.enabled;
  detailed.services.panWebclient.frontendPort = normalized.pan.frontendPort;
  detailed.services.panWebclient.adminUsername = normalized.pan.adminUsername;
  detailed.services.panWebclient.webPassword = normalized.pan.webPasswordBcrypt || legacySecrets.panWebPassword || "";
  detailed.services.panWebclient.webSessionSecret = normalized.pan.webSessionSecret;
  detailed.services.panWebclient.jwtPublicKeyPem = managedPublicKey;
  detailed.services.panWebclient.mounts = [];

  detailed.services.termWebclient.enabled = normalized.term.enabled;
  detailed.services.termWebclient.frontendPort = normalized.term.frontendPort;
  detailed.services.termWebclient.authUsername = normalized.term.authUsername;
  detailed.services.termWebclient.webPassword = normalized.term.webPasswordBcrypt || legacySecrets.termWebPassword || "";
  detailed.services.termWebclient.appAuthIssuer = websiteOrigin;
  detailed.services.termWebclient.jwtPublicKeyPem = managedPublicKey;
  detailed.services.termWebclient.copilotRunnerBaseUrl = detailed.agentPlatformRunner.baseUrl;
  detailed.services.termWebclient.mounts = [];
  detailed.services.termWebclient.agentsYaml = "";
  detailed.services.termWebclient.assistYaml = "";
  detailed.services.termWebclient.assistApiKey = "";

  for (const serviceKey of ["mcpServerImagine", "mcpServerMock"]) {
    detailed.services[serviceKey].enabled = normalized.mcp.enabled;
    detailed.services[serviceKey].hostPortEnabled = normalized.mcp.enabled && detailed.services[serviceKey].hostPortEnabled;
  }

  detailed.__groups = {
    mcpEnabled: normalized.mcp.enabled,
    containerHubEnabled: normalized.containerHub.enabled,
    runnerEnabled: normalized.agentPlatformRunner.enabled
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
  assert(typeof normalized.images?.registry === "string" && normalized.images.registry.trim(), "images.registry is required");
  assert(typeof normalized.images?.tag === "string" && normalized.images.tag.trim(), "images.tag is required");
  assert(typeof normalized.agentPlatformRunner?.baseUrl === "string" && normalized.agentPlatformRunner.baseUrl.trim(), "agentPlatformRunner.baseUrl is required");
  assert(typeof normalized.admin?.adminUsername === "string" && normalized.admin.adminUsername.trim(), "admin.adminUsername is required");
  assert(typeof normalized.pan?.adminUsername === "string" && normalized.pan.adminUsername.trim(), "pan.adminUsername is required");
  assert(typeof normalized.term?.authUsername === "string" && normalized.term.authUsername.trim(), "term.authUsername is required");
  ensurePort(normalized.gateway.listenPort, "gateway.listenPort");
  ensurePort(normalized.agentPlatformRunner.hostPort, "agentPlatformRunner.hostPort");
  ensurePort(normalized.containerHub.port, "containerHub.port");
  ensurePort(normalized.admin.frontendPort, "admin.frontendPort");
  ensurePort(normalized.pan.frontendPort, "pan.frontendPort");
  ensurePort(normalized.term.frontendPort, "term.frontendPort");
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
  const direct = getBcryptValue(secret);
  if (direct) {
    return direct;
  }
  const plain = secret && typeof secret === "object" ? String(secret.plain || "").trim() : "";
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
    case "mcp-server-imagine":
      return profile.services.mcpServerImagine.enabled;
    case "mcp-server-mock":
      return profile.services.mcpServerMock.enabled;
    case "agent-platform-runner":
      return profile.services.agentPlatformRunner.enabled;
    case "agent-container-hub":
      return profile.services.containerHub.enabled;
    default:
      return false;
  }
}

function renderComposeEnv(profile) {
  const imageRefs = buildManagedImageRefs(profile);
  return renderEnv([
    commentHeader("Root docker compose variables").trimEnd(),
    `PUBLIC_ORIGIN=${profile.website.publicOrigin}`,
    `IMAGE_REGISTRY=${quoteEnv(profile.images.registry)}`,
    `IMAGE_TAG=${quoteEnv(profile.images.tag)}`,
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
    `AGENT_PLATFORM_RUNNER_ENABLED=${profile.services.agentPlatformRunner.enabled ? "true" : "false"}`,
    `AGENT_PLATFORM_RUNNER_HOST_PORT=${profile.services.agentPlatformRunner.hostPort}`,
    `CONTAINER_HUB_ENABLED=${profile.services.containerHub.enabled ? "true" : "false"}`,
    `CONTAINER_HUB_PORT=${profile.services.containerHub.port}`,
    `MCP_IMAGINE_HOST_PORT=${profile.services.mcpServerImagine.hostPort}`,
    `MCP_MOCK_HOST_PORT=${profile.services.mcpServerMock.hostPort}`,
    `APP_SERVER_VITE_BASE_PATH=${profile.services.zenmindAppServer.viteBasePath}`,
    `MCP_IMAGINE_RUNNER_DATA_ROOT=${profile.services.mcpServerImagine.runnerDataRoot}`,
    `ZENMIND_APP_SERVER_BACKEND_IMAGE=${quoteEnv(imageRefs["zenmind-app-server-backend"])}`,
    `ZENMIND_APP_SERVER_FRONTEND_IMAGE=${quoteEnv(imageRefs["zenmind-app-server-frontend"])}`,
    `ZENMIND_VOICE_SERVER_IMAGE=${quoteEnv(imageRefs["zenmind-voice-server"])}`,
    `PAN_WEBCLIENT_API_IMAGE=${quoteEnv(imageRefs["pan-webclient-api"])}`,
    `PAN_WEBCLIENT_FRONTEND_IMAGE=${quoteEnv(imageRefs["pan-webclient-frontend"])}`,
    `TERM_WEBCLIENT_BACKEND_IMAGE=${quoteEnv(imageRefs["term-webclient-backend"])}`,
    `TERM_WEBCLIENT_FRONTEND_IMAGE=${quoteEnv(imageRefs["term-webclient-frontend"])}`,
    `AGENT_PLATFORM_RUNNER_IMAGE=${quoteEnv(imageRefs["agent-platform-runner"])}`,
    `MCP_SERVER_IMAGINE_IMAGE=${quoteEnv(imageRefs["mcp-server-imagine"])}`,
    `MCP_SERVER_MOCK_IMAGE=${quoteEnv(imageRefs["mcp-server-mock"])}`
  ]);
}

function buildManagedImageRefs(profile) {
  const registry = String(profile.images.registry || "").replace(/\/+$/, "");
  const tag = String(profile.images.tag || "").trim();
  return {
    "zenmind-app-server-backend": `${registry}/zenmind-app-server-backend:${tag}`,
    "zenmind-app-server-frontend": `${registry}/zenmind-app-server-frontend:${tag}`,
    "zenmind-voice-server": `${registry}/zenmind-voice-server:${tag}`,
    "pan-webclient-api": `${registry}/pan-webclient-api:${tag}`,
    "pan-webclient-frontend": `${registry}/pan-webclient-frontend:${tag}`,
    "term-webclient-backend": `${registry}/term-webclient-backend:${tag}`,
    "term-webclient-frontend": `${registry}/term-webclient-frontend:${tag}`,
    "agent-platform-runner": `${registry}/agent-platform-runner:${tag}`,
    "mcp-server-imagine": `${registry}/mcp-server-imagine:${tag}`,
    "mcp-server-mock": `${registry}/mcp-server-mock:${tag}`
  };
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
  addPortBlock("mcp-server-mock", "MCP_MOCK_HOST_PORT", profile.services.mcpServerMock.hostPortEnabled);
  return `${lines.join("\n")}\n`;
}

function renderStartupConfig(profile) {
  const enabled = FIXED_STARTUP_PRODUCTS.filter((product) => serviceEnabled(profile, product));
  const lines = enabled.map((product) => `${product}  # runtime=${PRODUCT_RUNTIME_TYPES[product] || "image"}`);
  return `${commentHeader("One product per line. Order defines startup sequence.")}${lines.join("\n")}\n`;
}

function renderGatewayNginx(profile) {
  const runnerRoute = profile.__groups?.runnerEnabled
    ? [
        "        location ^~ /api/ap/ {",
        "            proxy_buffering off;",
        "            proxy_cache off;",
        "            proxy_read_timeout 3600s;",
        "            proxy_send_timeout 3600s;",
        "            add_header X-Accel-Buffering no;",
        "            proxy_pass http://agent_platform_runner;",
        "        }"
      ]
    : [
        "        location ^~ /api/ap/ {",
        "            return 404;",
        "        }"
      ];
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
        "        location = /api/mcp/imagine { proxy_pass http://mcp_server_imagine/mcp; }"
      ]
    : [
        "        location = /api/mcp/mock { return 404; }",
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
    "    upstream agent_platform_runner { server agent-platform-runner:8080; }",
    "    upstream mcp_server_mock { server mcp-server-mock:8080; }",
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
    ...runnerRoute,
    "",
    ...mcpRoutes,
    "",
    ...panWebGate,
    ...panAppGate,
    ...termWebGate,
    ...termAppGate,
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

function renderRunnerEnv(profile) {
  const service = profile.services.agentPlatformRunner;
  return renderEnv([
    commentHeader("agent-platform-runner deployment contract").trimEnd(),
    `HOST_PORT=${service.hostPort}`,
    `AGENT_AUTH_ENABLED=${service.authEnabled ? "true" : "false"}`,
    `CHAT_IMAGE_TOKEN_SECRET=${quoteEnv(service.chatImageTokenSecret)}`,
    `AGENTS_DIR=${quoteEnv(service.dirs.agents)}`,
    `TEAMS_DIR=${quoteEnv(service.dirs.teams)}`,
    `MODELS_DIR=${quoteEnv(service.dirs.models)}`,
    `PROVIDERS_DIR=${quoteEnv(service.dirs.providers)}`,
    `TOOLS_DIR=${quoteEnv(service.dirs.tools)}`,
    `MCP_SERVERS_DIR=${quoteEnv(service.dirs.mcpServers)}`,
    `VIEWPORT_SERVERS_DIR=${quoteEnv(service.dirs.viewportServers)}`,
    `VIEWPORTS_DIR=${quoteEnv(service.dirs.viewports)}`,
    `SKILLS_MARKET_DIR=${quoteEnv(service.dirs.skillsMarket)}`,
    `SCHEDULES_DIR=${quoteEnv(service.dirs.schedules)}`,
    `CHATS_DIR=${quoteEnv(service.dirs.chats)}`,
    `ROOT_DIR=${quoteEnv(service.dirs.root)}`,
    `PAN_DIR=${quoteEnv(service.dirs.pan)}`
  ]);
}

function renderRunnerContainerHubConfig(profile) {
  return `${[
    `enabled: ${profile.services.containerHub.enabled ? "true" : "false"}`,
    `base-url: http://host.docker.internal:${profile.services.containerHub.port}`,
    `auth-token: ${JSON.stringify(profile.services.containerHub.authToken || "")}`,
    "default-environment-id:",
    "request-timeout-ms: 60000",
    "default-sandbox-level: run",
    "agent-idle-timeout-ms: 600000",
    "destroy-queue-delay-ms: 5000"
  ].join("\n")}\n`;
}

function renderContainerHubEnv(profile) {
  const service = profile.services.containerHub;
  return renderEnv([
    commentHeader("agent-container-hub deployment contract").trimEnd(),
    `BIND_ADDR=${quoteEnv(service.bindAddr)}`,
    `AUTH_TOKEN=${quoteEnv(service.authToken)}`,
    `CONFIG_ROOT=${quoteEnv(service.configRoot)}`,
    `ROOTFS_ROOT=${quoteEnv(service.rootfsRoot)}`,
    `BUILD_ROOT=${quoteEnv(service.buildRoot)}`,
    `SESSION_MOUNT_TEMPLATE_ROOT=${quoteEnv(service.sessionMountTemplateRoot)}`
  ]);
}

function repoPath(reposRoot, name, ...segments) {
  return path.join(reposRoot, name, ...segments);
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function ensureReleaseEnvFile(serviceDir) {
  const envPath = path.join(serviceDir, ".env");
  if (fs.existsSync(envPath)) {
    return envPath;
  }

  const examplePath = path.join(serviceDir, ".env.example");
  ensureDir(serviceDir);
  if (fs.existsSync(examplePath)) {
    fs.copyFileSync(examplePath, envPath);
  } else {
    fs.writeFileSync(envPath, "", "utf8");
  }
  return envPath;
}

function updateEnvContent(content, updates) {
  const lines = String(content || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  const result = [];
  const seen = new Set();

  for (const rawLine of lines) {
    const line = rawLine ?? "";
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      result.push(line);
      continue;
    }
    const key = match[1];
    if (!Object.prototype.hasOwnProperty.call(updates, key)) {
      result.push(line);
      continue;
    }
    result.push(`${key}=${updates[key]}`);
    seen.add(key);
  }

  for (const [key, value] of Object.entries(updates)) {
    if (!seen.has(key)) {
      result.push(`${key}=${value}`);
    }
  }

  const normalized = result.join("\n").replace(/\n+$/, "");
  return `${normalized}\n`;
}

function collectReleaseWrites(profile, versionDir, workspaceRoot, bcryptScriptPath) {
  const reposRoot = path.resolve(workspaceRoot, "..");
  const detailed = expandProfile(profile, reposRoot);
  const releaseIssuer = deriveReleaseIssuer(detailed.website.domain, detailed.gateway.listenPort);
  detailed.services.zenmindAppServer.issuer = releaseIssuer;
  detailed.services.termWebclient.appAuthIssuer = releaseIssuer;

  const deployDir = path.join(versionDir, "deploy");
  const writes = [];

  const appServerDir = path.join(deployDir, "zenmind-app-server");
  const appServerEnvPath = ensureReleaseEnvFile(appServerDir);
  writes.push({
    path: appServerEnvPath,
    content: updateEnvContent(fs.readFileSync(appServerEnvPath, "utf8"), {
      FRONTEND_PORT: String(detailed.services.zenmindAppServer.frontendPort),
      AUTH_ISSUER: quoteEnv(releaseIssuer),
      AUTH_ADMIN_USERNAME: quoteEnv(detailed.services.zenmindAppServer.adminUsername),
      AUTH_ADMIN_PASSWORD_BCRYPT: quoteEnv(resolveSecretHash(detailed.services.zenmindAppServer.adminPassword, bcryptScriptPath)),
      AUTH_APP_MASTER_PASSWORD_BCRYPT: quoteEnv(resolveSecretHash(detailed.services.zenmindAppServer.appMasterPassword, bcryptScriptPath))
    })
  });

  const panDir = path.join(deployDir, "pan-webclient");
  const panEnvPath = ensureReleaseEnvFile(panDir);
  writes.push({
    path: panEnvPath,
    content: updateEnvContent(fs.readFileSync(panEnvPath, "utf8"), {
      NGINX_PORT: String(detailed.services.panWebclient.frontendPort),
      PAN_ADMIN_USERNAME: quoteEnv(detailed.services.panWebclient.adminUsername),
      AUTH_PASSWORD_HASH_BCRYPT: quoteEnv(resolveSecretHash(detailed.services.panWebclient.webPassword, bcryptScriptPath)),
      WEB_SESSION_SECRET: quoteEnv(detailed.services.panWebclient.webSessionSecret)
    })
  });

  const termDir = path.join(deployDir, "term-webclient");
  const termEnvPath = ensureReleaseEnvFile(termDir);
  writes.push({
    path: termEnvPath,
    content: updateEnvContent(fs.readFileSync(termEnvPath, "utf8"), {
      FRONTEND_PORT: String(detailed.services.termWebclient.frontendPort),
      AUTH_USERNAME: quoteEnv(detailed.services.termWebclient.authUsername),
      AUTH_PASSWORD_HASH_BCRYPT: quoteEnv(resolveSecretHash(detailed.services.termWebclient.webPassword, bcryptScriptPath)),
      APP_AUTH_ISSUER: quoteEnv(releaseIssuer)
    })
  });

  const gatewayDir = path.join(deployDir, "zenmind-gateway");
  const gatewayEnvPath = ensureReleaseEnvFile(gatewayDir);
  writes.push({
    path: gatewayEnvPath,
    content: updateEnvContent(fs.readFileSync(gatewayEnvPath, "utf8"), {
      GATEWAY_PORT: String(detailed.gateway.listenPort)
    })
  });

  const runnerDir = path.join(deployDir, "agent-platform-runner");
  const runnerEnvPath = ensureReleaseEnvFile(runnerDir);
  writes.push({
    path: runnerEnvPath,
    content: updateEnvContent(fs.readFileSync(runnerEnvPath, "utf8"), {
      HOST_PORT: String(detailed.services.agentPlatformRunner.hostPort),
      AGENT_AUTH_ISSUER: quoteEnv(releaseIssuer)
    })
  });
  writes.push({
    path: path.join(runnerDir, "configs", "container-hub.yml"),
    content: renderRunnerContainerHubConfig(detailed)
  });

  const containerHubDir = path.join(deployDir, "agent-container-hub");
  const containerHubEnvPath = ensureReleaseEnvFile(containerHubDir);
  writes.push({
    path: containerHubEnvPath,
    content: updateEnvContent(fs.readFileSync(containerHubEnvPath, "utf8"), {
      BIND_ADDR: quoteEnv(detailed.services.containerHub.bindAddr),
      AUTH_TOKEN: quoteEnv(detailed.services.containerHub.authToken)
    })
  });

  const agentWebclientDir = path.join(deployDir, "agent-webclient");
  const agentWebclientEnvPath = ensureReleaseEnvFile(agentWebclientDir);
  writes.push({
    path: agentWebclientEnvPath,
    content: updateEnvContent(fs.readFileSync(agentWebclientEnvPath, "utf8"), {
      BASE_URL: quoteEnv(`http://host.docker.internal:${detailed.services.agentPlatformRunner.hostPort}`),
      VOICE_BASE_URL: quoteEnv(`http://host.docker.internal:${detailed.services.voiceServer.port}`)
    })
  });

  const agentWeixinBridgeDir = path.join(deployDir, "agent-weixin-bridge");
  const agentWeixinBridgeEnvPath = path.join(agentWeixinBridgeDir, ".env");
  const agentWeixinBridgeEnvExisted = fs.existsSync(agentWeixinBridgeEnvPath);
  ensureReleaseEnvFile(agentWeixinBridgeDir);
  writes.push({
    path: agentWeixinBridgeEnvPath,
    content: updateEnvContent(
      fs.readFileSync(agentWeixinBridgeEnvPath, "utf8"),
      agentWeixinBridgeEnvExisted
        ? {}
        : {
            RUNNER_BASE_URL: quoteEnv("http://agent-platform-runner:8080")
          }
    )
  });

  return {
    writes,
    meta: {
      releaseIssuer,
      enabled: {
        admin: Boolean(profile.admin?.enabled ?? true),
        pan: Boolean(profile.pan?.enabled ?? true),
        term: Boolean(profile.term?.enabled ?? true),
        mcp: Boolean(profile.mcp?.enabled ?? true),
        runner: Boolean(profile.agentPlatformRunner?.enabled ?? true),
        containerHub: Boolean(profile.containerHub?.enabled ?? false)
      }
    }
  };
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
  siblingWrites.push({ path: repoPath(reposRoot, "agent-platform-runner", ".env"), content: renderRunnerEnv(detailed) });
  siblingWrites.push({ path: repoPath(reposRoot, "agent-platform-runner", "configs", "container-hub.yml"), content: renderRunnerContainerHubConfig(detailed) });
  siblingWrites.push({ path: repoPath(reposRoot, "agent-container-hub", ".env"), content: renderContainerHubEnv(detailed) });

  if (normalized.mcp.enabled) {
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-imagine", ".env"), content: renderImagineEnv(detailed) });
    siblingWrites.push({ path: repoPath(reposRoot, "mcp-server-mock", ".env"), content: renderMockEnv(detailed) });
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

export function applyToRelease({ profile, workspaceRoot, versionDir, bcryptScriptPath, dryRun = false }) {
  const normalized = normalizeProfile(profile);
  const { writes, meta } = collectReleaseWrites(normalized, versionDir, workspaceRoot, bcryptScriptPath);

  if (!dryRun) {
    for (const write of writes) {
      ensureDir(path.dirname(write.path));
      fs.writeFileSync(write.path, write.content, "utf8");
    }
  }

  return { writes, meta, extraSteps: [] };
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
