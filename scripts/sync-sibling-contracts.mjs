#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const workspaceRoot = process.cwd();
const reposRoot = path.resolve(workspaceRoot, "..");

function writeFile(targetPath, content) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, content, "utf8");
}

function syncZenmindAppServer() {
  const repoRoot = path.join(reposRoot, "zenmind-app-server");
  const documentedDevBcrypt = "$2a$10$VAC1MOfQV2f6L3LqgU5PweT25AdVaRK3yvMLwXjA0uRUhtnbbQ1ue";
  writeFile(path.join(repoRoot, ".env.example"), `# Docker-first deployment contract for zenmind-app-server
FRONTEND_PORT=11950

# Public issuer used by OAuth2 / OIDC metadata.
AUTH_ISSUER=https://website.example.com

# Optional identity labels.
AUTH_ADMIN_USERNAME=admin
AUTH_APP_USERNAME=app

# Frontend base path behind the gateway.
VITE_BASE_PATH=/admin/

# Required bcrypt values. Replace before production use and keep single quotes around hashes.
AUTH_ADMIN_PASSWORD_BCRYPT='${documentedDevBcrypt}'
AUTH_APP_MASTER_PASSWORD_BCRYPT='${documentedDevBcrypt}'
`);

  writeFile(path.join(repoRoot, "docker-compose.yml"), `services:
  backend:
    image: zenmind-app-server-backend
    build:
      context: ./backend
    container_name: zenmind-app-server-backend
    env_file:
      - ./.env
    volumes:
      - ./data:/data
    expose:
      - "8080"
    networks:
      zenmind-network:
        aliases:
          - app-server-backend

  frontend:
    image: zenmind-app-server-frontend
    build:
      context: ./frontend
      args:
        VITE_BASE_PATH: \${VITE_BASE_PATH:-/admin/}
    container_name: zenmind-app-server-frontend
    depends_on:
      - backend
    environment:
      BACKEND_TARGET: http://backend:8080
      STATIC_DIR: /app/dist
    ports:
      - "\${FRONTEND_PORT}:80"
    networks:
      zenmind-network:
        aliases:
          - app-server-frontend

networks:
  zenmind-network:
    external: true
`);

  writeFile(path.join(repoRoot, "README.md"), `# zenmind-app-server

## 1. 项目简介

\`zenmind-app-server\` 是认证与管理服务，提供 OAuth2 / OIDC、管理后台、App 访问令牌和设备管理。

当前部署契约已经收敛为 Docker-first：

- backend 固定只在容器网络内监听 \`8080\`
- frontend 对外暴露 \`/admin/\`
- 根目录 \`.env.example\` 只保留部署必要项
- 外部“受管配置文件”不再作为默认部署契约

## 2. 快速开始

\`\`\`bash
cp .env.example .env
docker compose up -d --build
\`\`\`

默认入口：

- 管理台：\`http://127.0.0.1:11950/admin/\`

如需通过外层总网关接入，请保持：

- 管理台前缀：\`/admin/\`
- API 前缀：\`/admin/api\`
- OAuth2 / OIDC：\`/oauth2\`、\`/openid\`

## 3. 配置说明

- 环境变量契约以根目录 \`.env.example\` 为准
- 部署层只保留 \`FRONTEND_PORT\`；backend 不再暴露宿主机端口
- \`AUTH_ISSUER\` 仍然必需，因为服务会用它生成 OIDC / OAuth2 metadata
- 两个 bcrypt 仍然必填，推荐在写入 \`.env\` 时保留单引号
- 数据默认挂载到 \`./data\`

## 4. 部署

- \`docker-compose.yml\` 只负责双容器编排
- backend 容器网络端口固定为 \`8080\`
- frontend 容器负责静态资源和反向代理
- 若由总网关接入，不要再单独公开 backend 端口

## 5. 运维

- 查看日志：\`docker compose logs -f backend frontend\`
- OIDC metadata：\`curl -i http://127.0.0.1:11950/openid/.well-known/openid-configuration\`
- bcrypt 生成接口：\`POST /admin/api/bcrypt/generate\`
`);

  writeFile(path.join(repoRoot, "CLAUDE.md"), `# CLAUDE.md

## 1. 项目概览

\`zenmind-app-server\` 是一套认证与管理服务，提供 OAuth2 / OIDC、管理后台、App 访问令牌和设备管理。

仓库采用双容器 fullstack 结构：

- \`backend/\`：Go API，容器内固定监听 \`8080\`
- \`frontend/\`：React 管理台与前端网关，对外暴露 \`/admin/\`

## 2. 技术栈

- Backend：Go 1.23
- Frontend：React 18 + Vite
- HTTP 路由：\`chi\`
- 数据库：SQLite
- 配置：\`.env\`
- 部署：Docker / \`docker compose\`

## 3. 架构设计

- 浏览器访问 \`/admin/\`
- 前端网关代理 \`/admin/api/*\`、\`/oauth2/*\`、\`/openid/*\` 到 backend
- backend 负责认证、授权、管理 API 和 SQLite 持久化
- 当前版本不再把外部可编辑配置文件作为默认部署能力

## 4. 目录结构

- \`.env.example\`：部署环境变量契约
- \`docker-compose.yml\`：双容器本地编排
- \`backend/\`：Go 服务
- \`frontend/\`：管理台和前端网关
- \`data/\`：SQLite 持久化目录

## 5. 数据结构

核心模型仍位于：

- \`backend/internal/model/types.go\`
- \`backend/internal/store/store.go\`
- \`backend/schema.sql\`

## 6. API 定义

- Admin：\`/admin/api/*\`
- App Auth：\`/api/auth/*\`
- App Event：\`/api/app/*\`
- OAuth2：\`/oauth2/*\`
- OIDC：\`/openid/*\`

## 7. 开发要点

- \`.env.example\` 只维护部署必要字段
- backend 宿主机端口映射已从部署契约移除
- \`AUTH_ISSUER\`、两个 bcrypt、前端 base path 仍是关键输入
- 当前仓库仍兼容旧代码里的可编辑配置文件能力，但它不再是默认部署模型

## 8. 开发流程

1. \`cp .env.example .env\`
2. \`docker compose up -d --build\`
3. 后端改动后执行 \`make backend-test\`
4. 前端改动后执行 \`make frontend-build\`

## 9. 已知约束与注意事项

- backend 仅容器网络访问
- frontend 是唯一默认对外入口
- 公开 issuer 必须与真实部署入口一致
`);
}

