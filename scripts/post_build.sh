#!/bin/bash
# post_build.sh - 在 build_firmware_modify 完成后执行
# 目的：
#   1. 将 /etc_storage 启动脚本注入 firmware 镜像的 jffs2 区域
#   2. 输出 checksum 与版本信息
# Padavan 项目下调用: bash post_build.sh B70

set -e

TNAME="${1:-B70}"
ROOT=$(cd "$(dirname "$0")" && pwd)
IMG_DIR="$ROOT/images"

echo "==== post_build.sh for $TNAME ===="

if [ ! -d "$IMG_DIR" ]; then
    echo "FATAL: images dir not found at $IMG_DIR"
    exit 1
fi

# ---- 1. 打包 /etc_storage 脚本 ----
if [ -d "$ROOT/scripts/etc_storage" ]; then
    echo "[+] Bundling /etc_storage scripts"
    # 打包 etc_storage 全部内容(含 www/ 子目录), 新脚本自动进包
    tar czf "$IMG_DIR/etc_storage_scripts.tar.gz" \
        -C "$ROOT/scripts/etc_storage" .

    cd "$IMG_DIR"
    sha256sum etc_storage_scripts.tar.gz > etc_storage_scripts.sha256
    ls -lah
fi

# ---- 2. 生成 checksum ----
for img in "$IMG_DIR"/*.trx; do
    [ -f "$img" ] || continue
    sha256sum "$img" > "$img.sha256"
    echo "[+] $(basename "$img") size=$(du -h "$img" | cut -f1)"
done

# ---- 3. 生成 release 摘要 ----
cat > "$IMG_DIR/BUILD_INFO.txt" <<EOF
=========================================
B70 Padavan 固件构建摘要
=========================================
Build date : $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Commit     : ${GITHUB_SHA:-local}
TNAME      : $TNAME

固件主文件 (上传到 Breed):
$(ls -la "$IMG_DIR"/*.trx 2>/dev/null | awk '{print $NF, "(" $5 " bytes)"}' || echo "  (none)")

辅助脚本 (首次启动后输入以下命令安装):
  cd /tmp && wget -O- http://your-host/etc_storage_scripts.tar.gz | tar xzf -
  cp /tmp/startup.sh /etc/storage/ && chmod +x /etc/storage/startup.sh
  /etc/storage/startup.sh install
EOF

echo "==== post_build.sh done ===="
