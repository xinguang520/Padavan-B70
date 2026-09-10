#!/bin/sh
# /etc/storage/startup.sh
# Padavan 路由器开机启动脚本
# 管理 ShellClash (常开) + Tailscale (按需) + aria2 (按需) + 自动升级 + 通知 + Dashboard
# 安装方法:
#   1. SSH 进路由 (admin@192.168.123.1)
#   2. wget ... startup.sh -O /etc/storage/startup.sh
#   3. chmod +x /etc/storage/startup.sh
#   4. /etc/storage/startup.sh install   # 安装开机自启

STORE=/etc/storage
BIN=$STORE/bin
LOG=$STORE/logs
WWW=$STORE/www
mkdir -p "$BIN" "$LOG" "$WWW"

# ====== 配置 ======
RELEASE_BASE="https://github.com/juewuy/ShellClash/releases/download"
TAPPS_REPO="https://github.com/tailscale/tailscale/releases/download"
ARIA2_WEBUI="https://github.com/ziahamza/webui-aria2/archive/refs/heads/master.tar.gz"

# GitHub 仓库 - 你 fork 之后的 user/repo
GITHUB_REPO="${GITHUB_REPO:-YOUR_USER/YOUR_REPO}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# 软硬件检测
ARCH=$(uname -m)
[ "$ARCH" = "mips" ] && ARCH="mipsle-softfloat"

# ====== ShellClash 控制 ======
clash_start() {
    if [ ! -x "$BIN/clash" ] && [ ! -x "$BIN/clash-meta" ]; then
        echo "[$(date)] clash 未安装" >> "$LOG/clash.log"
        return 1
    fi
    if ! pgrep -f "/bin/clash" >/dev/null 2>&1; then
        BIN_FILE="$BIN/clash"
        [ -x "$BIN/clash-meta" ] && BIN_FILE="$BIN/clash-meta"
        "$BIN_FILE" -d "$STORE/clash" > "$LOG/clash.log" 2>&1 &
        echo "[$(date)] ShellClash 启动" >> "$LOG/clash.log"
    fi
}

clash_stop() {
    pkill -f "/bin/clash" 2>/dev/null
    echo "[$(date)] ShellClash 停止" >> "$LOG/clash.log"
}

clash_restart() { clash_stop; sleep 2; clash_start; }

# ====== Tailscale 控制 ======
tailscale_start() {
    [ -x "$BIN/tailscaled" ] || { echo "tailscaled 未安装"; return 1; }
    [ -d "$STORE/tailscale" ] || mkdir -p "$STORE/tailscale"
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        "$BIN/tailscaled" --statedir="$STORE/tailscale" \
                         --socket="$STORE/tailscale/tailscaled.sock" \
                         --tun=userspace-networking \
                         > "$LOG/tailscaled.log" 2>&1 &
        sleep 3
        "$BIN/tailscale" --socket="$STORE/tailscale/tailscaled.sock" up \
                         > "$LOG/tailscale.log" 2>&1
        echo "[$(date)] Tailscale 启动" >> "$LOG/tailscale.log"
    fi
}

tailscale_stop() {
    "$BIN/tailscale" --socket="$STORE/tailscale/tailscaled.sock" down 2>/dev/null
    pkill -x tailscaled 2>/dev/null
    echo "[$(date)] Tailscale 停止" >> "$LOG/tailscale.log"
}

# ====== aria2 控制 ======
ARIA2_RPC_PORT=6800
ARIA2_DIR="$STORE/aria2"
[ -d "$ARIA2_DIR" ] || mkdir -p "$ARIA2_DIR"

aria2_start() {
    if ! pgrep -x aria2c >/dev/null 2>&1; then
        aria2c --enable-rpc \
               --rpc-listen-port=$ARIA2_RPC_PORT \
               --dir="$ARIA2_DIR/downloads" \
               --conf-path="$ARIA2_DIR/aria2.conf" \
               --log="$LOG/aria2.log" \
               --daemon
        echo "[$(date)] aria2 启动: RPC :$ARIA2_RPC_PORT" >> "$LOG/aria2.log"
    fi
}

aria2_stop() {
    pkill -x aria2c 2>/dev/null
    echo "[$(date)] aria2 停止" >> "$LOG/aria2.log"
}

# ====== sing-box 控制 (委托给 sing-box.sh) ======
sb() {
    if [ -x "$STORE/sing-box.sh" ]; then
        sh "$STORE/sing-box.sh" "$@"
    else
        echo "sing-box.sh 不存在, 先拉取: curl -kfsSL https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/etc_storage/sing-box.sh -o $STORE/sing-box.sh && chmod +x $STORE/sing-box.sh"
    fi
}

# ====== 1) 拉取 Clash YAML 配置(从 GitHub 仓库) ======
yaml_pull() {
    if [ -x "$STORE/clash_yaml_pull.sh" ]; then
        CLASH_REPO="$GITHUB_REPO" \
        CLASH_BRANCH="$GITHUB_BRANCH" \
        USE_PROXY=1 \
        PROXY_ADDR="http://127.0.0.1:7890" \
        sh "$STORE/clash_yaml_pull.sh"
    fi
}

