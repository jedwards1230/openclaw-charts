#!/usr/bin/env bash
# =============================================================================
# runtime-inventory.sh - OpenClaw Container Runtime Inventory
# =============================================================================
#
# Generates runtime-specific markdown about the container environment.
# Covers ONLY what static image analysis (Syft/Trivy) cannot detect:
#   - Container runtime context (user, cwd, env vars)
#   - Filesystem layout and directory contents
#   - OpenClaw application details (package.json, npm scripts)
#   - User/permissions and security checks
#
# Used by CI (generate-docs.yml) inside a temp container, or manually:
#   kubectl exec -n home-agent deploy/openclaw -c openclaw -- \
#     bash < scripts/runtime-inventory.sh
#
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

out() { printf '%s\n' "$1"; }

# Safely read a field from /app/package.json via node
pkg_field() {
    local expr="$1"
    if [ -f /app/package.json ] && has_cmd node; then
        node -e "try{console.log($expr)}catch(e){console.log('Unknown')}" 2>/dev/null || echo "Unknown"
    else
        echo "Unknown"
    fi
}

# ---------------------------------------------------------------------------
# Application metadata
# ---------------------------------------------------------------------------

APP_NAME=$(pkg_field "require('/app/package.json').name||'Unknown'")
APP_VERSION=$(pkg_field "require('/app/package.json').version||'Unknown'")
APP_DESCRIPTION=$(pkg_field "require('/app/package.json').description||'Unknown'")
APP_LICENSE=$(pkg_field "require('/app/package.json').license||'Unknown'")
APP_MAIN=$(pkg_field "require('/app/package.json').main||'Unknown'")
APP_PKG_MANAGER=$(pkg_field "require('/app/package.json').packageManager||'Unknown'")
APP_NODE_ENGINE=$(pkg_field "(require('/app/package.json').engines||{}).node||'Unknown'")

# ==========================================================================
# Generate output
# ==========================================================================

# --- Container Runtime ---
echo "## Container Runtime"
echo ""
echo "| Property | Value |"
echo "|----------|-------|"
out "| Working Directory | \`$(pwd)\` |"
out "| User ID | $(id -u) |"
out "| Group ID | $(id -g) |"
out "| Home Directory | \`${HOME:-/root}\` |"
if has_cmd bash; then
    out "| Shell | $(bash --version 2>/dev/null | head -n1) |"
fi
out "| Hostname | \`${HOSTNAME:-unknown}\` |"
echo ""

# --- Environment Variables ---
echo "## Environment Variables"
echo ""

SENSITIVE_PATTERN='(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|PRIVATE)'

echo "### Application Environment"
echo ""
echo '```bash'
env 2>/dev/null | sort | while IFS='=' read -r name value; do
    [ -z "$name" ] && continue
    # Skip K8s service discovery noise
    case "$name" in
        *_SERVICE_HOST|*_SERVICE_PORT|*_SERVICE_PORT_*|*_PORT|*_PORT_*|KUBERNETES_*) continue ;;
    esac
    # Skip sensitive values
    if echo "$name" | grep -qE "$SENSITIVE_PATTERN"; then
        continue
    fi
    out "$name=$value"
done
echo '```'
echo ""

echo "### Secrets (Redacted)"
echo ""
echo "The following secret environment variables are set (values redacted):"
env 2>/dev/null | sort | while IFS='=' read -r name _value; do
    [ -z "$name" ] && continue
    if echo "$name" | grep -qE "$SENSITIVE_PATTERN"; then
        out "- \`$name\`"
    fi
done
echo ""

echo "### Kubernetes Service Discovery"
echo ""
echo "Kubernetes automatically injects service discovery environment variables:"
K8S_SVC_VARS=$(env 2>/dev/null | sort | grep -E '(_SERVICE_HOST|_SERVICE_PORT)$' || true)
if [ -n "$K8S_SVC_VARS" ]; then
    echo "$K8S_SVC_VARS" | while IFS='=' read -r name _value; do
        out "- \`$name\`"
    done
else
    echo "(none detected — may not be running in Kubernetes)"
fi
echo ""

# --- Filesystem Layout ---
echo "## Filesystem Layout"
echo ""

