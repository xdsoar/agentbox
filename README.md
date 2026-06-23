# agent-box

在 macOS 上用单一容器统一运行 **Claude Code** 与 **OpenCode**。容器本身就是安全边界,
agent 在容器内跑全自治(YOLO),靠**逐项目的挂载策略**决定它实际能碰到什么。
出网管控放在路由器/防火墙层做(容器这一层不做出口过滤)。

## 设计要点

- **一个镜像,两个 agent**:`@anthropic-ai/claude-code` 与 `opencode-ai` 都全局装在 `/usr/local`。
- **omo 预装**:`oh-my-openagent` 在构建时已注入 OpenCode(模板写在镜像 `/home/node/.config/opencode`),
  每个项目首次运行由 `agent-init.sh` 播种一份独立副本,开箱即用。
- **逐项目隔离的 dotfile**:不挂宿主机 `~/.claude`(那才是跨项目记忆串联的来源)。
  通过环境变量把两个 agent 的全部状态(记忆/配置/历史/缓存)重定向到项目内的 `./.agent/`。
  → 项目间零串联;`rm -rf .agent` 即可清空某项目的 agent 记忆。
- **版本可控**:容器内关掉自更新(`DISABLE_AUTOUPDATER=1`),版本由构建参数 pin 死,
  升级 = 改版本号重新 build,坏了改回旧 tag 即可,绝不会运行中被动升级。
- **爆炸半径受限**:`no-new-privileges`、`cap_drop: ALL`、`pids/mem/cpu` 限额、`/tmp` tmpfs。

## 一次性准备

```bash
# 放到一个固定位置,例如 ~/agent-box
cd ~/agent-box
cp .env.example .env && chmod 600 .env   # 填入 key 或 gateway
docker compose build                      # 构建镜像 agent-box:local
```

在 `~/.zshrc` 里加一个包装函数,之后在**任意项目目录**里一行启动:

```bash
agentbox() {
  PROJECT_DIR="$PWD" \
  docker compose -f "$HOME/agent-box/docker-compose.yml" --env-file "$HOME/agent-box/.env" \
    run --rm agent "$@"
}
```

## 日常用法

```bash
cd ~/code/some-project

agentbox                # 进容器 shell,/workspace 即当前项目
# 然后在容器里:
claude-yolo             # = claude --dangerously-skip-permissions
opencode                # OpenCode TUI(默认即全权限)

# 或一步到位:
agentbox claude-yolo
agentbox opencode
```

首次运行后,项目里会多出 `./.agent/`。**务必加进该项目的 `.gitignore`**:

```
.agent/
```

## 逐项目调整挂载策略(同一镜像,按项目调安全级别)

| 维度 | 可信项目 | 不可信 / 外部代码 |
|---|---|---|
| 项目挂载 | `:rw` | `:rw`(纯 review 时可在 compose 改成 `:ro`,agent 只读不能改) |
| 共享包缓存 | 可开启 npm/pip 缓存卷加速 | 关闭(不共享可能被投毒的缓存) |
| 出网 | 路由器/防火墙层按需放行 | 路由器/防火墙层收紧(容器这层不做过滤) |

容器内出口不做白名单——如需限制 agent 能访问哪些外部地址,在 iKuai / OpenWrt 上对该容器
(或整个 OrbStack VM)的流量做策略即可,粒度和审计都比塞个代理进容器更好控。

## omo / OpenCode 配置(已钉死 DeepSeek V4 Pro)

OpenCode 和 omo 都已在构建时配成**只用 `deepseek/deepseek-v4-pro`**:

- `opencode.json` 加了一个 `deepseek` provider(`@ai-sdk/openai-compatible`,baseURL
  `https://api.deepseek.com`,key 取运行时环境变量 `DEEPSEEK_API_KEY`),并把全局 `model` /
  `small_model` 都设成 `deepseek/deepseek-v4-pro`。
- omo 的 `oh-my-openagent.json` 里**每个 agent 和 category 的 model 都被重写成同一个**,并删掉了
  指向其他 provider 的 variant/fallback。

这些配置进了镜像模板,每个项目首次运行时播种到 `./.agent/config/opencode/`,所以**所有项目、所有
agent 都只走 DeepSeek V4 Pro**。在 `.env` 里填好 `DEEPSEEK_API_KEY` 即可。

验证:在容器里跑 `omo doctor`,它会列出每个 agent 的 effective model,确认全是 deepseek-v4-pro。

可选调整:

- **走网关而非官方 API**:`docker compose build --build-arg DEEPSEEK_BASE_URL=https://your-gw/v1`
  重新构建;或直接改某项目 `./.agent/config/opencode/opencode.json` 里的 `baseURL`。
- **省钱**:`small_model` 也用了 V4 Pro,标题生成这类轻活有点浪费。想省的话把
  `opencode.json` 的 `small_model` 改成 `deepseek/deepseek-v4-flash`(需在 provider 的 `models`
  里加一个 `deepseek-v4-flash` 条目)。
- **开思考模式**:DeepSeek V4 Pro 支持 `reasoning_effort` high/xhigh(xhigh=max),按需在
  provider 的模型选项里加,默认是非思考模式。

> 构建时 omo install 用 `--claude=yes` 只是为了让它生成一份完整的 agent 配置(deepseek 不在 omo 的
> 订阅 flag 选项里),随后会被上面的脚本整体重写成 deepseek,所以这个 flag 填什么都无所谓。

## 两个要诚实记住的边界

1. **API key 在容器环境变量里,agent 进程能读到它**(`printenv` 即见)。这是它正常工作的代价,
   消不掉。缓解:用可轮换/可限额的 gateway token;外泄风险的兜底就放在你路由器层的出网策略上。
   **`.env` 只放在 `~/agent-box`、`chmod 600`、不进任何 repo。**
2. **agent 闭环需要工具链在容器内**。对“容器内写、容器外跑”的高性能项目,agent 看不到编译/测试
   结果,自治会断。建议把该项目的运行时(python/node/jdk/cargo 等)加进镜像,或给该项目单独写一个
   `FROM agent-box:local` 的派生 Dockerfile,把闭环留在容器里。
