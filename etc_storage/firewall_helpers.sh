#!/bin/sh
# firewall_helpers.sh - iptables 透明代理 / subnet router 辅助
# 适用 Padavan,默认接受内网 192.168.123.0/24
# Tailscale 用于子网路由时调用;ShellClash 用于透明代理时调用

LAN=192.168.123.0/24
TUN=tun0

enable_clash_tproxy() {
    # 假设 clash 在 7892 端口开 redir-port (默认配置)
    REDIR_PORT=7892
    iptables -t nat -N CLASH 2>/dev/null
    iptables -t nat -F CLASH
    iptables -t nat -A CLASH -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A CLASH -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A CLASH -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A CLASH -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A CLASH -p tcp -j REDIRECT --to-ports $REDIR_PORT
    iptables -t nat -I PREROUTING 1 -s $LAN -j CLASH
    echo "Clash 透明代理已启用"
}

disable_clash_tproxy() {
    iptables -t nat -D PREROUTING -s $LAN -j CLASH 2>/dev/null
    iptables -t nat -F CLASH 2>/dev/null
    iptables -t nat -X CLASH 2>/dev/null
    echo "Clash 透明代理已关闭"
}

enable_ts_subnet_routes() {
    # tailscale up --advertise-routes=192.168.123.0/24
    iptables -A FORWARD -i $TUN -j ACCEPT
    iptables -A FORWARD -o $TUN -j ACCEPT
    iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -o br0 -j MASQUERADE
    echo "Tailscale 子网路由已启用"
}

disable_ts_subnet_routes() {
    iptables -D FORWARD -i $TUN -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o $TUN -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -s 100.64.0.0/10 -o br0 -j MASQUERADE 2>/dev/null
    echo "Tailscale 子网路由已关闭"
}

case "$1" in
    clash-on)    enable_clash_tproxy ;;
    clash-off)   disable_clash_tproxy ;;
    ts-route-on) enable_ts_subnet_routes ;;
    ts-route-off) disable_ts_subnet_routes ;;
    *)
        cat <<USAGE
用法: $0 {clash-on|clash-off|ts-route-on|ts-route-off}
USAGE
        ;;
esac
