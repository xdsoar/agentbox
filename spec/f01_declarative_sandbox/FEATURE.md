# F01: Declarative Agent Sandbox

**Feature**: 基于 `.devcontainer` 规范的声明式 Agent 容器环境管理

## 概述

为 agentbox 新增声明式容器生命周期管理能力。用户在项目 `.agent/devcontainer.json` 中声明 agent 需要的运行环境（语言运行时、系统依赖、缓存策略），agentbox CLI 自动管理容器的创建、复用、重建和清理。

## 核心功能

### 1. 声明式环境配置

项目根目录的 `.agent/devcontainer.json` 声明 agent 的容器环境：

```jsonc
{
  "build": { "dockerfile": "./Dockerfile.dev" },  // 定制 Dockerfile
  "image": "python:3.12-bookworm",                  // 或直接用已有镜像
  "features": {                                     // 社区工具安装器
    "ghcr.io/devcontainers/features/java:1": { "version": "21" }
  },
  "mounts": [                                       // 持久化缓存
    "source=maven-repo,target=/home/node/.m2/repository,type=volume"
  ],
  "postCreateCommand": "pip install -r requirements.txt",
  "containerEnv": { "JAVA_HOME": "/usr/lib/jvm/msopenjdk-21" }
}
```

### 2. 智能容器复用

- Dockerfile 未变 → 复用已有容器（`docker start`，秒级）
- Dockerfile 或 features 变更 → 自动重建（`docker compose down` + `build` + `up`）
- 判断依据：hash(Dockerfile + 自定义 Dockerfile + devcontainer.json features + build)

### 3. 三层持久化

| Layer | 内容 | 生命周期 |
|---|---|---|
| 镜像 | Dockerfile RUN 指令产物 | Dockerfile 变更时重建 |
| 容器 | Features 安装 + 运行时状态 | 配置未变时复用 |
| Volumes | Maven/Pip/NPM 缓存 | 手动清理，跨容器持久 |

### 4. 多 Session 容器共享

同一项目的多个 agent 对话共享同一个容器实例：
- 第一个会话 `docker start` 容器
- 后续会话直接接入
- 最后一个会话退出时 `docker stop`
- 通过 `.agent/container/sessions/` 下的标记文件追踪活跃会话

### 5. postCreate 钩子

容器首次创建后自动执行（如 `pip install -r requirements.txt` 预热依赖缓存）：
- 脚本注入到容器的 `/.agentbox/post-create.sh`
- 由 `agent-init.sh` 在容器启动时检测并执行
- 仅在首次启动时执行，容器复用时跳过

## CLI 接口

```bash
# 高层（session 感知，自动管理容器生命周期）
agentbox                 # 进入交互 shell
agentbox opencode        # 启动 OpenCode TUI
agentbox claude          # 启动 Claude Code
agentbox run <cmd>       # 容器内执行命令

# 底层（容器管理）
agentbox start           # 确保容器运行
agentbox stop            # 停止容器（会话感知）
agentbox rebuild         # 强制重建
agentbox clean            # 移除容器 + 项目 volumes + 状态
agentbox status          # 查看容器状态
```

## 文件清单

| 文件 | 类型 | 职责 |
|---|---|---|
| `bin/agentbox` | 新增 | CLI 入口，命令分发 |
| `lib/container.sh` | 新增 | 容器生命周期：hash 检测、create/reuse/rebuild |
| `lib/session.sh` | 新增 | 多 session 管理：注册/注销/活跃计数 |
| `lib/devcontainer.sh` | 新增 | devcontainer.json 解析 + compose override 生成 |
| `lib/volume.sh` | 新增 | 命名 volume 创建/清理 |
| `docker-compose.yml` | 修改 | `command: ["sleep", "infinity"]`，启用 npm/pip cache volumes |
| `agent-init.sh` | 修改 | 新增 postCreate 钩子 |
| `devcontainer.example.json` | 新增 | 用户模板 |
| `tests/run.sh` | 新增 | 自动化测试（8 场景） |
| `tests/README.md` | 新增 | 测试用例文档（11 场景） |

## 不在范围

- VS Code IDE 集成（`customizations`、扩展、`forwardPorts`）
- Docker-in-Docker 完整支持（Feature 接口保留但未验证）
- 多项目并发隔离（确认由用户承担冲突风险）
- 远程/云端容器
- Nix 集成
