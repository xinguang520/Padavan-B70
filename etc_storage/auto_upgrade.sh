#!/bin/sh
# auto_upgrade.sh - Padavan 自动检测上游固件更新并提示/自刷
# 使用：
#   - 在 Padavan Web → 系统管理 → 系统设置 → 开机后执行脚本 填一行:
#       /etc/storage/auto_upgrade.sh &
#   - 或在 SSH 里手动跑: /etc/storage/auto_upgrade.sh check | upgrade | status

# ============ 配置 ============
# 替换成你 fork 后仓库的 owner/repo
FIRMWARE_REPO="yourname/Padavan-build"
# 你发布的 .trx 直链(三种方式任一)
#
# 选项 A: GitHub Actions 上传到 Release tag, 直链格式:
#   FIRM_URL="https://github.com/$FIRMWARE_REPO/releases/latest/download/B70.trx"
#
# 选项 B: 自己 VPS / OSS / Web 托管:
#   FIRM_URL="https://your.cdn.example.com/B70.trx"
#
# 选项 C: jsDelivr 代理 GitHub Release:
#   FIRM_URL="https://cdn.jsdelivr.net/gh/$FIRMWARE_REPO@latest/B70.trx"
#
FIRM_URL="https://github.com/$FIRMWARE_REPO/releases/latest/download/B70.trx"

STATE_DIR=/etc/storage/.upgrade
TMP_DIR=/tmp
mkdir -p "$STATE_DIR"

# 远程大小/etag 用于轮询，不真去比对整个 .trx
# 如果你有 Release API JSON,这里改写为 hits jq 提取 tag_name

LAST_SIZE_FILE="$STATE_DIR/last_remote_size"
LAST_TAG_FILE="$STATE_DIR/last_known_tag"
LOG=/etc/storage/logs/auto_upgrade.log

mkdir -p /etc/storage/logs

# ============ 检测 ============
probe_remote() {
    # 不下载整个镜像,只用 HEAD 拉大小 + Last-Modified
    # -s 安静模式 -I 仅 HEAD -L 跟随 redirect
    # 没用 curl --max-time 显式上限
    curl -sILk --max-time 12 "$FIRM_URL" \
        | tee "$STATE_DIR/headers.txt" >/dev/null 2>&1
    # 提取 Content-Length (十进制字节)
    grep -i '^content-length:' "$STATE_DIR/headers.txt" \
        | tail -1 | awk '{print $2}' | tr -d '\r'
}

# ============ 模式 ============
case "$1" in
    check)
        SIZE=$(probe_remote)
        [ -z "$SIZE" ] && { echo "[$(date)] 检测失败: $FIRM_URL 无响应" | tee -a "$LOG" >&2; exit 1; }
        PREV=$(cat "$LAST_SIZE_FILE" 2>/dev/null || echo 0)
        if [ "$SIZE" != "$PREV" ]; then
            echo "NEW"
            echo "$SIZE" > "$LAST_SIZE_FILE"
        else
            echo "OK"
        fi
        ;;
    upgrade)
        SIZE=$(probe_remote)
        PREV=$(cat "$LAST_SIZE_FILE" 2>/dev/null || echo 0)
        if [ -z "$SIZE" ] || [ "$SIZE" = "$PREV" ]; then
            echo "无需升级 (size=$SIZE, prev=$PREV)"
            exit 0
        fi
        echo "[$(date)] 开始下载新固件: $FIRM_URL ($SIZE bytes)" | tee -a "$LOG"
        curl -Lk --max-time 120 -o "$TMP_DIR/firmware_new.trx" "$FIRM_URL" || {
            echo "[$(date)] 下载失败" | tee -a "$LOG"
            exit 1
        }
        # 校验
        DL_SIZE=$(stat -c%s "$TMP_DIR/firmware_new.trx" 2>/dev/null || stat -f%z "$TMP_DIR/firmware_new.trx")
        if [ "$DL_SIZE" -ne "$SIZE" ] 2>/dev/null; then
            echo "[$(date)] 大小不符: 期望 $SIZE, 实际 $DL_SIZE (取消)" | tee -a "$LOG"
            rm -f "$TMP_DIR/firmware_new.trx"
            exit 2
        fi

        # Padavan 用 mtd 写入 firmware 分区:
        # 因为 /dev/mtdblock 设备路径取决于机器, 通常写法是:
        #   mtd -r write /tmp/firmware_new.trx firmware
        # 但更稳的是调 Padavan 的 updater 脚本(若 web UI 提供)
        # 否则需要人工进入 web 完成最后一步(下面给出通知路径)

        echo "[$(date)] 固件已下载到 $TMP_DIR/firmware_new.trx ($DL_SIZE bytes)" | tee -a "$LOG"

        # 通知用户(可选): 上传一行日志到 Padavan 后台日志
        # 也可用 curl POST 到 webhook, 这里仅写本地日志
        cat >> "$LOG" <<EOF

========== 升级待确认 ===========
请进路由后台 → 系统管理 → 固件升级 → 选择备份的本地固件
或在你的 SSH 会话里手动执行:
    mtd -r write $TMP_DIR/firmware_new.trx firmware

确认前可以先打开另一终端压力测试:
    ping -c 100 -i 1 192.168.123.1
=================================
EOF
        echo "已下载,等待人工确认刷新。"
        ;;
    auto-upgrade)        # 全自动:无人值守直接刷(慎用!)
        "$0" upgrade >/dev/null 2>&1
        [ -f "$TMP_DIR/firmware_new.trx" ] && \
            mtd -r write "$TMP_DIR/firmware_new.trx" firmware
        ;;
    status)
        echo "last remote size: $(cat "$LAST_SIZE_FILE" 2>/dev/null || echo unknown)"
        echo "current check     : $(probe_remote)"
        echo "target URL        : $FIRM_URL"
        ;;
    *)
        cat <<'USAGE'
用法: auto_upgrade.sh {check | upgrade | status | auto-upgrade}
  check        仅探测,不下载
  upgrade      下载新固件并放到 /tmp,等你手动在 Web 后台刷
  auto-upgrade 全自动(不建议),刷完会立即重启
USAGE
        ;;
esac
