#!/bin/sh
# aria2.sh - aria2 RPC 控制脚本
# Padavan 已自带 aria2c,本脚本只管理 RPC 与下载目录

ARIA2_RPC_PORT=6800
ARIA2_RPC_SECRET=""
ARIA2_DIR=/etc/storage/aria2
STORE=$ARIA2_DIR
DOWN=$ARIA2_DIR/downloads
CONF=$ARIA2_DIR/aria2.conf
LOG=/etc/storage/logs/aria2.log

mkdir -p "$DOWN"
[ -f "$CONF" ] || cat > "$CONF" <<EOF
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=$ARIA2_RPC_PORT
rpc-secret=$ARIA2_RPC_SECRET
dir=$DOWN
disk-cache=16M
max-connection-per-server=8
max-concurrent-downloads=4
continue=true
input-file=$ARIA2_DIR/aria2.session
save-session=$ARIA2_DIR/aria2.session
save-session-interval=60
log=$LOG
log-level=warn
EOF
touch "$ARIA2_DIR/aria2.session"

start() {
    if pgrep -x aria2c >/dev/null 2>&1; then
        echo "aria2 已在运行"
        return
    fi
    aria2c --conf-path="$CONF" -D
    sleep 1
    echo "aria2 RPC 端口: $ARIA2_RPC_PORT (无密码)"
    echo "Web UI 推荐使用 AriaNg: 把静态文件扔到 /etc/storage/www/ 下"
}

stop() {
    pkill -x aria2c
    echo "aria2 已停止"
}

status() {
    if pgrep -x aria2c >/dev/null 2>&1; then
        curl -s "http://127.0.0.1:$ARIA2_RPC_PORT/jsonrpc" \
             -d '{"jsonrpc":"2.0","method":"aria2.getGlobalStat","id":1}' && echo
    else
        echo "aria2 未运行"
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)
        cat <<USAGE
用法: $0 {start|stop|restart|status}
RPC 端口: $ARIA2_RPC_PORT
下载目录: $DOWN
USAGE
        ;;
esac
