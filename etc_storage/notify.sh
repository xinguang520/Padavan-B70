#!/bin/sh
# ---------------------------------------------------------------
# notify.sh
# 推送告警 / 状态变更到 Telegram Bot 或 Email
# 配置: /etc/storage/notify.conf (key=value)
# 用法: notify.sh <title> <message> [level]
#   level: info | warn | err  (默认 info)
# ---------------------------------------------------------------

set -e

CONF="/etc/storage/notify.conf"
LOG="/etc/storage/notify.log"

if [ ! -f "$CONF" ]; then
    # 静默: 未配置就不发
    exit 0
fi

. "$CONF"

TITLE="${1:-no-title}"
MSG="${2:-}"
LEVEL="${3:-info}"

# Padavan host 信息
HOST=$(uname -n 2>/dev/null || echo "B70")
IP=$(ip -4 addr show br0 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
[ -z "$IP" ] && IP=$(nvram get lan_ipaddr 2>/dev/null)
[ -z "$IP" ] && IP="?"

FULL_MSG="[$LEVEL] [$HOST @ $IP]
$TITLE
$MSG"

log_line() {
    printf "[%s] %s\n" "$(date '+%F %T')" "$FULL_MSG" >> "$LOG"
}

# ---- Telegram ----
tg_send() {
    [ -z "$TG_BOT_TOKEN" ] && return
    [ -z "$TG_CHAT_ID" ] && return

    # curl 走代理(避免 router 自己没法访问 telegram)
    PROXY_ARG=""
    [ "$TG_USE_PROXY" = "1" ] && PROXY_ARG="--proxy ${TG_PROXY_ADDR:-http://127.0.0.1:7890}"

    curl -fsSL --max-time 15 $PROXY_ARG \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=${FULL_MSG}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        > /dev/null 2>&1
}

# ---- Email (SMTP, 通过 curl smtp://) ----
mail_send() {
    [ -z "$SMTP_HOST" ] && return
    [ -z "$SMTP_TO" ] && return

    # Padavan 没装 sendmail, 用 curl 直接 SMTP
    FROM="${SMTP_FROM:-root@${HOST}}"
    SUBJECT="${TITLE} [$LEVEL]"
    BODY="${FULL_MSG}"

    # 用 curl smtp:// 需要带 --mail-from/--mail-rcpt + 文件 body
    TMP="/tmp/.mail.$$"
    {
        printf "From: %s\n" "$FROM"
        printf "To: %s\n" "$SMTP_TO"
        printf "Subject: %s\n" "$SUBJECT"
        printf "Date: %s\n" "$(date -R 2>/dev/null || date)"
        printf "\n%s\n" "$BODY"
    } > "$TMP"

    AUTH=""
    [ -n "$SMTP_USER" ] && AUTH="--user ${SMTP_USER}:${SMTP_PASS}"

    curl -v --ssl --max-time 30 \
        "smtps://${SMTP_HOST}:${SMTP_PORT:-465}" \
        $AUTH \
        --mail-from "$FROM" \
        --mail-rcpt "$SMTP_TO" \
        -T "$TMP" 2>>"$LOG" >>"$LOG" || true

    rm -f "$TMP"
}

log_line
tg_send
mail_send

exit 0