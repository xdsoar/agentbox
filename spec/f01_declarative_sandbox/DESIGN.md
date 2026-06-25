# F01 设计方案

## 架构决策

### 决策 1：沿用 docker-compose 而非裸 docker 命令

**选择**：保留 `docker-compose.yml` 作为容器定义，agentbox CLI 调用 `docker compose` 子命令。

**理由**：
- compose 已处理镜像构建、env file 读取、security opts、资源限制
- 保留与现有 `.agentbox.yml` compose override 的兼容性
- 避免重写所有容器配置到裸 `docker run` 参数

### 决策 2：容器 CMD 改为 `sleep infinity`

**选择**：将容器从一次性 `bash` 改为后台保持的 `sleep infinity`。

**理由**：
- `docker compose run --rm`（原方案）每次创建新容器并销毁，不满足复用需求
- `sleep infinity` 是最轻量的后台保持方式（零 CPU 消耗）
- `agent-init.sh` 仍在 ENTRYPOINT 执行，完成状态初始化后 exec 到 sleep

### 决策 3：Bash 作为 CLI 语言

**选择**：不引入 Go/Rust/Node.js 运行时，全部用 Bash + jq + Docker CLI。

**理由**：
- agentbox 现有代码全是 bash + Docker，保持一致性
- 目标用户（macOS 开发者）已有 bash 和 Docker
- jq 是唯一新增依赖（brew install jq），用于 JSON 解析
- 复杂度可控：总代码量约 500 行 bash

### 决策 4：Hash 检测驱动容器重建

**选择**：计算 `hash(Dockerfile + 自定义 Dockerfile + devcontainer.json features + build)` 与上次存储值对比。

**理由**：
- 比时间戳可靠（git checkout 可能重置修改时间）
- 比 `docker compose up --no-recreate` 更精确（compose 只检查 compose 文件本身，不知道 devcontainer.json 的变更）
- 项目依赖（requirements.txt）的变更不触发重建，而是由 postCreateCommand 增量处理

### 决策 5：Session 标记文件替代引用计数

**选择**：`.agent/container/sessions/<session-id>` 空文件标记活跃会话，而非维护整数计数器。

**理由**：
- 不需要保证 inc/dec 原子性（文件创建/删除是原子的）
- 异常退出自动清理（trap EXIT 删除标记文件）
- 可扩展：未来可记录 session 元数据（启动时间、命令等）

### 决策 6：postCreate 通过文件注入

**选择**：将 postCreateCommand 写入文件 → mount 进容器 → agent-init.sh 检测执行 → CLI 删除文件。

**理由**：
- 避免 Docker SDK API 调用（保持纯 CLI 依赖）
- `agent-init.sh` 是自然执行点（容器 ENTRYPOINT）
- 文件存在性保证只执行一次（CLI 执行后删除）

---

## 数据流

### 启动流程（`agentbox start`）

```
用户执行 agentbox start
       │
       ▼
devcontainer_init()
  ├─ 读 .agent/devcontainer.json
  ├─ 生成 compose override → .agent/container/compose.override.yml
  ├─ 设置 COMPOSE_PROJECT（基于项目路径 hash）
  └─ 提取 AGENTBOX_MOUNTS
       │
       ▼
volume_create_all()
  └─ docker volume create（幂等，已存在则跳过）
       │
       ▼
容器存在？
  ├─ 否 → docker compose build → docker compose up -d --wait
  │       → _save_hashes() → _run_postcreate()
  │
  ├─ 是 + hash 变 → docker compose down → build → up -d --wait
  │                → _save_hashes() → _run_postcreate()
  │
  └─ 是 + hash 不变 + 容器 stopped → docker compose start

       │
       ▼
_run_postcreate()
  ├─ 读 devcontainer.json 的 postCreateCommand
  ├─ 写 .agent/container/post-create.sh
  ├─ mount 进容器 /.agentbox/post-create.sh（via compose override）
  ├─ docker compose exec agent bash /.agentbox/post-create.sh
  └─ 删除 post-create.sh（标注已执行）
```

### 会话封装流程（`agentbox run <cmd>`）

```
用户执行 agentbox run <cmd>
       │
       ▼
container_start()（确保容器在运行）
       │
       ▼
session_register()
  └─ touch .agent/container/sessions/<ses-PID-timestamp>
       │
       ▼
docker compose exec -it agent <cmd>
       │
       ▼
trap EXIT → _session_cleanup()
  ├─ session_unregister()（删除标记文件）
  └─ session_has_active()？
       ├─ 否 → container_stop()
       └─ 是 → 什么都不做
```

### 退出流程（`agentbox clean`）

```
agentbox clean
       │
       ▼
docker compose down（删除容器）
       │
       ▼
rm -rf .agent/container（删除状态文件）
       │
       ▼
volume_cleanup()
  └─ 删除 devcontainer.json mounts 中声明的项目级 volumes
     （共享 volumes 如 pip-cache/npm-cache 不删除）
```

---

## 状态文件

| 路径 | 内容 | 写入时机 |
|---|---|---|
| `.agent/container/image.hash` | SHA-256 of Dockerfile(s) | 每次重建容器时 |
| `.agent/container/features.hash` | SHA-256 of devcontainer.json features+build+image | 每次重建容器时 |
| `.agent/container/compose.override.yml` | 生成的 compose override | 每次 `devcontainer_init()` 调用时 |
| `.agent/container/sessions/<id>` | 空文件（存在 = 活跃） | session 开始/结束时增删 |
| `.agent/container/post-create.sh` | postCreateCommand 脚本 | 容器创建时；执行后立即删除 |

---

## 兼容性

- **向后兼容**：没有 `.agent/devcontainer.json` 的项目仍然可用（生成 minimal override）
- **`.agentbox.yml` 不受影响**：compose override merge 机制独立于 devcontainer 系统
- **`.env` 不受影响**：环境变量 passthrough 保持不变
- **agentbox 基础镜像**：Dockerfile 未修改，现有 `docker compose build` 仍然有效
