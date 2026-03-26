#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import {
  getInstallProfilePath,
  loadInstallProfile,
  validateInstallProfile,
  writeInstallProfile
} from "./install-profile-lib.mjs";

function parseArgs(argv) {
  const args = {
    workspaceRoot: process.cwd(),
    versionDir: "",
    installProfilePath: "",
    readyFile: ""
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--workspace-root":
        args.workspaceRoot = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--version-dir":
        args.versionDir = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--install-profile":
        args.installProfilePath = path.resolve(argv[index + 1]);
        index += 1;
        break;
      case "--ready-file":
        args.readyFile = path.resolve(argv[index + 1]);
        index += 1;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!args.versionDir) {
    throw new Error("--version-dir is required");
  }
  if (!args.readyFile) {
    throw new Error("--ready-file is required");
  }

  return args;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function readRegistryEntries(registryDir) {
  return fs.readdirSync(registryDir)
    .filter((fileName) => fileName.endsWith(".yml") || fileName.endsWith(".yaml"))
    .map((fileName) => {
      const filePath = path.join(registryDir, fileName);
      const content = fs.readFileSync(filePath, "utf8");
      const key = (content.match(/^key:\s*(.+)$/m)?.[1] || "").trim();
      const modelId = (content.match(/^modelId:\s*(.+)$/m)?.[1] || "").trim();
      const provider = (content.match(/^provider:\s*(.+)$/m)?.[1] || "").trim();
      return {
        key: key || path.basename(fileName, path.extname(fileName)),
        modelId,
        provider
      };
    })
    .sort((left, right) => left.key.localeCompare(right.key));
}

function buildHtml({ profile, providers, models, installProfilePath }) {
  const providerOptions = providers.map((item) => {
    const selected = item.key === profile.primaryProvider ? " selected" : "";
    return `<option value="${escapeHtml(item.key)}"${selected}>${escapeHtml(item.key)}</option>`;
  }).join("");

  const modelOptions = models.map((item) => {
    const selected = item.key === profile.primaryModel ? " selected" : "";
    const label = item.modelId ? `${item.key} (${item.modelId})` : item.key;
    return `<option value="${escapeHtml(item.key)}"${selected}>${escapeHtml(label)}</option>`;
  }).join("");

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ZenMind 首次配置</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4efe6;
      --card: rgba(255,255,255,0.92);
      --ink: #1f2937;
      --muted: #6b7280;
      --line: rgba(31,41,55,0.12);
      --accent: #0f766e;
      --accent-soft: rgba(15,118,110,0.12);
      --danger: #b91c1c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Avenir Next", "PingFang SC", "Noto Sans SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(15,118,110,0.22), transparent 32%),
        radial-gradient(circle at bottom right, rgba(217,119,6,0.18), transparent 28%),
        var(--bg);
      color: var(--ink);
      display: grid;
      place-items: center;
      padding: 24px;
    }
    .card {
      width: min(720px, 100%);
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 24px;
      padding: 28px;
      box-shadow: 0 18px 60px rgba(31,41,55,0.08);
      backdrop-filter: blur(12px);
    }
    h1 { margin: 0 0 10px; font-size: 32px; }
    p { margin: 0 0 14px; line-height: 1.6; color: var(--muted); }
    .note {
      background: var(--accent-soft);
      border-radius: 16px;
      padding: 14px 16px;
      margin: 18px 0 22px;
    }
    form { display: grid; gap: 16px; }
    label { display: grid; gap: 8px; font-weight: 600; }
    input, select, button {
      font: inherit;
      border-radius: 14px;
      border: 1px solid var(--line);
      padding: 12px 14px;
      width: 100%;
      background: white;
    }
    button {
      border: none;
      background: var(--accent);
      color: white;
      font-weight: 700;
      cursor: pointer;
      margin-top: 8px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 16px;
    }
    .status {
      min-height: 24px;
      color: var(--danger);
      font-size: 14px;
    }
    .path {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 13px;
      color: var(--ink);
      word-break: break-all;
    }
  </style>
</head>
<body>
  <main class="card">
    <h1>ZenMind 首次配置</h1>
    <p>把系统真正跑起来只需要先填这 6 项。语音、图片生成和更多 provider 配置可以在安装完成后再补。</p>
    <div class="note">
      <p><strong>这一步会直接写入本机安装配置。</strong></p>
      <p class="path">${escapeHtml(installProfilePath)}</p>
    </div>
    <form id="wizard-form">
      <label>
        网站名 / 域名
        <input name="siteName" value="${escapeHtml(profile.siteName)}" placeholder="例如 localhost 或 zenmind.local" required>
      </label>
      <div class="grid">
        <label>
          管理员用户名
          <input name="adminUsername" value="${escapeHtml(profile.adminUsername)}" required>
        </label>
        <label>
          管理员密码
          <input name="adminPassword" type="password" value="${escapeHtml(profile.adminPassword)}" required>
        </label>
      </div>
      <div class="grid">
        <label>
          主 Provider
          <select name="primaryProvider" required>${providerOptions}</select>
        </label>
        <label>
          主 Model
          <select name="primaryModel" required>${modelOptions}</select>
        </label>
      </div>
      <label>
        API Key
        <input name="primaryApiKey" type="password" value="${escapeHtml(profile.primaryApiKey)}" required>
      </label>
      <div class="status" id="status"></div>
      <button type="submit">保存并继续安装</button>
    </form>
  </main>
  <script>
    const form = document.getElementById("wizard-form");
    const statusNode = document.getElementById("status");
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      statusNode.textContent = "";
      const payload = Object.fromEntries(new FormData(form).entries());
      try {
        const response = await fetch("/api/save", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        });
        if (!response.ok) {
          const error = await response.text();
          throw new Error(error || "保存失败");
        }
        statusNode.style.color = "#0f766e";
        statusNode.textContent = "配置已保存，终端会自动继续后续安装。";
      } catch (error) {
        statusNode.style.color = "#b91c1c";
        statusNode.textContent = error.message || "保存失败";
      }
    });
  </script>
