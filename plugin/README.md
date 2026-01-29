# Vimalinx Server 插件

中文 | [English](README.en.md)

该插件用于连接 Gateway 与 Vimalinx Server，支持轮询（poll）或 webhook 入站模式，并使用 Token 认证。

## 需求

- Gateway 运行中（Node 22+）。
- 可访问的 Vimalinx Server。

## 安装

面向最终用户的最简流程（推荐）：

1) 安装 Clawdbot（只需一次）

```bash
npm install -g clawdbot@latest
```

2) 在仓库根目录运行一键安装

```bash
./install.sh
```

3) 按提示输入
- 服务器地址：`https://vimagram.vimalinx.xyz`
- Token：在 Vimagram App 的 Account 页面生成/复制

完成后脚本会自动配置并重启 Gateway。

可选：不交互模式

```bash
VIMALINX_SERVER_URL="https://vimagram.vimalinx.xyz" \
VIMALINX_TOKEN="你的Token" \
./install.sh
```

可选：跳过自动步骤

```bash
VIMALINX_SKIP_DOCTOR_FIX=1 \
VIMALINX_SKIP_GATEWAY_START=1 \
VIMALINX_SKIP_STATUS=1 \
./install.sh
```

可选：覆盖已有插件安装

```bash
VIMALINX_FORCE_OVERWRITE=1 ./install.sh
```


## 配置（向导）

```bash
clawdbot onboard
```

向导会要求：
- 选择服务器（官方 / 自定义 URL）。
- 输入 Vimagram 生成的 Token。
- 选择入站模式（poll 或 webhook）。

## 配置（手动）

最小配置（单账号）：

```yaml
channels:
  test:
    baseUrl: https://vimagram.vimalinx.xyz
    userId: user-id
    token: host-token
    inboundMode: poll
```

可选字段：
- `webhookPath`（默认 `/test-webhook`）
- `webhookToken`（默认等于 `token`）

## 验证

```bash
clawdbot channels status --probe
```

若一切正常，状态会显示 connected/polling。

## 相关

- Server：`server/README.md`
- Android App：`app/README.md`
