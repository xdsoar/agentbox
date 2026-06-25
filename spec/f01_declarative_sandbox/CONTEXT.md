# F01 验证上下文

本文档供另一个 OpenCode 实例在 Docker 环境中验证本功能使用。

## 环境要求

- macOS 或 Linux（有 Docker daemon）
- Docker Desktop / OrbStack / 原生 Docker 已运行
- `jq` 已安装（`brew install jq` 或 `apt-get install jq`）
- agentbox 基础镜像已构建：`cd /path/to/agentbox && docker compose build`

## 启动 agentbox CLI

```bash
# 设置环境变量
export AGENTBOX_HOME="/path/to/agentbox"   # agentbox 仓库所在目录
export PATH="$AGENTBOX_HOME/bin:$PATH"

# 验证可用
agentbox --help
```

## 验证场景覆盖

验证顺序：场景 1 → 2 → 3 → 4（postCreate）→ 5 → 7 → 9

### 场景 1：首次启动（冷启动）

```bash
# 准备：创建干净的项目目录
mkdir -p /tmp/agentbox-test-1/.agent

# 复制模板
cp $AGENTBOX_HOME/devcontainer.example.json /tmp/agentbox-test-1/.agent/devcontainer.json

# 修改模板：去掉 build 和 image，设为空
cat > /tmp/agentbox-test-1/.agent/devcontainer.json <<'JSON'
{}
JSON

cd /tmp/agentbox-test-1
agentbox start
```

**应观察到**：`docker compose build` 构建镜像，`docker compose up -d` 创建容器，终端输出 `Container ready`。

**验证**：
```bash
# 状态文件已创建
cat .agent/container/image.hash     # 非空
cat .agent/container/features.hash  # 非空

# 容器可交互
agentbox exec whoami   # → node
agentbox exec pwd      # → /agentbox-test-1
```

### 场景 2：容器复用（不重建）

```bash
# 创建标记文件
agentbox exec touch /tmp/reuse-marker

# 重新 start（配置未变）
agentbox start
```

**应观察到**：终端输出 `Starting existing container...`，没有构建过程。

```bash
# 标记文件仍在（证明是同一容器）
agentbox exec ls /tmp/reuse-marker   # → /tmp/reuse-marker
```

### 场景 3：配置变更触发重建

```bash
# 修改 devcontainer.json 的 features（触发 hash 变更）
cat > .agent/devcontainer.json <<'JSON'
{"features": {"trigger-rebuild": "v2"}}
JSON

agentbox start
```

**应观察到**：终端输出 `Config changed — rebuilding container...`，然后执行 build + up。

```bash
# 之前创建的标记文件应消失（新容器）
agentbox exec ls /tmp/reuse-marker   # → No such file

# hash 已更新
cat .agent/container/features.hash   # 不同于之前的值
```

### 场景 4：postCreate 钩子

```bash
# 修改 devcontainer.json，设置 postCreateCommand
cat > .agent/devcontainer.json <<'JSON'
{"features": {}, "postCreateCommand": "echo 'PC_RAN' > /tmp/pc-test"}
JSON

# 修改 features 触发重建
cat > .agent/devcontainer.json <<'JSON'
{"features": {"rebuild-again": "v3"}, "postCreateCommand": "echo 'PC_RAN' > /tmp/pc-test"}
JSON

agentbox start
```

```bash
# postCreate 已执行
agentbox exec cat /tmp/pc-test       # → PC_RAN

# 不触发重建时，postCreate 应只执行一次
agentbox start                        # → Starting existing container...
agentbox exec wc -l /tmp/pc-test     # → 1（只有一行，没重复执行）
```

### 场景 5：Volume 缓存持久化

```bash
# 当前配置保持原样
agentbox exec pip install requests    # 首次下载安装

# 强制重建
agentbox rebuild
```

**应观察到**：完整构建 + 容器重建流程。

```bash
# 再次安装，应命中缓存
agentbox exec pip install requests    # 输出包含 "already satisfied"

# 缓存 volume 存在
docker volume ls | grep pip-cache     # → pip-cache
```

### 场景 7：空闲容器自动 Stop

```bash
# 使用 `agentbox run`（session 感知模式）
agentbox run echo "done"

sleep 2

# 容器应已停止
agentbox status                       # → Status: stopped
```

### 场景 9：Clean 命令

```bash
agentbox clean
```

**应观察到**：容器被删除，`.agent/container/` 目录被清理。

```bash
# 验证清理
ls .agent/container/ 2>&1      # → No such file or directory

# 冷启动仍然可用
agentbox start                   # → First start — building image...
```

---

## 交互式验证（需手动）

### 场景 6：多终端容器共享

需要两个终端窗口，同时 cd 到同一项目目录：

**终端 A**：
```bash
cd /tmp/agentbox-test-1
agentbox                            # 进入交互 shell，保持连接
```

**终端 B**：
```bash
cd /tmp/agentbox-test-1
agentbox exec ls /tmp               # 应能正常执行
exit                                # 终端 B 退出
```

**终端 A**：`exit`

**观察**：终端 B 退出后容器仍运行（因为终端 A 还在），终端 A 退出后容器 stop。

### 场景 10：TUI 集成

```bash
cd /tmp/agentbox-test-1
agentbox opencode                   # 应进入 OpenCode TUI
# 退出后容器自动 stop（如无其他会话）
```

---

## 如果遇到问题

### 常见问题排查

1. **`docker compose build` 失败**：检查 `.env` 是否存在、Docker daemon 是否运行
2. **`jq: command not found`**：`brew install jq`（macOS）或 `apt-get install jq`（Linux）
3. **容器无法启动**：`docker compose logs agent` 查看容器日志
4. **session 目录未清理**：`rm -rf .agent/container/sessions/` 手动重置
5. **完全重置测试**：`agentbox clean && rm -rf .agent/container/`
6. **权限问题**：agentbox 容器以 `node` 用户（uid 1000）运行，确保项目目录对当前用户可读写

### 调试方法

```bash
# 查看 agentbox 状态
agentbox status

# 查看容器日志
docker compose -p <project-name> logs agent

# 查看 compose override 内容
cat .agent/container/compose.override.yml

# 手动进入容器（绕过 CLI）
docker compose -p <project-name> exec agent bash
```

---

## 相关文件路径

```
/path/to/agentbox/
├── bin/agentbox              ← CLI 入口（已验证 bash -n 无语法错误）
├── lib/container.sh          ← 容器生命周期
├── lib/session.sh            ← 会话管理
├── lib/devcontainer.sh       ← devcontainer 解析
├── lib/volume.sh             ← volume 管理
├── docker-compose.yml        ← 已修改（sleep infinity, cache volumes）
├── agent-init.sh             ← 已增强（postCreate 钩子）
├── devcontainer.example.json ← 用户模板
└── spec/f01_declarative-sandbox/
    ├── FEATURE.md            ← 功能说明
    ├── DESIGN.md             ← 设计方案
    └── CONTEXT.md            ← 本文件
```