</body>
</html>`;
}

async function readRequestBody(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const installProfilePath = args.installProfilePath || getInstallProfilePath(args.workspaceRoot);
  const providersDir = path.join(args.versionDir, "deploy", ".zenmind", "registries", "providers");
  const modelsDir = path.join(args.versionDir, "deploy", ".zenmind", "registries", "models");
  const providers = readRegistryEntries(providersDir);
  const models = readRegistryEntries(modelsDir);
  const existingProfile = fs.existsSync(installProfilePath)
    ? loadInstallProfile(installProfilePath)
    : {
        siteName: "localhost",
        adminUsername: "admin",
        adminPassword: "",
        primaryProvider: providers[0]?.key || "",
        primaryModel: models[0]?.key || "",
        primaryApiKey: ""
      };

  const server = http.createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/") {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end(buildHtml({
        profile: existingProfile,
        providers,
        models,
        installProfilePath
      }));
      return;
    }

    if (request.method === "POST" && request.url === "/api/save") {
      try {
        const payload = JSON.parse(await readRequestBody(request));
        validateInstallProfile(payload);
        writeInstallProfile(args.workspaceRoot, payload, installProfilePath);
        response.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
        response.end(JSON.stringify({ ok: true }));
        setTimeout(() => {
          server.close(() => process.exit(0));
        }, 150);
      } catch (error) {
        response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
        response.end(error.message || "invalid install profile");
      }
      return;
    }

    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("not found");
  });

  server.listen(0, "127.0.0.1", () => {
    const address = server.address();
    const url = `http://127.0.0.1:${address.port}/`;
    fs.mkdirSync(path.dirname(args.readyFile), { recursive: true });
    fs.writeFileSync(args.readyFile, `${url}\n`, "utf8");
  });
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
