#!/bin/sh
# sing-box.sh - sing-box 一键安装/启动脚本 (linux-mipsle)
# 适用: Padavan B70 (MT7621)。二进制装到 /etc/storage/bin, 配置在 /etc/storage/sing-box/
# 用法: $0 {install|start|stop|restart|status|version}

STORE=/etc/storage
BIN=$STORE/bin
LOG=$STORE/logs
CONF=$STORE/sing-box
mkdir -p "$BIN" "$LOG" "$CONF"

REPO="SagerNet/sing-box"

latest_ver() {
    curl -kfsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/'
}

# 选择 mipsle 资产: 优先 musl(静态), 再退回普通 mipsle
pick_asset() {
    curl -kfsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep -oE '"browser_download_url": *"[^"]*linux-mipsle[^"]*\.zip"' \
        | sed -E 's/.*"(https[^"]*)".*/\1/' \
        | sort | awk '/musl/{m=$0} {a=$0} END{print (m!=""?m:a)}'
}

download_singbox() {
    [ -x "$BIN/sing-box" ] && { echo "sing-box 已安装: $($BIN/sing-box version | head -1)"; return 0; }
    command -v unzip >/dev/null 2>&1 || {
        echo "! 缺少 unzip。插U盘装 Entware 后 opkg install unzip, 或在电脑上解压后 scp 二进制过来。"
        return 1
    }
    URL=$(pick_asset)
    [ -n "$URL" ] || { echo "! 未能从 GitHub API 获取 mipsle 资产(可能限流), 稍后重试"; return 1; }
    echo "[+] 下载 $URL"
    cd /tmp && rm -rf sb_dl && mkdir sb_dl && cd sb_dl
    curl -kfsSL -o sb.zip "$URL" || { echo "! 下载失败"; return 1; }
    unzip -oq sb.zip || { echo "! 解压失败"; return 1; }
    SB=$(find . -type f -name sing-box | head -1)
    [ -n "$SB" ] || { echo "! zip 里没找到 sing-box"; return 1; }
    chmod +x "$SB" && mv "$SB" "$BIN/sing-box"
    "$BIN/sing-box" version | head -1
}

ensure_conf() {
    [ -f "$CONF/config.json" ] && return 0
    cat > "$CONF/config.json" <<'JSON'
{
  "log": { "level": "info", "output": "/etc/storage/logs/sing-box.log" },
  "inbounds": [
    { "type": "mixed", "tag": "in", "listen": "127.0.0.1", "listen_port": 2080 }
  ],
  "outbounds": [
    { "type": "direct", "tag": "out" }
  ],
  "route": { "final": "out" }
}
JSON
    echo "[+] 已生成占位配置 $CONF/config.json (mixed 端口 2080, 直连出口)"
    echo "    请把实际节点写进 outbounds, 或用 clash 订阅转换后的 sing-box 配置替换。"
}

start_singbox() {
    download_singbox && ensure_conf || return 1
    if ! pgrep -f "/bin/sing-box run" >/dev/null 2>&1; then
        "$BIN/sing-box" run -c "$CONF/config.json" >> "$LOG/sing-box-run.log" 2>&1 &
        sleep 2
        echo "sing-box 已启动 (pid $(pgrep -f 'sing-box run' | head -1))"
    else
        echo "sing-box 已在运行"
    fi
}

stop_singbox() {
    pkill -f "/bin/sing-box run" 2>/dev/null
    echo "sing-box 已停止"
}

case "$1" in
    install)  download_singbox ;;
    start)    start_singbox ;;
    stop)     stop_singbox ;;
    restart)  stop_singbox; sleep 1; start_singbox ;;
    status)   pgrep -f "/bin/sing-box run" >/dev/null 2>&1 && \
                  { echo "运行中"; "$BIN/sing-box" version | head -1; } || echo "未运行" ;;
    version)  download_singbox >/dev/null 2>&1 && "$BIN/sing-box" version | head -1 ;;
    *)  cat <<USAGE
用法: $0 {install|start|stop|restart|status|version}
配置文件: $CONF/config.json
USAGE
        ;;
esac
