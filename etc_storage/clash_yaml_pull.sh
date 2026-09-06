#!/bin/sh
# ---------------------------------------------------------------
# clash_yaml_pull.sh
# 从 GitHub 仓库拉取 Clash 配置 + 节点 + 规则,合并后写入
# /etc/storage/clash/config.yaml,并热重启 ShellClash
# ---------------------------------------------------------------

set -e

REPO="${CLASH_REPO:-YOUR_USER/YOUR_REPO}"   # GitHub user/repo
BRANCH="${CLASH_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/clash-yaml"
CACHE_DIR="/etc/storage/clash_yaml_cache"
DEST_DIR="/etc/storage/clash"
DEST_FILE="${DEST_DIR}/config.yaml"
LOG_FILE="/etc/storage/clash_yaml_pull.log"
LOCK="/var/lock/clash_yaml_pull.lock"

# 代理(路由器未必有国际网,所以先尝试走 ShellClash 自身)
USE_PROXY="${USE_PROXY:-1}"
PROXY_ADDR="${PROXY_ADDR:-http://127.0.0.1:7890}"

log() {
    printf "[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

curl_with_proxy() {
    if [ "$USE_PROXY" = "1" ]; then
        curl -fsSL --max-time 30 --proxy "$PROXY_ADDR" "$@"
    else
        curl -fsSL --max-time 30 "$@"
    fi
}

# 防止重入
exec 9>"$LOCK" || { log "locked, skip"; exit 0; }
flock -n 9 || { log "another instance running, exit"; exit 0; }

mkdir -p "$CACHE_DIR" "$DEST_DIR"

log "== pull start, repo=$REPO branch=$BRANCH =="

# 1) 拉主配置
if ! curl_with_proxy "${RAW_BASE}/config.yaml" -o "${CACHE_DIR}/config.yaml"; then
    log "FAIL: pull config.yaml"
    exit 1
fi

# 2) 拉所有规则
for f in private gfw cncidr lancidr applications; do
    curl_with_proxy "${RAW_BASE}/rules/${f}.yaml" \
        -o "${CACHE_DIR}/${f}.yaml" || log "warn: rules/${f}.yaml"
done

# 3) 拉所有 proxies 片段并合并成数组
PROXIES_YAML="${CACHE_DIR}/proxies.merged.yaml"
: > "$PROXIES_YAML"
for f in "${CACHE_DIR}"/../clash_yaml_cache/../*.yaml; do :; done

# 直接拉目录里所有 .yaml
PROXY_FILES=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${REPO}/contents/clash-yaml/proxies?ref=${BRANCH}" \
    2>/dev/null | grep '"name"' | grep '\.yaml' | sed 's/.*"\([^"]*\)".*/\1/' || true)

for f in $PROXY_FILES; do
    log "pull proxies/$f"
    TMP="${CACHE_DIR}/.proxy.$$"
    if curl_with_proxy "${RAW_BASE}/proxies/${f}" -o "$TMP"; then
        # 验证是数组(- 开头)
        FIRST=$(head -n1 "$TMP" | tr -d ' \t')
        if [ "$FIRST" = "-" ]; then
            cat "$TMP" >> "$PROXIES_YAML"
            echo "" >> "$PROXIES_YAML"
        else
            log "skip $f: not an array (first line: $FIRST)"
        fi
    fi
    rm -f "$TMP"
done

# 4) 处理 subscriptions/*.yaml,在线抓机场订阅
SUB_FILES=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${REPO}/contents/clash-yaml/subscriptions?ref=${BRANCH}" \
    2>/dev/null | grep '"name"' | grep '\.yaml' | sed 's/.*"\([^"]*\)".*/\1/' || true)

for f in $SUB_FILES; do
    log "pull subscriptions/$f"
    SUB="${CACHE_DIR}/.sub.$$"
    curl_with_proxy "${RAW_BASE}/subscriptions/${f}" -o "$SUB" || continue

    URL=$(grep -E "^url:" "$SUB" | head -1 | sed 's/^url:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')
    if [ -z "$URL" ]; then
        log "skip $f: no url field"
        rm -f "$SUB"
        continue
    fi

    log "fetch airport subscription: $URL"
    TMP_B64="/tmp/.sub_raw.$$"
    if curl -fsSL --max-time 60 \
            --user-agent "clash.meta" \
            "$URL" -o "$TMP_B64"; then
        # 多数机场是 base64 编码的 YAML
        if head -c4 "$TMP_B64" | grep -qv '^[{#\[]'; then
            base64 -d "$TMP_B64" > "${TMP_B64}.yaml" 2>/dev/null || cp "$TMP_B64" "${TMP_B64}.yaml"
        else
            cp "$TMP_B64" "${TMP_B64}.yaml"
        fi
        # 提取 proxies: 列表(粗暴做法: 用 awk 抓 proxies 到下一个顶级 key 之前)
        awk '
            /^proxies:/ {flag=1; print; next}
            /^[a-zA-Z_]/ && flag {flag=0}
            flag {print}
        ' "${TMP_B64}.yaml" >> "$PROXIES_YAML"
        rm -f "${TMP_B64}" "${TMP_B64}.yaml"
    fi
    rm -f "$SUB"
done

# 5) 把 proxies.merged.yaml 注入主配置(替换占位段)
log "merge proxies into config"
awk -v PROXIES_FILE="$PROXIES_YAML" '
    /# ↓↓↓ 占位;被 clash_yaml_pull.sh 合并 subscriptions\/\* 后替换 ↓↓↓/ {
        sent=1
        print
        print "  # ↓↓↓ auto-merged by clash_yaml_pull.sh at " strftime("%F %T") " ↓↓↓"
        while ((getline line < PROXIES_FILE) > 0) print line
        close(PROXIES_FILE)
        next
    }
    /# ↑↑↑ 占位结束 ↑↑↑/ {
        print
        sent=0
        next
    }
    sent && /^  proxies:[[:space:]]*\[DIRECT\]/ {
        print "  proxies: [AUTO, DIRECT, REJECT]"
        next
    }
    { print }
' "${CACHE_DIR}/config.yaml" > "${CACHE_DIR}/config.merged.yaml"

# 验证 yaml 语法(简单 grep 检查)
if ! grep -q "port:" "${CACHE_DIR}/config.merged.yaml"; then
    log "FAIL: merged yaml invalid, keep old config"
    exit 2
fi

# 6) 备份 + 替换
[ -f "$DEST_FILE" ] && cp "$DEST_FILE" "${DEST_FILE}.bak"
cp "${CACHE_DIR}/config.merged.yaml" "$DEST_FILE"
log "config written: $DEST_FILE ($(wc -c < "$DEST_FILE") bytes)"

# 7) 重启 ShellClash(如果装着)
if [ -x /etc/storage/clash.sh ] || [ -f /etc/storage/clash.sh ]; then
    log "restart ShellClash"
    /etc/storage/clash.sh restart 2>&1 | tee -a "$LOG_FILE" || log "clash restart failed"
fi

# 8) 通知
if [ -x /etc/storage/notify.sh ]; then
    /etc/storage/notify.sh "clash-yaml updated" "$(wc -l < $PROXIES_YAML) proxies, $(wc -c < $DEST_FILE) bytes" 2>/dev/null || true
fi

log "== pull done =="