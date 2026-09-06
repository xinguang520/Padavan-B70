# 极路由 B70 Padavan 固件自动编译 + 运行时套件 (GitHub Actions)

> 自带 **aria2 + PHP 探针**（编译进固件）。  
> **ShellClash（常开）+ Tailscale（按需常驻）+ aria2 + OTA 自动升级 + Telegram/邮件通知 + Dashboard** 一次打包。



---

## 🚀 5 步在 github.com 上编译你的固件

你已刷好不死后台（Breed），所以**直接从第 3 步开始**。

### 步骤 1️⃣ Fork 仓库

打开 GitHub 推荐的**任一底仓**（推荐第一个）：

- **【推荐】** [`zyj20200/Padavan-B70`](https://github.com/zyj20200/Padavan-B70)（即将本目录所有内容推送过去的官方底仓）
- 或 [`chenxudong2020/Padavan-build`](https://github.com/chenxudong2020/Padavan-build)

点右上角 **`Fork`** 按钮 → 选你自己的 GitHub 账号 → 等 fork 完成（5-10 秒）。

> Fork 后你的仓库地址是 `https://github.com/<你的用户名>/Padavan-B70`

### 步骤 2️⃣ 把本目录所有文件 push 到 fork 仓库

本目录 `b70-padavan-build/` 里已经包含所有必要的文件。你有两种推送方式：

#### 方式 A：本地直接 push（推荐，简单）

```bash
cd b70-padavan-build
git init
git add .
git commit -m "B70 Padavan init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/Padavan-B70.git
git push -u origin main
```

#### 方式 B：在 GitHub 网页上传（不用 Git）

1. 进你 fork 的仓库页面
2. 点 **`Add file → Upload files`**
3. 把 `b70-padavan-build/` 里**所有文件+目录**直接拖进上传框
4. 滚到底 → **`Commit changes`**

> ⚠️ 一定要带 `.github/`、`configs/`、`scripts/`、`etc_storage/`、`clash-yaml/`、`www/` 这些目录（开头是点的目录也要拖进去，必要时用 GitHub Desktop 客户端）

### 步骤 3️⃣ 启用 GitHub Actions

1. 进你 fork 的仓库页面 → 顶部 **`Actions`** 标签
2. 看到一个黄底提示：**"Workflows aren't being run on this forked repository"**
3. 点中间绿色按钮 **`I understand my workflows, go ahead and enable them`**

### 步骤 4️⃣ 触发首次编译

**最简方式（必做）：**

- 回到仓库主页 → 右上角 **`★ Star`** 一下（已 Star 过先取消再点）
- 这一步会让 GitHub 触发 workflow（即使没 push 过代码也行）

**或者：**

- **`Actions` 标签 → 左侧 `Padavan CI B70` → 右侧 `Run workflow` → 绿色 Run workflow 按钮**

等 **15-30 分钟**（首次需要下载工具链）。

**怎么看日志：**

- **`Actions` → 点当前跑的那条 → 点 `build` → 展开 `Build B70 firmware` 这一步**
- 看到 `Build done` 就成了

### 步骤 5️⃣ 拿固件

跑成功后：

- **`Actions` → 当前 run → 滚到底 → `Artifacts` → 下载 `B70-firmware-xxxx.zip`**
- 解压，里面有 `B70_3.4.3.9.trx`

把这个 `.trx` 文件**备用**。

### 步骤 6️⃣ 在 Breed 里刷新

> 你已经刷过 Breed，跳过此步；直接刷新的 `.trx` 即可。

1. 浏览器进 Breed：`http://192.168.1.1/`（按住 RESET 上电 5 秒）
2. 左侧 **`固件更新`**
3. **勾选 "擦除 flash 所有数据"**（首次刷第三方必做）
4. 选择 `B70_3.4.3.9.trx` → 点 **`上传`**
5. 等路由自动重启 → 浏览器开 **`http://192.168.123.1/`** → 用户名 `admin` / 密码 `admin`

---

## 📦 完整功能清单

| 模块                  | 来源                 | 体积      | 控制命令                                                      |
| ------------------- | ------------------ | ------- | --------------------------------------------------------- |
| **aria2**           | 编译进 firmware       | ~1.5 MB | `aria2.sh start/stop`                                     |
| **PHP 探针**          | 编译进 firmware       | <100 KB | `http://192.168.123.1/probe.php`                          |
| **ShellClash**      | 首次启动拉取 (jffs2)     | ~10 MB  | `startup.sh clash-start`                                  |
| **Tailscale**       | 首次启动拉取 (jffs2)     | ~8 MB   | `tailscale.sh install`                                    |
| **Clash YAML**      | 仓库托管 → 路由器 cron 拉取 | -       | `startup.sh yaml-pull`                                    |
| **Tailscale 自动升级**  | cron 每周日检查         | -       | `startup.sh ts-upgrade`                                   |
| **OTA 升级**          | cron 每 10 分钟检测     | -       | `startup.sh fw-check`                                     |
| **Telegram / 邮件通知** | 事件触发               | -       | `notify.sh`                                               |
| **Dashboard 面板**    | cron 每分钟刷新         | -       | `http://192.168.123.1/cgi-bin/storage/www/dashboard.html` |

---

## 🔧 路由器首次开箱配置

### 1) SSH 进路由

```
ssh admin@192.168.123.1     # 密码 admin
```


### 2) 上传本仓库的脚本到路由器

**方式 A：U盘**（最稳）

把 `etc_storage/` 内容拷到 U 盘根目录，插入路由器 USB，执行：

```bash
mkdir -p /tmp/usb
mount -t vfat /dev/sda1 /tmp/usb 2>/dev/null || mount -t ext4 /dev/sda1 /tmp/usb
cp -r /tmp/usb/etc_storage/* /etc/storage/
chmod +x /etc/storage/*.sh
umount /tmp/usb
```

**方式 B：scp / WinSCP**

```bash
scp -r etc_storage/* admin@192.168.123.1:/tmp/
ssh admin@192.168.123.1
mkdir -p /etc/storage/bin /etc/storage/logs /etc/storage/www
cp /tmp/*.sh /etc/storage/
chmod +x /etc/storage/*.sh
```

**方式 C：直接 GitHub raw 拉**

```bash
# 在路由器 SSH 内直接拉
GITHUB_REPO="<你的用户名>/Padavan-B70"
mkdir -p /etc/storage/bin /etc/storage/logs /etc/storage/www
for f in startup.sh clash_yaml_pull.sh tailscale_upgrade.sh notify.sh \
         firewall_helpers.sh auto_upgrade.sh clash.sh tailscale.sh aria2.sh; do
    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/etc_storage/${f}" \
         -o "/etc/storage/${f}"
done
curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/www/dashboard.html" \
     -o "/etc/storage/www/dashboard.html"
chmod +x /etc/storage/*.sh
```

### 3) 安装 ShellClash + Tailscale

```bash
# ShellClash（一键）
sh -c "$(curl -kfsSl https://raw.githubusercontent.com/juewuy/ShellClash/master/install.sh)"
# 选 1 (安装到 /etc/storage)，内核选 clash-meta

# Tailscale（我们的脚本一键装）
/etc/storage/tailscale.sh install
/etc/storage/tailscale.sh start

# aria2（按需）
/etc/storage/aria2.sh start
```

### 4) 注册开机自启 + cron

```bash
/etc/storage/startup.sh install
```

这会：

- 把 `startup.sh boot` 写入 `/etc/storage/post_wan_action.sh`
- 注册 4 个 cron（yaml 每天拉、tailscale 每周日升级、固件每 10 分钟查、dashboard 每分钟）

### 5) Web 后台二次确认

浏览器 `192.168.123.1` → **`系统管理`** → **`高级设置`** → **`开机执行脚本`**：

```
/etc/storage/startup.sh boot &
```

填进去保存。

---

## 🎯 日常使用

### 开关服务

```bash
/etc/storage/startup.sh                  # 看所有命令

/etc/storage/startup.sh clash-start      # 开 ShellClash
/etc/storage/startup.sh clash-stop       # 关
/etc/storage/startup.sh clash-restart    # 重启(配置改完用这个)

/etc/storage/startup.sh ts-start         # 开 Tailscale
/etc/storage/startup.sh ts-stop          # 关
/etc/storage/startup.sh ts-upgrade       # 手动检查升级

/etc/storage/startup.sh aria2-start      # 开 aria2
/etc/storage/startup.sh aria2-stop       # 关

/etc/storage/startup.sh yaml-pull        # 手动从 GitHub 拉 Clash 配置
/etc/storage/startup.sh fw-check         # 手动检测 GitHub Release 新固件
/etc/storage/startup.sh dashboard        # 手动刷新 Dashboard 数据
```

### 添加你自己的节点 / 改 Clash 规则

**两种方式任选：**

#### 方式 1：直接在 GitHub 仓库改（推荐）

1. 进你 fork 的仓库 → 进入 `clash-yaml/` 目录
2. **加新节点：** 在 `proxies/` 下点 `Add file → Create new file`，文件名 `my-vps.yaml`：
   ```yaml
   - name: "my-vps"
     type: vmess
     server: vps.example.com
     port: 443
     uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     alterId: 0
     cipher: auto
     tls: true
   ```
3. **加机场订阅：** 编辑 `subscriptions/airport-1.yaml`，把机场给你的 URL 填进 `url:` 字段
4. **改主配置：** 编辑 `config.yaml`，改完保存即可
5. **Commit changes**

之后路由器每天凌晨 03:00 自动拉新（也随时可手动 `/etc/storage/startup.sh yaml-pull`）。

#### 方式 2：SSH 直接改（不重启生效）

```bash
vi /etc/storage/clash/config.yaml        # 直接改
/etc/storage/startup.sh clash-restart    # 重启 ShellClash
```

### 看 Dashboard

- **`http://192.168.123.1/cgi-bin/storage/www/dashboard.html`**

或 Padavan 后台菜单里手动加个链接指向这个 URL。

显示 CPU / 内存 / 磁盘 / 服务状态 / WAN IP / 是否检测到新固件，每 10s 自动刷新。

### 配 Telegram 通知

1. Telegram `@BotFather` → `/newbot` → 拿 `bot_token`
2. 给你自己的 bot 发条消息，然后浏览器访问：
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
   找到 `"chat":{"id":123456789}` 里的数字（你的 chat_id）
3. 编辑 `/etc/storage/notify.conf`：
   ```bash
   vi /etc/storage/notify.conf
   ```
   填入：

```bash
TG_BOT_TOKEN="1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
TG_CHAT_ID="123456789"
TG_USE_PROXY="1"
TG_PROXY_ADDR="http://127.0.0.1:7890"
```

保存后 `/etc/storage/notify.sh "测试" "通知已配置 OK"` 测试一下。

### 配邮件通知

`notify.conf` 里：

```bash
SMTP_HOST="smtp.gmail.com"
SMTP_PORT="465"
SMTP_USER="you@gmail.com"
SMTP_PASS="xxxx-xxxx-xxxx-xxxx"   # Gmail 用应用专用密码
SMTP_FROM="b70@hiwifi.cn"
SMTP_TO="you@gmail.com"
```

支持 Gmail / Outlook / QQ 邮箱 / 自建 SMTP。

### 配 Tailscale

1. Tailscale 后台 → `Settings → Personal Settings → Reusable short-lived auth keys` → 生成一个 key（设过期时间 90 天）
2. 路由器：

```bash
/etc/storage/tailscale.sh authkey tskey-auth-xxxxxxxxxxxxxx
/etc/storage/tailscale.sh start
```

1. Tailscale 后台 `Machines` 应该看到 `B70` 节点。

---

## 🔄 CI 自动重编 + OTA

### CI 何时自动跑？

| 触发                                | 自动化 | 备注                         |
| --------------------------------- | --- | -------------------------- |
| 改任何 `.config / .sh / .yml` 后 push | ✅   | workflow 头 `push:` 段       |
| 每天 UTC 0:00                       | ✅   | `schedule.cron: 0 0 * * *` |
| 你手动点 `Run workflow`               | ✅   | Actions 页                  |
| Star / Unstar 仓库                  | ✅   | 强迫触发用                      |

### Release 自动发布

`Padavan_CI_B70.yml` 最后一步 `Publish to Release` 会在以下条件时自动发 Release：

- 手动 `Run workflow`
- 定时跑
- 你打 tag 时（`git tag v1.2.3 && git push --tags`）

直链：`https://github.com/<你>/Padavan-B70/releases/latest/download/B70.trx`

### 路由器 OTA 流程

```
GitHub Actions 跑完 → 自动发 GitHub Release (nightly-20260906)
   ↓
路由器开机 / cron 每 10 分钟跑 /etc/storage/auto_upgrade.sh check
   ↓
对比 HEAD Content-Length 与本地记录
   ↓
发现不一样 → 下载新版 .trx 到 /tmp/firmware_new.trx
   ↓
发 Telegram / 邮件: "新版已下载, 你 Web 后台刷一下"
   ↓
你: 192.168.123.1 → 系统管理 → 固件升级 → 选 .trx 上传 → 一键升级
```

**为什么不自动刷：** B70 flash 16 MB 装不下两份镜像，没法软件回滚；中途断电就救砖。所以永远**人工最后一步**确认最稳。

### 关闭 OTA 检测

如果不需要 OTA：

```bash
vi /etc/storage/startup.sh
# 把 fw_check 那行注释掉即可
```

---


## 📁 文件结构

```
b70-padavan-build/
├── .github/workflows/
│   └── Padavan_CI_B70.yml              # GitHub Actions CI
├── configs/templates/
│   └── B70.config                      # Padavan 编译模板 (aria2 + PHP)
├── scripts/
│   └── post_build.sh                   # 编译后处理
├── clash-yaml/                         # ← 路由器 Clash 配置仓库(托管在 GitHub)
│   ├── config.yaml                     # 主配置 (含占位符,被路由器脚本注入)
│   ├── README.md
│   ├── proxies/                        # 单节点 YAML 片段
│   │   ├── example-vmess.yaml
│   │   ├── example-trojan.yaml
│   │   └── your-nodes.yaml             # ← 你加的节点放这里
│   ├── rules/
│   │   ├── private.yaml                # 私有直连
│   │   ├── gfw.yaml                    # GFW 列表
│   │   ├── cncidr.yaml                 # 国内 IP
│   │   ├── lancidr.yaml                # 局域网 IP
│   │   └── applications.yaml           # 主流应用直连
│   └── subscriptions/
│       └── airport-1.yaml              # 机场订阅 url
├── www/
│   ├── dashboard.html                  # 状态面板(PHP)
│   ├── monitor.sh                      # 数据采集脚本
│   └── status.json.example             # 占位
├── etc_storage/                        # ← 拷到路由器 /etc/storage/
│   ├── startup.sh                      # 开机自启入口
│   ├── clash_yaml_pull.sh              # ← Clash YAML 拉取
│   ├── tailscale_upgrade.sh            # ← Tailscale 自动升级
│   ├── notify.sh                       # ← 推送通知
│   ├── notify.conf.example             # 通知配置示例
│   ├── auto_upgrade.sh                 # OTA 检测
│   ├── clash.sh                        # ShellClash 包装
│   ├── tailscale.sh                    # Tailscale 控制
│   ├── aria2.sh                        # aria2 控制
│   └── firewall_helpers.sh              # iptables 透明代理
└── README.md                           # 本文件
```

---


## 🛟 故障排查

| 症状                                               | 可能原因                                 | 解决                                                                        |
| ------------------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------- |
| Actions 编译失败 log 中 `fakeroot: command not found` | 依赖没装                                 | 看 GitHub Actions step `Install build deps` 输出                             |
| 编译 30 分钟没出 `.trx`                                | 工具链下载失败                              | 重新 Run workflow；GitHub Actions 在网络波动时偶发                                   |
| flash 后进不去 Padavan                               | Breed 没擦 flash                       | 重进 Breed 重刷，**勾上擦 flash**                                                 |
| ShellClash 启动后 LAN 不走代理                          | 没启用透明代理                              | `/etc/storage/firewall_helpers.sh clash-on`                               |
| Tailscale 起来后访问速度慢                               | userspace-networking 性能差             | 改 `--tun=auto`（需 mt76 驱动，Tailscale 官方文档有说明）                               |
| aria2 RPC 连不上 (192.168.123.1:6800)               | 防火墙挡端口                               | Padavan Web → 防火墙 → 开放 6800                                               |
| Dashboard 打不开 (404)                              | www 文件没拷                             | `cp /tmp/dashboard.html /etc/storage/www/`                                |
| Telegram 通知发不出去                                  | bot 没收到 chat_id                      | 给 bot 发条消息再 `getUpdates` 看 chat_id                                        |
| `auto_upgrade.sh check` 老说 OK 但没新版               | GitHub API 限流                        | 检查仓库名是否填对；等 1 小时再试                                                        |
| 路由器 RAM 满                                        | ShellClash + Tailscale 同时开 128 MB 顶满 | 改 `tailscale.sh stop` 关掉，或换 ShellClash 用 metacub 自动降级                     |
| 浏览器登 Padavan 后台慢                                 | dashboard.html 每 10s 刷新抢 CPU         | 把 `dashboard.html` 里 `<meta http-equiv="refresh" content="10">` 改 30 或注释掉 |

---

## 🔐 安全提醒

- 默认 admin/admin，**第一次进 Web 后台立刻改密码**
- Tailscale authkey 不要 commit 到仓库（用环境变量或本地配置）
- 路由器开 Web 后台只允许 LAN 访问，不要在 Padavan 里把 HTTP 服务端口暴露到 WAN

---

## 📜 License

GPLv3 (Padavan upstream) · 本配置文件仅供学习与个人使用。
