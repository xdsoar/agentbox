#!/usr/bin/env bash
# container.sh — container lifecycle management for agentbox.
#
# Responsibilities:
#   - Hash-based change detection (Dockerfile + devcontainer features)
#   - Container create / reuse / rebuild decisions
#   - Docker compose orchestration (build, up, down, start, stop)
#
# Requires:
#   - $AGENTBOX_HOME       : agentbox installation directory
#   - $PROJECT_DIR          : user's project directory
#   - $COMPOSE_PROJECT      : unique docker compose project name (set by devcontainer.sh)
#   - $COMPOSE_OVERRIDE_FILE: path to generated compose override (set by devcontainer.sh)

set -euo pipefail

# ── state file paths ─────────────────────────────────────────────────────

state_dir()    { echo "$PROJECT_DIR/.agent/container"; }
image_hash()   { echo "$(state_dir)/image.hash"; }
features_hash(){ echo "$(state_dir)/features.hash"; }

# Compute SHA-256 of a file. Cross-platform (Linux sha256sum / macOS shasum).
_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "ERROR: no sha256sum or shasum found" >&2
        exit 1
    fi
}

# ── hash computation ─────────────────────────────────────────────────────

_current_image_hash() {
    # Hash both the base agentbox Dockerfile AND any project-specific Dockerfile
    # (specified via build.dockerfile in devcontainer.json).
    local tmpfile
    tmpfile=$(mktemp)
    cat "$AGENTBOX_HOME/Dockerfile" 2>/dev/null >> "$tmpfile" || true

    local config="$PROJECT_DIR/.agent/devcontainer.json"
    if [ -f "$config" ] && command -v jq &>/dev/null; then
        local custom_df
        custom_df=$(jq -r '.build.dockerfile // empty' "$config" 2>/dev/null || true)
        if [ -n "$custom_df" ] && [ -f "$PROJECT_DIR/$custom_df" ]; then
            cat "$PROJECT_DIR/$custom_df" >> "$tmpfile"
        fi
    fi

    local hash
    if [ -s "$tmpfile" ]; then
        hash=$(_sha256 "$tmpfile")
    else
        hash="0000000000000000000000000000000000000000000000000000000000000000"
    fi
    rm -f "$tmpfile"
    echo "$hash"
}

_current_features_hash() {
    local config="$PROJECT_DIR/.agent/devcontainer.json"
    if [ -f "$config" ] && command -v jq &>/dev/null; then
        # Hash the features + build section (everything that affects container creation)
        jq -S '{features: .features, build: .build, image: .image}' "$config" 2>/dev/null | \
            _sha256 <(cat)
    elif [ -f "$config" ]; then
        # Fallback: hash the whole file (jq not available)
        _sha256 "$config"
    else
        # No config: use default agentbox features = empty
        echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # sha256 of empty string
    fi
}

_stored_hash() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file"
    else
        echo ""
    fi
}

_save_hashes() {
    mkdir -p "$(state_dir)"
    _current_image_hash   > "$(image_hash)"
    _current_features_hash > "$(features_hash)"
}

_needs_rebuild() {
    local current_img current_feat stored_img stored_feat
    current_img="$(_current_image_hash)"
    current_feat="$(_current_features_hash)"
    stored_img="$(_stored_hash "$(image_hash)")"
    stored_feat="$(_stored_hash "$(features_hash)")"

    [ "$current_img" != "$stored_img" ] || [ "$current_feat" != "$stored_feat" ]
}

# ── compose command helpers ──────────────────────────────────────────────

_compose() {
    docker compose -p "$COMPOSE_PROJECT" \
        -f "$AGENTBOX_HOME/docker-compose.yml" \
        ${COMPOSE_OVERRIDE_FILE:+-f "$COMPOSE_OVERRIDE_FILE"} \
        "$@"
}

_container_running() {
    _compose ps --status running -q 2>/dev/null | grep -q .
}

_container_exists() {
    _compose ps -a -q 2>/dev/null | grep -q .
}

# ── public API ───────────────────────────────────────────────────────────

# Ensure container is running. Rebuild if config changed.
container_start() {
    # Initialize devcontainer config (sets COMPOSE_PROJECT, COMPOSE_OVERRIDE_FILE)
    devcontainer_init

    # Ensure volumes exist
    volume_create_all

    if ! _container_exists; then
        # First time: build image + create container
        echo "[agentbox] First start — building image and creating container..."
        _compose build
        _compose up -d --wait
        _save_hashes
        _run_postcreate
    elif _needs_rebuild; then
        # Config changed: destroy old container, rebuild, recreate
        echo "[agentbox] Config changed — rebuilding container..."
        _compose down
        _compose build
        _compose up -d --wait
        _save_hashes
        _run_postcreate
    elif ! _container_running; then
        # Container exists but stopped, no config change — just start it
        echo "[agentbox] Starting existing container..."
        _compose start
    fi
    # else: container already running, config unchanged — do nothing
}

container_stop() {
    if _container_running; then
        echo "[agentbox] Stopping container..."
        _compose stop
    fi
}

container_rebuild() {
    echo "[agentbox] Forcing full rebuild..."
    if _container_exists; then
        _compose down
    fi
    _compose build --no-cache
    _compose up -d --wait
    _save_hashes
    _run_postcreate
    echo "[agentbox] Rebuild complete."
}

container_clean() {
    echo "[agentbox] Cleaning up..."
    if _container_exists; then
        _compose down
    fi
    # Remove state directory
    if [ -d "$(state_dir)" ]; then
        rm -rf "$(state_dir)"
        echo "[agentbox] State directory removed: $(state_dir)"
    fi
    # Clean project-specific volumes only (not shared caches)
    volume_cleanup
    echo "[agentbox] Clean complete."
}

container_status() {
    echo "Project:   $PROJECT_DIR"
    echo "Compose:   $COMPOSE_PROJECT"

    if _container_running; then
        echo "Status:    running"
        _compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
    elif _container_exists; then
        echo "Status:    stopped"
    else
        echo "Status:    not created"
    fi

    if [ -f "$(image_hash)" ]; then
        echo "Image hash:  $(_stored_hash "$(image_hash)")"
    fi
    if [ -f "$(features_hash)" ]; then
        echo "Feat. hash:  $(_stored_hash "$(features_hash)")"
    fi
}

# ── postCreate hook ──────────────────────────────────────────────────────

_run_postcreate() {
    local config="$PROJECT_DIR/.agent/devcontainer.json"
    if [ ! -f "$config" ]; then
        return 0
    fi

    local post_create
    post_create=$(jq -r '.postCreateCommand // empty' "$config" 2>/dev/null || true)
    if [ -z "$post_create" ]; then
        return 0
    fi

    echo "[agentbox] Running postCreateCommand..."
    # Write a script and mount it so the container's entrypoint picks it up
    mkdir -p "$PROJECT_DIR/.agent/container"
    echo "#!/usr/bin/env bash"  > "$PROJECT_DIR/.agent/container/post-create.sh"
    echo "set -euo pipefail"   >> "$PROJECT_DIR/.agent/container/post-create.sh"
    echo "$post_create"        >> "$PROJECT_DIR/.agent/container/post-create.sh"
    chmod +x "$PROJECT_DIR/.agent/container/post-create.sh"

    # Run it inside the container
    _compose exec -T agent bash /.agentbox/post-create.sh 2>/dev/null || {
        echo "[agentbox] WARNING: postCreateCommand failed (exit code: $?)" >&2
    }
    rm -f "$PROJECT_DIR/.agent/container/post-create.sh"
}