# ====== 2) Tailscale 自动升级 ======
ts_upgrade() {
    if [ -x "$STORE/tailscale_upgrade.sh" ]; then
        TAILSCALE_REPO="tailscale/tailscale" \
        sh "$STORE/tailscale_upgrade.sh"
    fi
}

# ====== 3) Dashboard 数据采集 ======
dashboard_update() {
    if [ -x "$STORE/www/monitor.sh" ]; then
        # monitor.sh 内含 shebang 检查,直接调 php
        MONITOR_PHP=$(command -v php-cli 2>/dev/null || command -v php 2>/dev/null)
        [ -n "$MONITOR_PHP" ] && "$MONITOR_PHP" "$STORE/www/monitor.sh" json >/dev/null 2>&1
    fi
}

# ====== 4) 固件升级检测 ======
fw_check() {
    if [ -x "$STORE/auto_upgrade.sh" ]; then
        # 用路由器自己的 IP 检测 WAN 是否通
        sh "$STORE/auto_upgrade.sh" check
    fi
}

# ====== 安装/卸载 ======
install_autostart() {
    # Padavan: 把 startup.sh boot 写入 post_wan_action.sh
    if ! grep -q "startup.sh boot" "$STORE/post_wan_action.sh" 2>/dev/null; then
        echo "/etc/storage/startup.sh boot &" >> "$STORE/post_wan_action.sh" 2>/dev/null
    fi
    # 同时 rc.unslung(兼容老 Padavan)
    if ! grep -q "startup.sh boot" /etc/storage/rc.unslung 2>/dev/null; then
        echo "$0 boot &" >> /etc/storage/rc.unslung 2>/dev/null
    fi

    # 注册 cron
    CRON_FILE="/etc/storage/crontabs/root"
    mkdir -p "$(dirname "$CRON_FILE")"

    cat >> "$CRON_FILE" <<EOF
# B70 Padavan 自定义定时任务
0 3 * * * /etc/storage/startup.sh yaml-pull  >> /etc/storage/logs/yaml_pull.log 2>&1
0 4 * * 0 /etc/storage/startup.sh ts-upgrade >> /etc/storage/logs/ts_upgrade.log 2>&1
*/10 * * * * /etc/storage/startup.sh fw-check   >> /etc/storage/logs/fw_check.log 2>&1
*/1 * * * *  /etc/storage/startup.sh dashboard  >> /etc/storage/logs/dashboard.log 2>&1
EOF

    # 启动 crond(如果没启)
    pgrep crond >/dev/null || /usr/sbin/crond -L /etc/storage/logs/cron.log

    # Web 后台开机执行脚本二次确认
    echo "已设置开机自启。请到 Web: 系统管理 → 高级设置 → 开机执行脚本 二次确认。"
}

# ====== 主入口 ======
case "$1" in
    boot)
        # 等待 WAN 起来
        sleep 30
        # Clash(常开)
        clash_start
        # 拉 yaml
        yaml_pull
        clash_restart
        # Dashboard 数据
        dashboard_update
        # 固件检测
        fw_check
        # 通知启动成功
        [ -x "$STORE/notify.sh" ] && "$STORE/notify.sh" "B70 boot" "$(date '+%F %T')" info 2>/dev/null || true
        ;;
    install)   install_autostart ;;
    uninstall)
        rm -f "$BIN/clash"* "$BIN/tailscale"* "$BIN/aria2c" "$BIN/sing-box" 2>/dev/null
        echo "已清理"
        ;;
    clash-start)    clash_start ;;
    clash-stop)     clash_stop ;;
    clash-restart)  clash_restart ;;
    ts-start)       tailscale_start ;;
    ts-stop)        tailscale_stop ;;
    ts-upgrade)     ts_upgrade ;;
    aria2-start)    aria2_start ;;
    aria2-stop)     aria2_stop ;;
    sb-install)     sb install ;;
    sb-start)       sb start ;;
    sb-stop)        sb stop ;;
    sb-restart)     sb restart ;;
    sb-status)      sb status ;;
    yaml-pull)      yaml_pull ;;
    fw-check)       fw_check ;;
    dashboard)      dashboard_update ;;
    *)
        cat <<USAGE
用法:
  $0 boot                          开机自启 (由 post_wan_action.sh 调用)
  $0 install                       注册开机自启 + 注册 cron
  $0 clash-start | clash-stop      ShellClash 控制
  $0 clash-restart                 ShellClash 重启
  $0 ts-start    | ts-stop         Tailscale 控制
  $0 ts-upgrade                    Tailscale 升级检测
  $0 aria2-start  | aria2-stop     aria2 控制
  $0 sb-install                    安装 sing-box 二进制(mipsle)
  $0 sb-start | sb-stop | sb-restart | sb-status   sing-box 控制
  $0 yaml-pull                     拉取 GitHub Clash YAML 配置
  $0 fw-check                      检测 GitHub Release 新固件
  $0 dashboard                     更新 dashboard 数据
  $0 uninstall                     清理二进制
USAGE
        ;;
esac