echo "### Application Structure"
echo ""
echo '```'
if [ -d /app ]; then
    out "/app/                           # OpenClaw application root"
    for entry in /app/*; do
        [ -e "$entry" ] || continue
        name=$(basename "$entry")
        if [ -d "$entry" ]; then
            out "  $name/"
        else
            out "  $name"
        fi
    done
fi
echo '```'
echo ""

echo "### Home Directory"
echo ""
echo '```'
HOME_DIR="${HOME:-/home/node}"
if [ -d "$HOME_DIR" ]; then
    out "$HOME_DIR/"
    for entry in "$HOME_DIR"/* "$HOME_DIR"/.*; do
        [ -e "$entry" ] || continue
        name=$(basename "$entry")
        case "$name" in .|..) continue ;; esac
        if [ -d "$entry" ]; then
            out "  $name/"
            if [ "$name" = ".openclaw" ]; then
                for subentry in "$entry"/*; do
                    [ -e "$subentry" ] || continue
                    subname=$(basename "$subentry")
                    if [ -d "$subentry" ]; then
                        out "    $subname/"
                    else
                        out "    $subname"
                    fi
                done
            fi
        else
            out "  $name"
        fi
    done
fi
echo '```'
echo ""

echo "### System Binaries"
echo ""
echo '```'
out "/usr/local/bin/                # Custom binaries"
if [ -d /usr/local/bin ]; then
    ls -1 /usr/local/bin 2>/dev/null | while read -r f; do
        if [ -L "/usr/local/bin/$f" ]; then
            target=$(readlink "/usr/local/bin/$f" 2>/dev/null || echo "?")
            out "  $f -> $target"
        else
            out "  $f"
        fi
    done
fi
echo '```'
echo ""

# --- OpenClaw Application ---
echo "## OpenClaw Application"
echo ""

echo "### Application Details"
echo ""
echo "| Property | Value |"
echo "|----------|-------|"
out "| Name | $APP_NAME |"
out "| Version | $APP_VERSION |"
out "| Description | $APP_DESCRIPTION |"
out "| License | $APP_LICENSE |"
out "| Main Entry | \`$APP_MAIN\` |"
out "| Package Manager | $APP_PKG_MANAGER |"
if [ "$APP_NODE_ENGINE" != "Unknown" ]; then
    NODE_VER=$(node --version 2>/dev/null || echo "Unknown")
    out "| Node.js Engine | $APP_NODE_ENGINE (running $NODE_VER) |"
fi
echo ""

echo "### Available Commands"
echo ""
echo "npm scripts from \`package.json\`:"
echo ""
if [ -f /app/package.json ] && has_cmd node; then
    node -e "
const pkg = require('/app/package.json');
const scripts = pkg.scripts || {};
const keys = Object.keys(scripts).sort();
for (const k of keys) {
    console.log('- \`npm run ' + k + '\` - \`' + scripts[k] + '\`');
}
" 2>/dev/null || echo "- (unable to read scripts)"
else
    echo "- (package.json not available)"
fi
echo ""

# --- User and Permissions ---
echo "## User and Permissions"
echo ""

echo "### Container User"
echo ""
echo "| Property | Value | Notes |"
echo "|----------|-------|-------|"

CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

if getent passwd "$CURRENT_UID" >/dev/null 2>&1; then
    USERNAME=$(getent passwd "$CURRENT_UID" | cut -d: -f1)
    out "| UID | $CURRENT_UID | User: $USERNAME |"
else
    out "| UID | $CURRENT_UID | No entry in /etc/passwd |"
fi

if getent group "$CURRENT_GID" >/dev/null 2>&1; then
    GROUPNAME=$(getent group "$CURRENT_GID" | cut -d: -f1)
    out "| GID | $CURRENT_GID | Group: $GROUPNAME |"
else
    out "| GID | $CURRENT_GID | No entry in /etc/group |"
fi
out "| Groups | $(id -G 2>/dev/null | tr ' ' ', ') | All groups |"
out "| Home | ${HOME:-/root} | From environment |"
echo ""

out "**Full id output**: \`$(id 2>/dev/null)\`"
echo ""

# --- Security Checks ---
echo "## Security Checks"
echo ""

# SUID/SGID binaries
echo "### SUID/SGID Binaries"
echo ""
SUID_SGID_LIST=$(find / -xdev \( -path /proc -o -path /sys \) -prune -o \( -perm -4000 -o -perm -2000 \) -type f -print 2>/dev/null || true)
if [ -n "$SUID_SGID_LIST" ]; then
    echo "| Binary | Permissions |"
    echo "|--------|-------------|"
    echo "$SUID_SGID_LIST" | while IFS= read -r binary; do
        [ -z "$binary" ] && continue
        perms=$(ls -l "$binary" 2>/dev/null | awk '{print $1}' || echo "unknown")
        out "| \`$binary\` | \`$perms\` |"
    done
else
    echo "No SUID/SGID binaries found."
fi
echo ""

# Writable paths
echo "### Writable Paths"
echo ""
echo "Testing writability of key directories (UID $(id -u)):"
echo ""
echo "| Path | Writable | Notes |"
echo "|------|----------|-------|"
for test_dir in "/" "/tmp" "/app" "/usr" "/etc" "/home/node" "/home/node/.openclaw"; do
    if [ -d "$test_dir" ]; then
        if [ -w "$test_dir" ]; then
            out "| \`$test_dir\` | Yes | Writable by current user |"
        else
            out "| \`$test_dir\` | No | Read-only for current user |"
        fi
    else
        out "| \`$test_dir\` | N/A | Directory does not exist |"
    fi
done
echo ""

# Read-only root filesystem
echo "### Read-Only Root Filesystem"
echo ""
RO_TEST_FILE="/.ro_test_$$"
if touch "$RO_TEST_FILE" 2>/dev/null; then
    rm -f "$RO_TEST_FILE" 2>/dev/null || true
    echo "- Root filesystem is **writable** (\`readOnlyRootFilesystem: false\` or not set)"
else
    echo "- Root filesystem is **read-only** (\`readOnlyRootFilesystem: true\`)"
fi
if [ -f /proc/mounts ]; then
    ROOT_OPTS=$(grep ' / ' /proc/mounts 2>/dev/null | head -n1 | awk '{print $4}')
    if [ -n "$ROOT_OPTS" ]; then
        if echo ",$ROOT_OPTS," | grep -q ",ro,"; then
            out "- /proc/mounts confirms: root mounted as **ro**"
        elif echo ",$ROOT_OPTS," | grep -q ",rw,"; then
            out "- /proc/mounts confirms: root mounted as **rw**"
        fi
    fi
fi
echo ""

# APT sources
echo "### APT Sources"
echo ""
if [ -f /etc/apt/sources.list ] || [ -d /etc/apt/sources.list.d ]; then
    echo "**Configured APT repositories**:"
    echo ""
    echo '```'
    if [ -f /etc/apt/sources.list ]; then
        echo "# /etc/apt/sources.list"
        grep -v '^\s*#' /etc/apt/sources.list 2>/dev/null | grep -v '^\s*$' || echo "(empty or commented out)"
        echo ""
    fi
    if [ -d /etc/apt/sources.list.d ]; then
        for src_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            [ -f "$src_file" ] || continue
            out "# $src_file"
            grep -v '^\s*#' "$src_file" 2>/dev/null | grep -v '^\s*$' || echo "(empty)"
            echo ""
        done
    fi
    echo '```'
    echo ""
    NON_STD_REPOS=$(grep -rhE '^(deb|URIs)' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -vE '(debian\.org|deb\.debian\.org|security\.debian\.org)' || true)
    if [ -n "$NON_STD_REPOS" ]; then
        echo "**Non-standard repositories detected**:"
        echo '```'
        echo "$NON_STD_REPOS"
        echo '```'
    else
        echo "All repositories are standard Debian sources."
    fi
else
    echo "No APT sources configuration found."
fi
echo ""

# Users with login shells
echo "### Users with Login Shells"
echo ""
echo "Accounts with real login shells (not \`/usr/sbin/nologin\` or \`/bin/false\`):"
echo ""
if [ -f /etc/passwd ]; then
    LOGIN_USERS=$(grep -vE ':/usr/sbin/nologin$|:/bin/false$' /etc/passwd 2>/dev/null || true)
    if [ -n "$LOGIN_USERS" ]; then
        echo "| Username | UID | GID | Shell |"
        echo "|----------|-----|-----|-------|"
        echo "$LOGIN_USERS" | while IFS=: read -r username _pass uid gid _gecos _home shell; do
            out "| $username | $uid | $gid | \`$shell\` |"
        done
    else
        echo "No users with login shells found."
    fi
else
    echo "/etc/passwd not available."
fi
echo ""

# --- Resource Limits ---
echo "## Resource Limits"
echo ""

echo "**CPU** (from host):"
if [ -f /proc/cpuinfo ]; then
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -n1 | cut -d: -f2 | sed 's/^[[:space:]]*//')
    CPU_COUNT=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null || echo "Unknown")
    out "- Model: ${CPU_MODEL:-Unknown}"
    out "- Processors visible: $CPU_COUNT"
