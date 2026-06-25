# agentbox Test Cases

## Automated Tests (`tests/run.sh`)

### Scenario 1: First Start — Cold Boot
| Step | Action | Expected Result |
|------|--------|-----------------|
| 1.1 | `agentbox start` on fresh project (no .agent/container/) | `docker compose build` runs, `docker compose up -d` creates container |
| 1.2 | Check `.agent/container/image.hash` | File exists, non-empty |
| 1.3 | Check `.agent/container/features.hash` | File exists |
| 1.4 | `docker compose ps --status running` | Container is running |
| 1.5 | `agentbox exec whoami` | Output: `node` |
| 1.6 | `agentbox exec pwd` | Output: `/<project-name>` |

### Scenario 2: Container Reuse — No Rebuild
| Step | Action | Expected Result |
|------|--------|-----------------|
| 2.1 | `agentbox start` (second time, no config change) | No "Building" output, container unchanged |
| 2.2 | `agentbox exec touch /tmp/reuse-marker` | File created |
| 2.3 | `agentbox exec ls /tmp/reuse-marker` | File exists (same container) |

### Scenario 3: Hash Change Triggers Rebuild
| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.1 | Modify Dockerfile or devcontainer.json features | Hash mismatch |
| 3.2 | `agentbox start` | Detects hash change → `docker compose down` → `build` → `up -d` |
| 3.3 | Check `.agent/container/image.hash` | Updated to new hash |
| 3.4 | `agentbox exec ls /tmp/reuse-marker` | File NOT found (new container) |

### Scenario 4: postCreateCommand Execution
| Step | Action | Expected Result |
|------|--------|-----------------|
| 4.1 | Set `postCreateCommand` in devcontainer.json | `"echo 'PC_RAN' > /tmp/pc-test"` |
| 4.2 | Trigger rebuild (modify features hash) | Container rebuilt |
| 4.3 | `agentbox exec cat /tmp/pc-test` | Output: `PC_RAN` |
| 4.4 | `agentbox exec cat /tmp/pc-test` (no rebuild) | File still exists (same container) |
| 4.5 | Trigger another rebuild | File exists with `PC_RAN` (postCreate re-ran) |

### Scenario 5: Volume Cache Persistence Across Rebuild
| Step | Action | Expected Result |
|------|--------|-----------------|
| 5.1 | `agentbox exec pip install requests` | Package installs |
| 5.2 | `agentbox rebuild` | Container destroyed and recreated |
| 5.3 | `agentbox exec pip install requests` | "Using cached" or near-instant completion |
| 5.4 | `docker volume ls \| grep pip-cache` | Volume exists |

### Scenario 7: Idle Container Auto-Stop
| Step | Action | Expected Result |
|------|--------|-----------------|
| 7.1 | `agentbox start` then `agentbox exec echo done` | Command completes |
| 7.2 | Wait 1s | Container should be stopped (no active sessions) |
| 7.3 | `docker compose ps --status running` | Empty (agent service not running) |

### Scenario 9: Clean Command
| Step | Action | Expected Result |
|------|--------|-----------------|
| 9.1 | `agentbox clean` | Container removed, project volumes removed |
| 9.2 | `docker compose ps` | No agent service |
| 9.3 | Check `.agent/container/` | State directory cleaned |
| 9.4 | `agentbox start` (after clean) | Cold boot, fresh container |

### Scenario 11: Multi-Project Isolation
| Step | Action | Expected Result |
|------|--------|-----------------|
| 11.1 | Project A and Project B each have `.agent/devcontainer.json` | Different configs |
| 11.2 | `agentbox exec hostname` in each project | Different container hostnames |
| 11.3 | `agentbox exec pip install flask` in Project A | flask only visible in Project A |
| 11.4 | `agentbox exec pip show flask` in Project B | Package not found |

---

## Interactive Tests (Manual Verification)

### Scenario 6: Multi-Session Container Sharing
| Step | Action | Expected Result |
|------|--------|-----------------|
| 6.1 | Terminal A: `agentbox` (enters bash) | Container running |
| 6.2 | Terminal A: `touch /tmp/session-a` | File created |
| 6.3 | Terminal B: `agentbox exec ls /tmp/session-a` | File visible (same container) |
| 6.4 | Terminal B: `exit` | Container NOT stopped (Terminal A still active) |
| 6.5 | Terminal A: `exit` | Container stopped (no more sessions) |

### Scenario 10: High-Level Interface — TUI
| Step | Action | Expected Result |
|------|--------|-----------------|
| 10.1 | `agentbox echo "hello"` | Output: `hello` (start + exec) |
| 10.2 | `agentbox opencode` | OpenCode TUI launches (container auto-started) |
| 10.3 | Exit OpenCode | Container stops (if no other sessions) |
| 10.4 | `agentbox` (bare, no args) | Enters interactive bash in container |
