#!/bin/sh
# ---------------------------------------------------------------
# tailscale_upgrade.sh
# 监控 tailscale/tailscale GitHub Releases,有新版自动下载并替换
# 当前版本记录: /etc/storage/tailscale_version
# ---------------------------------------------------------------

set -e

BIN_DIR="/etc/storage/bin"
TS_BIN="${BIN_DIR}/tailscaled"
TSC_BIN="${BIN_DIR}/tailscale"
STATE_FILE="/etc/storage/tailscale_version"
LOG_FILE="/etc/storage/tailscale_upgrade.log"
LOCK="/var/lock/tailscale_upgrade.lock"

REPO="${TAILSCALE_REPO:-tailscale/tailscale}"

log() {
    printf "[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

exec 9>"$LOCK" || true
flock -n 9 || { log "locked, skip"; exit 0; }

log "== check tailscale latest =="

# Padavan 默认 MIPS 24KEc + softfloat
LATEST_JSON=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || echo "")

if [ -z "$LATEST_JSON" ]; then
    log "FAIL: cannot reach github api (no internet?)"
    exit 1
fi

TAG=$(echo "$LATEST_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/')
if [ -z "$TAG" ]; then
    log "FAIL: no tag in response"
    exit 2
fi

# 已有版本
CURRENT=""
[ -f "$STATE_FILE" ] && CURRENT=$(cat "$STATE_FILE")

log "current=$CURRENT latest=$TAG"

if [ "$CURRENT" = "$TAG" ]; then
    log "up-to-date, nothing to do"
    exit 0
fi

# 下载对应 mipsle 二进制
BASE_URL="https://github.com/${REPO}/releases/download/v${TAG}"
ASSET_TS="tailscale_${TAG}_mipsle.tgz"

# fallback URL 列表
for try_url in \
    "${BASE_URL}/${ASSET_TS}" \
    "${BASE_URL}/tailscale_${TAG}_mipsle.tar.gz" \
    "${BASE_URL}/tailscale_${TAG}_linux_mipsle.tar.gz"; do
    log "try $try_url"
    TMP="/tmp/ts_$$.tgz"
    if curl -fsSL --max-time 120 "$try_url" -o "$TMP"; then
        log "downloaded $(wc -c < $TMP) bytes"
        # 解包
        mkdir -p "${BIN_DIR}/.extract.$$"
        if tar -xzf "$TMP" -C "${BIN_DIR}/.extract.$$"; then
            # tar 出来的结构通常是 tailscale_${TAG}_mipsle/tailscaled 等
            FOUND_D=$(find "${BIN_DIR}/.extract.$$" -name tailscaled | head -1)
            if [ -z "$FOUND_D" ]; then
                log "FAIL: tailscaled missing in archive"
                rm -rf "${BIN_DIR}/.extract.$$" "$TMP"
                continue
            fi
            FOUND_D=$(dirname "$FOUND_D")

            # 备份旧版本
            [ -x "$TS_BIN" ] && cp "$TS_BIN" "${TS_BIN}.bak"
            [ -x "$TSC_BIN" ] && cp "$TSC_BIN" "${TSC_BIN}.bak"

            cp -f "$FOUND_D/tailscaled" "$TS_BIN"
            cp -f "$FOUND_D/tailscale"  "$TSC_BIN"
            chmod +x "$TS_BIN" "$TSC_BIN"

            rm -rf "${BIN_DIR}/.extract.$$" "$TMP"

            # 记录新版本
            echo "$TAG" > "$STATE_FILE"
            log "upgraded to $TAG"

            # 重启 tailscale(如果正在跑)
            if [ -x /etc/storage/tailscale.sh ]; then
                /etc/storage/tailscale.sh restart 2>&1 | tee -a "$LOG_FILE" || log "restart failed"
            fi

            # 通知
            if [ -x /etc/storage/notify.sh ]; then
                /etc/storage/notify.sh "Tailscale upgraded" "old=$CURRENT new=$TAG" 2>/dev/null || true
            fi
            exit 0
        fi
    fi
done

log "FAIL: could not download tailscale $TAG"
exit 3