# Clash YAML 配置仓库

放在这里的所有配置都会被路由器端 `clash_yaml_pull.sh` 拉取、合并、生成最终配置。

## 目录结构

```
clash-yaml/
├── config.yaml                  # 主配置(占位符会自动被脚本填充)
├── README.md                    # 本文件
├── proxies/
│   ├── example-vmess.yaml       # 单节点 YAML 片段(数组元素)
│   ├── example-trojan.yaml
│   └── my-vps.yaml              # 你自己加的真实节点
├── rules/
│   ├── private.yaml             # 私有直连列表
│   ├── gfw.yaml                 # GFW 列表
│   ├── cncidr.yaml              # 国内 IP 段
│   ├── lancidr.yaml             # 局域网 IP 段
│   └── applications.yaml        # 主流应用直连
└── subscriptions/
    └── airport-1.yaml           # 机场订阅(支持 url 在线抓取)
```

## 工作机制

`/etc/storage/clash_yaml_pull.sh` 每次执行时会：

1. 从 GitHub raw 拉取本目录所有 yaml 文件
2. 把 `proxies/*.yaml` 合并进 `config.yaml` 的 `proxies:` 数组(替换 `# ↓↓↓ 占位 ↓↓↓` 注释段)
3. 把 `subscriptions/*.yaml` 里 `url:` 字段的机场订阅在线抓下来,base64 解码后注入
4. 把合并结果写到 `/etc/storage/clash/config.yaml`
5. 调用 `clash.sh restart` 重启 ShellClash

触发时机:
- `startup.sh` 安装时立刻拉一次
- `cron` 每天 03:00 自动拉一次(可在 `startup.sh` 里改)

## 添加你自己的节点

**方式 A**: 直接在 `proxies/` 下加新 yaml 文件,每个文件是 proxies 数组的片段(开头带 `-`):

```yaml
# proxies/my-vps.yaml
- name: "my-vps"
  type: vmess
  server: vps.example.com
  port: 443
  uuid: xxxxx
  ...
```

**方式 B**: 编辑 `subscriptions/airport-1.yaml`,把机场订阅 url 填进去。

## 启用机场订阅 URL 在线抓取

1. 拿到机场给的「Clash 订阅链接」
2. 编辑 `subscriptions/airport-1.yaml`:
   ```yaml
   url: "https://机场域名/link?id=xxx"
   proxies: []
   ```
3. push 一次,等路由器 cron 拉新(或者手动 `/etc/storage/clash_yaml_pull.sh`)

> ⚠️ 机场订阅是 base64 编码的,部分机场会要求 `User-Agent: clash.meta`,本脚本默认带这个 UA。

## 修改主配置

只改 `config.yaml` 即可,推送到 GitHub,路由器下次 cron 自动同步。

## 故障排查

| 现象 | 检查 |
|---|---|
| 没拉新 | `cat /etc/storage/clash_yaml_pull.log` 看错误 |
| 配置不生效 | `clash -t -d /etc/storage/clash/` 测配置语法 |
| 节点列表为空 | 检查 proxies/*.yaml 是否合法 yaml |
| GitHub raw 拉不下来 | 路由器可能没国际网,先 `clash.sh start` 一次再拉 |