else
    echo "- /proc/cpuinfo not available"
fi
echo ""

echo "**Memory** (from host):"
if [ -f /proc/meminfo ]; then
    MEM_TOTAL=$(grep 'MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2, $3}')
    MEM_AVAIL=$(grep 'MemAvailable' /proc/meminfo 2>/dev/null | awk '{print $2, $3}')
    out "- Total: ${MEM_TOTAL:-Unknown}"
    out "- Available: ${MEM_AVAIL:-Unknown}"
else
    echo "- /proc/meminfo not available"
fi
if [ -n "${NODE_OPTIONS:-}" ]; then
    out "- Node.js heap: $NODE_OPTIONS"
fi
echo ""

if [ -f /sys/fs/cgroup/memory.max ] || [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo "**Container cgroup limits**:"
    if [ -f /sys/fs/cgroup/memory.max ]; then
        MEM_LIMIT=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "Unknown")
        if [ "$MEM_LIMIT" != "max" ] && [ "$MEM_LIMIT" != "Unknown" ]; then
            MEM_LIMIT_MB=$((MEM_LIMIT / 1024 / 1024))
            out "- Memory limit: $MEM_LIMIT_MB MB"
        else
            out "- Memory limit: $MEM_LIMIT"
        fi
    elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        MEM_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "Unknown")
        MEM_LIMIT_MB=$((MEM_LIMIT / 1024 / 1024))
        out "- Memory limit: $MEM_LIMIT_MB MB"
    fi
    if [ -f /sys/fs/cgroup/cpu.max ]; then
        CPU_MAX=$(cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo "Unknown")
        out "- CPU quota: $CPU_MAX"
    fi
    echo ""
