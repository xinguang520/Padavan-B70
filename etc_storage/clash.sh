#!/bin/sh
# clash.sh - ShellClash 控制包装 (由 startup.sh 调用或单独使用)
# 安装:
#   wget -qO- https://raw.githubusercontent.com/juewuy/ShellClash/master/install.sh | sh
# 之后该文件路径: /etc/storage/shellclash/clash.sh

ACTION="$1"
[ -z "$ACTION" ] && ACTION=help

case "$ACTION" in
    status)   /etc/storage/shellclash/clash -h ;;
    start)    /etc/storage/shellclash/clash -s ;;
    stop)     /etc/storage/shellclash/clash -k ;;
    restart)  /etc/storage/shellclash/clash -r ;;
    test)     /etc/storage/shellclash/clash -t ;;
    update)   /etc/storage/shellclash/clash -u ;;
    *)        /etc/storage/shellclash/clash ;;
esac
