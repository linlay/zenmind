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
    webEnabled: true,
    frontendPort: 11950,
    webPasswordBcrypt: "",
    appMasterPasswordBcrypt: ""
  },
  pan: {
    enabled: true,
    webEnabled: true,
    frontendPort: 11946,
    webPasswordBcrypt: "",
    webSessionSecret: ""
  },
  term: {
    enabled: true,
    webEnabled: true,
    frontendPort: 11947,
    webPasswordBcrypt: ""
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

const PROJECTS = {
  admin: { path: "admin.enabled", label: "管理端" },
  pan: { path: "pan.enabled", label: "网盘" },
  term: { path: "term.enabled", label: "终端" },
  miniApp: { path: "miniApp.enabled", label: "小应用" },
  sandboxes: { path: "sandboxes.enabled", label: "沙箱" },
  mcp: { path: "mcp.enabled", label: "MCP 服务" }
};

const BCRYPT_SALT_ROUNDS = 10;

const form = document.querySelector("#config-form");
const fileInput = document.querySelector("#file-input");
const fileStatus = document.querySelector("#file-status");
const dirtyStatus = document.querySelector("#dirty-status");
const metricOrigin = document.querySelector("#metric-origin");
const metricGateway = document.querySelector("#metric-gateway");
const metricGroups = document.querySelector("#metric-groups");
const copyDialog = document.querySelector("#copy-dialog");
const copyDialogTitle = document.querySelector("#copy-dialog-title");
const copyDialogDescription = document.querySelector("#copy-dialog-description");
const copySourceList = document.querySelector("#copy-source-list");
const copyCloseButton = document.querySelector("[data-copy-close]");
const namedFields = Array.from(form.querySelectorAll("[name]"));
const passwordFields = Array.from(form.querySelectorAll("[data-bcrypt-target]"));
const sensitiveFields = Array.from(form.querySelectorAll("[data-sensitive='true']"));
const navButtons = Array.from(document.querySelectorAll("[data-select-view]"));
const navToggles = Array.from(document.querySelectorAll("[data-project-toggle]"));
const viewPanels = Array.from(document.querySelectorAll(".view-panel"));
const advancedButtons = Array.from(document.querySelectorAll("[data-advanced-toggle]"));
const hashStatusNodes = Array.from(document.querySelectorAll("[data-hash-status-for]"));

let state = normalizeProfile(DEFAULT_PROFILE);
let plainPasswordState = {};
let fileHandle = null;
let dirty = false;
let selectedView = "global";
let copyTargetPath = null;
let copyDialogFallbackOpen = false;
const expandedAdvanced = new Set();

function clone(value) {
  return JSON.parse(JSON.stringify(value));
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

function normalizeBcrypt(hash) {
  const trimmed = String(hash || "").trim().replace(/^['"]|['"]$/g, "");
  if (trimmed.startsWith("$2b$")) {
    return `$2y$${trimmed.slice(4)}`;
  }
  return trimmed;
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

function getImportedBcryptValue(secret) {
  const direct = getBcryptValue(secret);
  if (direct) {
    return direct;
  }
  if (secret && typeof secret === "object") {
    return computeBcrypt(String(secret.plain || ""));
  }
  return "";
}

function normalizeProfile(rawProfile) {
  if (rawProfile?.profileVersion === 2) {
    return {
      profileVersion: 2,
      website: {
        domain: stripProtocol(rawProfile?.website?.domain || DEFAULT_PROFILE.website.domain).toLowerCase()
      },
      cloudflared: {
        tunnelUuid: String(rawProfile?.cloudflared?.tunnelUuid || DEFAULT_PROFILE.cloudflared.tunnelUuid)
      },
      gateway: {
        listenPort: rawProfile?.gateway?.listenPort ?? DEFAULT_PROFILE.gateway.listenPort
      },
      agentPlatformRunner: {
        baseUrl: String(rawProfile?.agentPlatformRunner?.baseUrl || DEFAULT_PROFILE.agentPlatformRunner.baseUrl)
      },
      admin: {
        enabled: Boolean(rawProfile?.admin?.enabled ?? DEFAULT_PROFILE.admin.enabled),
        webEnabled: Boolean(rawProfile?.admin?.webEnabled ?? rawProfile?.admin?.publicEnabled ?? DEFAULT_PROFILE.admin.webEnabled),
        frontendPort: rawProfile?.admin?.frontendPort ?? DEFAULT_PROFILE.admin.frontendPort,
        webPasswordBcrypt: getImportedBcryptValue(rawProfile?.admin?.webPasswordBcrypt || rawProfile?.admin?.adminPassword),
        appMasterPasswordBcrypt: getImportedBcryptValue(rawProfile?.admin?.appMasterPasswordBcrypt || rawProfile?.admin?.appMasterPassword)
      },
      pan: {
        enabled: Boolean(rawProfile?.pan?.enabled ?? DEFAULT_PROFILE.pan.enabled),
        webEnabled: Boolean(rawProfile?.pan?.webEnabled ?? DEFAULT_PROFILE.pan.webEnabled),
        frontendPort: rawProfile?.pan?.frontendPort ?? DEFAULT_PROFILE.pan.frontendPort,
        webPasswordBcrypt: getImportedBcryptValue(rawProfile?.pan?.webPasswordBcrypt || rawProfile?.pan?.webPassword),
        webSessionSecret: String(rawProfile?.pan?.webSessionSecret || "")
      },
      term: {
        enabled: Boolean(rawProfile?.term?.enabled ?? DEFAULT_PROFILE.term.enabled),
        webEnabled: Boolean(rawProfile?.term?.webEnabled ?? DEFAULT_PROFILE.term.webEnabled),
        frontendPort: rawProfile?.term?.frontendPort ?? DEFAULT_PROFILE.term.frontendPort,
        webPasswordBcrypt: getImportedBcryptValue(rawProfile?.term?.webPasswordBcrypt || rawProfile?.term?.webPassword)
      },
      miniApp: {
        enabled: Boolean(rawProfile?.miniApp?.enabled ?? DEFAULT_PROFILE.miniApp.enabled),
        defaultAppMode: String(rawProfile?.miniApp?.defaultAppMode || DEFAULT_PROFILE.miniApp.defaultAppMode),
        publicBase: String(rawProfile?.miniApp?.publicBase || DEFAULT_PROFILE.miniApp.publicBase),
        port: rawProfile?.miniApp?.port ?? DEFAULT_PROFILE.miniApp.port
      },
      sandboxes: {
        enabled: Boolean(rawProfile?.sandboxes?.enabled ?? DEFAULT_PROFILE.sandboxes.enabled)
      },
      mcp: {
        enabled: Boolean(rawProfile?.mcp?.enabled ?? DEFAULT_PROFILE.mcp.enabled)
      }
    };
  }

  const legacyMcpEnabled = [
    rawProfile?.services?.mcpServerImagine?.enabled,
    rawProfile?.services?.mcpServerBash?.enabled,
    rawProfile?.services?.mcpServerMock?.enabled,
    rawProfile?.services?.mcpServerEmail?.enabled
  ].some((value) => value === true);

  return {
    profileVersion: 2,
    website: {
      domain: stripProtocol(rawProfile?.website?.domain || rawProfile?.website?.publicOrigin || rawProfile?.cloudflared?.hostname || DEFAULT_PROFILE.website.domain).toLowerCase()
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
      webEnabled: Boolean(rawProfile?.access?.adminPublicEnabled ?? DEFAULT_PROFILE.admin.webEnabled),
      frontendPort: rawProfile?.services?.zenmindAppServer?.frontendPort ?? DEFAULT_PROFILE.admin.frontendPort,
      webPasswordBcrypt: getImportedBcryptValue(rawProfile?.services?.zenmindAppServer?.adminPassword),
      appMasterPasswordBcrypt: getImportedBcryptValue(rawProfile?.services?.zenmindAppServer?.appMasterPassword)
    },
    pan: {
      enabled: Boolean(rawProfile?.services?.panWebclient?.enabled ?? DEFAULT_PROFILE.pan.enabled),
      webEnabled: Boolean(rawProfile?.access?.panWebEnabled ?? DEFAULT_PROFILE.pan.webEnabled),
      frontendPort: rawProfile?.services?.panWebclient?.frontendPort ?? DEFAULT_PROFILE.pan.frontendPort,
      webPasswordBcrypt: getImportedBcryptValue(rawProfile?.services?.panWebclient?.webPassword),
      webSessionSecret: String(rawProfile?.services?.panWebclient?.webSessionSecret || "")
    },
    term: {
      enabled: Boolean(rawProfile?.services?.termWebclient?.enabled ?? DEFAULT_PROFILE.term.enabled),
      webEnabled: Boolean(rawProfile?.access?.termWebEnabled ?? DEFAULT_PROFILE.term.webEnabled),
      frontendPort: rawProfile?.services?.termWebclient?.frontendPort ?? DEFAULT_PROFILE.term.frontendPort,
      webPasswordBcrypt: getImportedBcryptValue(rawProfile?.services?.termWebclient?.webPassword)
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
      enabled: legacyMcpEnabled || rawProfile?.mcp?.enabled === true || DEFAULT_PROFILE.mcp.enabled
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
      webEnabled: normalized.admin.webEnabled,
      frontendPort: normalized.admin.frontendPort,
      webPasswordBcrypt: normalized.admin.webPasswordBcrypt,
      appMasterPasswordBcrypt: normalized.admin.appMasterPasswordBcrypt
    },
    pan: {
      enabled: normalized.pan.enabled,
      webEnabled: normalized.pan.webEnabled,
      frontendPort: normalized.pan.frontendPort,
      webPasswordBcrypt: normalized.pan.webPasswordBcrypt,
      webSessionSecret: normalized.pan.webSessionSecret
    },
    term: {
      enabled: normalized.term.enabled,
      webEnabled: normalized.term.webEnabled,
      frontendPort: normalized.term.frontendPort,
      webPasswordBcrypt: normalized.term.webPasswordBcrypt
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

function setDeep(target, dottedPath, value) {
  const parts = dottedPath.split(".");
  let cursor = target;
  for (let index = 0; index < parts.length - 1; index += 1) {
    const part = parts[index];
    if (!cursor[part] || typeof cursor[part] !== "object") {
      cursor[part] = {};
    }
    cursor = cursor[part];
  }
  cursor[parts.at(-1)] = value;
}

function getDeep(target, dottedPath) {
  return dottedPath.split(".").reduce((acc, part) => acc?.[part], target);
}

function deriveOrigin(domain) {
  return domain ? `https://${domain}` : "-";
}

function getFieldElement(name) {
  return namedFields.find((element) => element.name === name) || null;
}

function getPasswordField(targetPath) {
  return passwordFields.find((element) => element.dataset.bcryptTarget === targetPath) || null;
}

function getSensitivePath(element) {
  return element.dataset.sensitivePath || element.dataset.bcryptTarget || element.name || "";
}

function getFieldLabel(path) {
  const field = sensitiveFields.find((element) => getSensitivePath(element) === path)
    || getFieldElement(path)
    || getPasswordField(path);
  return field?.closest("[data-field-label]")?.dataset.fieldLabel || path;
}

function renderFieldValue(element, value) {
  if (element.type === "checkbox") {
    element.checked = Boolean(value);
    return;
  }
  element.value = value ?? "";
}

function renderPasswordFields() {
  for (const field of passwordFields) {
    const targetPath = field.dataset.bcryptTarget;
    field.value = plainPasswordState[targetPath] || "";
  }
}

function renderHashStatuses() {
  for (const node of hashStatusNodes) {
    const targetPath = node.dataset.hashStatusFor;
    const hasHash = String(getDeep(state, targetPath) || "").trim().length > 0;
    node.textContent = hasHash ? "已生成 bcrypt，保存到 JSON 时不会写入明文。" : "输入明文后会立即转换成 bcrypt，JSON 只保存 hash。";
  }
}

function enabledGroups() {
  return Object.entries(PROJECTS)
    .filter(([, project]) => Boolean(getDeep(state, project.path)))
    .map(([, project]) => project.label);
}

function updateMetrics() {
  metricOrigin.textContent = deriveOrigin(state.website.domain);
  metricGateway.textContent = `127.0.0.1:${state.gateway.listenPort}`;
  metricGroups.textContent = enabledGroups().join(" / ") || "无";
  dirtyStatus.textContent = dirty ? "当前内容尚未保存" : "当前内容已保存";
}

function updateProjectNav() {
  for (const button of navButtons) {
    button.classList.toggle("is-active", button.dataset.selectView === selectedView);
  }
  for (const toggle of navToggles) {
    const projectKey = toggle.dataset.projectToggle;
    toggle.checked = Boolean(getDeep(state, PROJECTS[projectKey].path));
  }
}

function updatePanels() {
  for (const panel of viewPanels) {
    const projectKey = panel.dataset.projectPanel;
    if (!projectKey) {
      continue;
    }
    const enabled = Boolean(getDeep(state, PROJECTS[projectKey].path));
    const disabledState = panel.querySelector(`[data-disabled-state="${projectKey}"]`);
    const enabledBody = panel.querySelector(`[data-enabled-body="${projectKey}"]`);
    if (disabledState) {
      disabledState.hidden = enabled;
    }
    if (enabledBody) {
      enabledBody.hidden = !enabled;
    }
  }
}

function updateAdvancedSections() {
  for (const button of advancedButtons) {
    const key = button.dataset.advancedToggle;
    const open = expandedAdvanced.has(key);
    button.classList.toggle("is-open", open);
    button.textContent = open ? "收起高级" : "高级选项";
  }
  for (const section of document.querySelectorAll("[data-advanced-body]")) {
    section.hidden = !expandedAdvanced.has(section.dataset.advancedBody);
  }
}

function getVisibleSensitiveSources(targetPath) {
  return sensitiveFields.filter((field) => {
    const sourcePath = getSensitivePath(field);
    if (!sourcePath || sourcePath === targetPath) {
      return false;
    }
    return String(getDeep(state, sourcePath) || "").trim().length > 0;
  });
}

function updateCopyButtons() {
  for (const button of form.querySelectorAll(".copy-button")) {
    const targetPath = button.dataset.copyTarget;
    button.disabled = getVisibleSensitiveSources(targetPath).length === 0;
  }
}

function syncUi() {
  renderPasswordFields();
  renderHashStatuses();
  updateMetrics();
  updateProjectNav();
  updatePanels();
  updateAdvancedSections();
  updateCopyButtons();
}

function renderProfile(profile, { resetPlainPasswords = false } = {}) {
  state = normalizeProfile(profile);
  if (resetPlainPasswords) {
    plainPasswordState = {};
  }
  for (const element of namedFields) {
    renderFieldValue(element, getDeep(state, element.name));
  }
  syncUi();
}

function markDirty(nextDirty) {
  dirty = nextDirty;
  syncUi();
}

function normalizeFieldValue(input) {
  if (input.type === "checkbox") {
    return input.checked;
  }
  if (input.type === "number") {
    return input.value === "" ? "" : Number.parseInt(input.value, 10);
  }
  if (input.name === "website.domain") {
    return stripProtocol(input.value).toLowerCase();
  }
  return input.value;
}

function setSelectedView(view) {
  selectedView = view;
  updateProjectNav();
  const section = document.querySelector(`#section-${view}`);
  if (section) {
    section.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function generateSecret() {
  if (window.crypto?.getRandomValues) {
    const bytes = new Uint8Array(24);
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
  }
  return Array.from({ length: 48 }, () => Math.floor(Math.random() * 16).toString(16)).join("");
}

function setProjectEnabled(projectKey, enabled) {
  setDeep(state, PROJECTS[projectKey].path, enabled);

  if (projectKey === "pan" && enabled && !state.pan.webSessionSecret.trim()) {
    state.pan.webSessionSecret = generateSecret();
    const secretField = getFieldElement("pan.webSessionSecret");
    if (secretField) {
      renderFieldValue(secretField, state.pan.webSessionSecret);
    }
  }

  if (projectKey === "admin") {
    state.admin.webEnabled = enabled ? state.admin.webEnabled || true : false;
  }
  if (projectKey === "pan") {
    state.pan.webEnabled = enabled ? state.pan.webEnabled || true : false;
  }
  if (projectKey === "term") {
    state.term.webEnabled = enabled ? state.term.webEnabled || true : false;
  }

  renderProfile(state);
  markDirty(true);
}

function closeCopyDialog() {
  if (copyDialogFallbackOpen) {
    copyDialog.classList.remove("is-fallback-open");
    copyDialog.removeAttribute("open");
    copyDialogFallbackOpen = false;
  }
  copyTargetPath = null;
  copySourceList.replaceChildren();
}

function showCopyDialog() {
  if (typeof copyDialog.showModal === "function") {
    copyDialog.showModal();
    return;
  }
  copyDialog.setAttribute("open", "open");
  copyDialog.classList.add("is-fallback-open");
  copyDialogFallbackOpen = true;
}

function dismissCopyDialog() {
  if (typeof copyDialog.close === "function") {
    copyDialog.close();
    return;
  }
  closeCopyDialog();
}

function openCopyDialog(targetPath) {
  if (copyDialog.open || copyDialogFallbackOpen) {
    dismissCopyDialog();
  }
  copyTargetPath = targetPath;
  const sources = getVisibleSensitiveSources(targetPath);
  copyDialogTitle.textContent = `复制到 ${getFieldLabel(targetPath)}`;
  copyDialogDescription.textContent = sources.length > 0
    ? "选择当前页已生成的 bcrypt 或 secret，直接带入目标字段。密码输入框不会回显明文。"
    : "当前页还没有其他已填写的敏感字段。";
  copySourceList.replaceChildren();

  if (sources.length === 0) {
    const empty = document.createElement("p");
    empty.className = "copy-empty";
    empty.textContent = "没有可用来源。";
    copySourceList.append(empty);
  } else {
    for (const sourceField of sources) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "copy-source-button";
      button.dataset.sourcePath = getSensitivePath(sourceField);
      button.innerHTML = `<span>${getFieldLabel(getSensitivePath(sourceField))}</span><small>已填写</small>`;
      copySourceList.append(button);
    }
  }

  showCopyDialog();
}

function computeBcrypt(plainValue) {
  if (!plainValue || !plainValue.trim()) {
    return "";
  }
  if (typeof dcodeIO !== "undefined" && dcodeIO.bcrypt) {
    const salt = dcodeIO.bcrypt.genSaltSync(BCRYPT_SALT_ROUNDS);
    return dcodeIO.bcrypt.hashSync(plainValue, salt);
  }
  console.error("bcrypt.js is unavailable, cannot generate hash.");
  return "";
}

const sectionObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        const view = entry.target.dataset.view;
        if (view) {
          selectedView = view;
          updateProjectNav();
        }
      }
    }
  },
  { rootMargin: "-20% 0px -60% 0px", threshold: 0 }
);

for (const panel of viewPanels) {
  sectionObserver.observe(panel);
}

form.addEventListener("input", (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) {
    return;
  }

  if (target.dataset.bcryptTarget) {
    const bcryptPath = target.dataset.bcryptTarget;
    plainPasswordState[bcryptPath] = target.value;
    if (target.value.trim()) {
      const hash = computeBcrypt(target.value);
      if (hash) {
        setDeep(state, bcryptPath, hash);
        markDirty(true);
      } else {
        syncUi();
      }
    } else {
      syncUi();
    }
    return;
  }

  const value = normalizeFieldValue(target);
  setDeep(state, target.name, value);
  if (target.name === "website.domain") {
    target.value = value;
  }
  markDirty(true);
});

document.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  const viewButton = target.closest("[data-select-view]");
  if (viewButton) {
    setSelectedView(viewButton.dataset.selectView);
    return;
  }

  const advancedButton = target.closest("[data-advanced-toggle]");
  if (advancedButton) {
    const key = advancedButton.dataset.advancedToggle;
    if (expandedAdvanced.has(key)) {
      expandedAdvanced.delete(key);
    } else {
      expandedAdvanced.add(key);
    }
    syncUi();
    return;
  }

  const copyButton = target.closest(".copy-button");
  if (copyButton) {
    openCopyDialog(copyButton.dataset.copyTarget);
    return;
  }

  const sourceButton = target.closest(".copy-source-button");
  if (sourceButton && copyTargetPath) {
    const sourcePath = sourceButton.dataset.sourcePath;
    const value = getDeep(state, sourcePath);
    setDeep(state, copyTargetPath, value);
    plainPasswordState[copyTargetPath] = "";
    const namedField = getFieldElement(copyTargetPath);
    if (namedField) {
      renderFieldValue(namedField, value);
    }
    const passwordField = getPasswordField(copyTargetPath);
    if (passwordField) {
      passwordField.value = "";
    }
    markDirty(true);
    dismissCopyDialog();
    return;
  }

  if (target === copyDialog && copyDialogFallbackOpen) {
    dismissCopyDialog();
  }
});

for (const toggle of navToggles) {
  toggle.addEventListener("change", () => {
    setProjectEnabled(toggle.dataset.projectToggle, toggle.checked);
    const targetView = toggle.dataset.projectToggle === "miniApp" ? "mini-app" : toggle.dataset.projectToggle;
    setSelectedView(targetView);
  });
}

copyDialog.addEventListener("close", closeCopyDialog);
copyCloseButton.addEventListener("click", () => {
  dismissCopyDialog();
});

document.querySelector("#load-example").addEventListener("click", () => {
  renderProfile(DEFAULT_PROFILE, { resetPlainPasswords: true });
  fileHandle = null;
  fileStatus.textContent = "示例配置（未绑定文件）";
  markDirty(true);
});

document.querySelector("#import-json").addEventListener("click", () => {
  fileInput.click();
});

fileInput.addEventListener("change", async (event) => {
  const [file] = event.target.files || [];
  if (!file) {
    return;
  }
  const parsed = JSON.parse(await file.text());
  renderProfile(parsed, { resetPlainPasswords: true });
  fileHandle = null;
  fileStatus.textContent = `${file.name}（导入）`;
  markDirty(true);
  fileInput.value = "";
});

document.querySelector("#export-json").addEventListener("click", () => {
  const blob = new Blob([`${JSON.stringify(serializeProfile(state), null, 2)}\n`], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "zenmind.profile.local.json";
  anchor.click();
  URL.revokeObjectURL(url);
});

async function saveToHandle(handle) {
  const writable = await handle.createWritable();
  await writable.write(`${JSON.stringify(serializeProfile(state), null, 2)}\n`);
  await writable.close();
  fileHandle = handle;
  fileStatus.textContent = handle.name;
  markDirty(false);
}

document.querySelector("#open-file").addEventListener("click", async () => {
  if (window.showOpenFilePicker) {
    try {
      const [handle] = await window.showOpenFilePicker({
        types: [{ description: "JSON", accept: { "application/json": [".json"] } }]
      });
      if (!handle) {
        return;
      }
      const file = await handle.getFile();
      renderProfile(JSON.parse(await file.text()), { resetPlainPasswords: true });
      fileHandle = handle;
      fileStatus.textContent = handle.name;
      markDirty(false);
      return;
    } catch (error) {
      if (error?.name !== "AbortError") {
        console.error(error);
      }
      return;
    }
  }
  fileInput.click();
});

document.querySelector("#save-file").addEventListener("click", async () => {
  try {
    if (fileHandle) {
      await saveToHandle(fileHandle);
      return;
    }
    if (window.showSaveFilePicker) {
      const handle = await window.showSaveFilePicker({
        suggestedName: "zenmind.profile.local.json",
        types: [{ description: "JSON", accept: { "application/json": [".json"] } }]
      });
      await saveToHandle(handle);
      return;
    }
    document.querySelector("#export-json").click();
    markDirty(false);
  } catch (error) {
    if (error?.name !== "AbortError") {
      console.error(error);
    }
  }
});

renderProfile(DEFAULT_PROFILE, { resetPlainPasswords: true });
markDirty(false);
