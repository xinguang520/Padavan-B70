#!/bin/sh
# tailscale.sh - Tailscale 一键安装/启动脚本 (mipsle)
# 适用: Padavan 路由器 / 内存 ≥ 64 MB

STORE=/etc/storage
BIN=$STORE/bin
LOG=$STORE/logs
mkdir -p "$BIN" "$LOG" "$STORE/tailscale"

TAPPS_VER="1.48.2"
TAPPS_BASE="https://github.com/ZQCHI/MT7621-Openwrt-Tailscale-bin/releases/download/v1.48.2"

download_tailscale() {
    if [ -x "$BIN/tailscaled" ] && [ -x "$BIN/tailscale" ]; then
        echo "tailscale 已安装，跳过下载"
        return 0
    fi
    cd /tmp
    echo "[+] 拉取 tailscaled"
    curl -kfsSL -o tailscaled \
        "$TAPPS_BASE/tailscaled" && chmod +x tailscaled && mv tailscaled "$BIN/tailscaled"
    echo "[+] 拉取 tailscale"
    curl -kfsSL -o tailscale_cli \
        "$TAPPS_BASE/tailscale" && chmod +x tailscale_cli && mv tailscale_cli "$BIN/tailscale"
}

start_tailscale() {
    download_tailscale
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        "$BIN/tailscaled" \
            --statedir="$STORE/tailscale" \
            --socket="$STORE/tailscale/tailscaled.sock" \
            --tun=userspace-networking \
            >> "$LOG/tailscaled.log" 2>&1 &
        sleep 3
        "$BIN/tailscale" --socket="$STORE/tailscale/tailscaled.sock" up \
            >> "$LOG/tailscale.log" 2>&1
        echo "Tailscale 已启动，首次使用请按提示登录。"
    else
        echo "Tailscale 已在运行"
    fi
}

stop_tailscale() {
    if [ -x "$BIN/tailscale" ]; then
        "$BIN/tailscale" --socket="$STORE/tailscale/tailscaled.sock" down 2>/dev/null
    fi
    pkill -x tailscaled 2>/dev/null
    echo "Tailscale 已停止"
}

status_tailscale() {
    if pgrep -x tailscaled >/dev/null 2>&1; then
        "$BIN/tailscale" --socket="$STORE/tailscale/tailscaled.sock" status 2>&1
    else
        echo "tailscaled 未运行"
    fi
}

case "$1" in
    install)  download_tailscale ;;
    start)    start_tailscale ;;
    stop)     stop_tailscale ;;
    restart)  stop_tailscale; sleep 1; start_tailscale ;;
    status)   status_tailscale ;;
    *)
        cat <<USAGE
用法: $0 {install|start|stop|restart|status}
USAGE
        ;;
esac