function syncZenmindVoiceServer() {
  const repoRoot = path.join(reposRoot, "zenmind-voice-server");
  const composeContent = `services:
  voice-server:
    build:
      context: .
      dockerfile: Dockerfile
    image: zenmind-voice-server:local
    env_file:
      - .env
    ports:
      - "11953:11953"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:11953/actuator/health >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped

  voice-console:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    image: zenmind-voice-console:local
    depends_on:
      voice-server:
        condition: service_healthy
    ports:
      - "8088:80"
    restart: unless-stopped
`;
  writeFile(path.join(repoRoot, "docker-compose.yml"), composeContent);

  writeFile(path.join(repoRoot, "README.md"), `# zenmind-voice-server

## 1. 项目简介

这是一个统一语音服务示例仓库，提供实时 ASR、本地 TTS 和 QA 闭环语音对话能力。

外层网关契约已经固定为：

- 业务接口统一走 \`/api/voice/*\`
- 健康检查走 \`/actuator/health\`
- 本轮总控只接入 backend API，不公开 voice console 路由

## 2. 快速开始

\`\`\`bash
cp .env.example .env
go run ./cmd/voice-server
\`\`\`

默认地址：

- HTTP：\`http://localhost:11953\`
- WebSocket：\`ws://localhost:11953/api/voice/ws\`

## 3. 配置说明

- 环境变量契约文件：\`.env.example\`
- 当前只通过 \`.env\` / 环境变量注入真实值
- 最重要的部署路径约束是 \`/api/voice/*\`
- 若由总网关接入，应直接把 \`/api/voice/*\` 反代到 backend，而不是依赖 console 前端

## 4. 部署

\`\`\`bash
docker compose up --build
\`\`\`

- \`docker-compose.yml\` 是标准 compose 入口
- \`voice-server\` 负责 backend
- \`voice-console\` 仅用于本地调试控制台

## 5. 运维

- 健康检查：\`curl -sS http://localhost:11953/actuator/health\`
- 能力接口：\`curl -sS http://localhost:11953/api/voice/capabilities\`
`);

  writeFile(path.join(repoRoot, "CLAUDE.md"), `# CLAUDE.md

## 1. 项目概览
\`zenmind-voice-server\` 是一个统一语音服务示例仓库，提供实时 ASR、文本 TTS，以及 ASR -> LLM -> TTS 的 QA 闭环能力。

外层接口契约固定为：

- \`GET /api/voice/capabilities\`
- \`GET /api/voice/tts/voices\`
- \`GET /api/voice/ws\`
- \`GET /actuator/health\`

## 2. 技术栈
- 后端：Go 1.26、\`net/http\`、\`gorilla/websocket\`
- 前端：React 18、TypeScript、Vite
- 部署：Docker、\`docker compose\`

## 3. 架构设计
- backend 暴露唯一业务前缀 \`/api/voice/*\`
- console 前端只用于本地调试，不是总控外层路由契约
- QA 模式依赖外部 runner SSE

## 4. 目录结构
- \`cmd/voice-server\`：服务启动入口
- \`internal/httpapi\`：REST 接口
- \`internal/ws\`：WebSocket 协议实现
- \`frontend\`：本地调试控制台
- \`docker-compose.yml\`：标准 compose 入口

## 5. 数据结构
- \`config.App\`
- \`clientEvent\`
- \`sessionContext\`
- \`asrTask\` / \`ttsTask\`

## 6. API 定义
- \`GET /api/voice/capabilities\`
- \`GET /api/voice/tts/voices\`
- \`GET /api/voice/ws\`
- \`GET /actuator/health\`

## 7. 开发要点
- 默认服务端口仍由 \`SERVER_PORT\` 控制
- 对外路径只维护 \`/api/voice/*\`
- 当前版本未内建业务鉴权，接入方需在网关或部署层控制访问

## 8. 开发流程
1. \`cp .env.example .env\`
2. \`go run ./cmd/voice-server\`
3. \`cd frontend && npm install && npm run dev\`
4. \`docker compose up --build\`

## 9. 已知约束与注意事项
- 本轮总控只接入 backend API，不公开 console
- 若接入外层网关，不要再在路径层做第二套 voice 业务前缀
`);
}

syncZenmindAppServer();
syncZenmindVoiceServer();
process.stdout.write("Sibling deployment contracts synced.\n");
