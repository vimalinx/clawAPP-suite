# Vimalinx Server

中文 | [English](README.en.md)

Vimalinx Server 插件的最小聊天服务器（channel id: `test`）。

## 快速启动（本地轮询模式）

```bash
export TEST_SERVER_PORT=8788
export TEST_USERS_FILE=/path/to/vimalinx-users.json
export TEST_ALLOW_REGISTRATION=true

node server/server.mjs
```

- `TEST_USERS_FILE` 用于持久化注册用户。
- 默认入站模式为 `poll`。

## 配置

环境变量：

- `TEST_SERVER_PORT`（默认 `8788`）
- `TEST_SERVER_TOKEN`（可选，全局 `/send` 密钥）
- `TEST_GATEWAY_URL`（Gateway webhook URL）
- `TEST_GATEWAY_TOKEN`（Gateway token）
- `TEST_INBOUND_MODE`（`poll` 或 `webhook`）
- `TEST_USERS_FILE`（用户文件路径）
- `TEST_USERS_WRITE_FILE`（注册写入路径，默认同 `TEST_USERS_FILE`）
- `TEST_USERS`（内联 JSON）
- `TEST_DEFAULT_USER_ID` + `TEST_DEFAULT_USER_TOKEN`
- `TEST_ALLOW_REGISTRATION`（`true`/`false`）
- `TEST_INVITE_CODES`（邀请码列表）
- `TEST_HMAC_SECRET`（Webhook/Send 的签名密钥）
- `TEST_REQUIRE_SIGNATURE`（当 secret 存在时默认 true）
- `TEST_SIGNATURE_TTL_MS`（签名时间窗，默认 `300000`）

## 邀请码模式

可选发码或不发码：

- 不发邀请码：不设置 `TEST_INVITE_CODES`（或设置为空），并确保
  `TEST_ALLOW_REGISTRATION=true`。
- 需要邀请码：设置 `TEST_INVITE_CODES`，示例：

```bash
export TEST_INVITE_CODES="vimalinx-xxxxxxx1,vimalinx-xxxxxxx2"
```

如果要完全关闭注册：

```bash
export TEST_ALLOW_REGISTRATION=false
```

## Webhook 模式

```bash
export TEST_INBOUND_MODE=webhook
export TEST_GATEWAY_URL=https://gateway-host:18789/test-webhook
```

注意：
- 建议公网部署使用 HTTPS。
- 可在用户文件中为单个用户设置 `gatewayUrl`。
- 若设置 `TEST_HMAC_SECRET`，请求会带签名。

## 运行（Node 22+）

```bash
node server/server.mjs
```

## 部署建议

- 使用 systemd/PM2 等保证进程守护。
- 开启注册时确保 users 文件可写。
- 建议开启 `TEST_SERVER_TOKEN` 或使用用户 token 保护 `/send`。

## 端点概览

- `GET /` web UI
- `GET /api/stream` SSE
- `GET /api/poll` 长轮询
- `POST /api/message` 入站消息
- `POST /api/register` 注册
- `POST /api/account/login` 账号密码登录
- `POST /api/token` 生成主机 Token
- `POST /api/token/usage` 统计
- `POST /api/login` token 登录
- `POST /send` Gateway 出站回执

## 请求示例

Send（客户端 -> 服务器）：

```json
{ "userId": "alice", "token": "alice-token", "text": "hello" }
```

入站到 Gateway（服务器 -> Gateway）：

```json
{
  "message": {
    "chatId": "user:alice",
    "chatType": "dm",
    "senderId": "alice",
    "senderName": "Alice",
    "text": "hello",
    "timestamp": 1710000000
  }
}
```

Poll 响应（服务器 -> Gateway）：

```json
{
  "ok": true,
  "messages": [
    {
      "chatId": "user:alice",
      "chatType": "dm",
      "senderId": "alice",
      "senderName": "Alice",
      "text": "hello",
      "timestamp": 1710000000
    }
  ]
}
```

出站（Gateway -> 服务器）：

```json
{ "chatId": "user:alice", "text": "hi", "replyToId": "msg-123" }
```

签名头（启用签名时）：

```
x-test-timestamp: <unix_ms>
x-test-nonce: <random>
x-test-signature: HMAC_SHA256(secret, "${timestamp}.${nonce}.${rawBody}")
```

注册示例（客户端 -> 服务器）：

```json
{
  "userId": "alice",
  "inviteCode": "alpha-2026",
  "displayName": "Alice",
  "password": "your-password"
}
```