fi

# --- Storage ---
echo "## Storage"
echo ""

echo "### Disk Usage"
echo ""
echo '```'
df -h 2>/dev/null | grep -vE '(tmpfs|shm)' | head -20 || echo "(df not available)"
echo '```'
echo ""

echo "### All Mounts"
echo ""
echo '```'
df -h 2>/dev/null || echo "(df not available)"
echo '```'
echo ""

# --- Deployment-Specific Note ---
echo "## Deployment-Specific Auditing"
echo ""
echo "The following security checks require a live Kubernetes deployment and cannot"
echo "be performed in CI:"
echo ""
echo "- **Linux Capabilities**: \`/proc/1/status\` (CapInh, CapPrm, CapEff, CapBnd)"
echo "- **Seccomp Status**: Filter mode and BPF profile"
echo "- **AppArmor/SELinux**: Security module profiles"
echo "- **Listening Ports**: Active TCP listeners (\`ss -tlnp\`)"
echo "- **Network Interfaces**: Pod networking vs host networking"
echo "- **Mounted Secrets**: Kubernetes service account tokens"
echo "- **Filesystem Mount Options**: Security-relevant mount flags"
echo "- **Process List**: Running processes in the container"
echo ""
echo "To run a full deployment audit:"
echo '```bash'
echo 'kubectl exec -n home-agent deploy/openclaw -c openclaw -- bash < scripts/runtime-inventory.sh'
echo '```'
echo ""
