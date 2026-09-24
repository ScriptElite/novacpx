# NovaCPX — API 参考

## 概述

所有 API 端点均在 `/api/<resource>/<action>` 下提供服务。

**基础 URL 模式：** `https://<server>:<port>/api/<resource>/<action>`

同一套 API 在三个面板端口（8880、8881、8882）上均可用。哪些操作能够成功取决于已认证会话的角色。

### 认证

所有端点（除 `auth/login` 外）都需要一个活动的会话 Cookie `ncpx_session`。通过调用 `auth/login` 获取它。

```http
POST /api/auth/login
Content-Type: application/json

{"username": "admin", "password": "Nova2026!!"}
```

响应会设置 `ncpx_session` Cookie。在所有后续请求中包含它（在 fetch 中使用 `credentials: 'include'`，或在 curl 中使用 `-b cookies.txt`）。

### 响应格式

每个响应都是 JSON：

```json
{
  "success": true,
  "message": "OK",
  "data": { ... }
}
```

出错时：

```json
{
  "success": false,
  "message": "Reason",
  "errors": []
}
```

分页响应包含一个 `meta` 块：

```json
{
  "success": true,
  "data": { "items": [...], "meta": { "total": 100, "page": 1, "per_page": 25, "pages": 4 } }
}
```

### 角色访问权限

| 角色 | 面板 | 访问权限 |
|------|------|---------|
| `admin` | 8882 | 全部 |
| `reseller` | 8881 | 自己的账户 + 经销商功能 |
| `user` | 8880 | 仅自己的账户 |

### 速率限制

| 范围 | 限制 |
|------|------|
| 登录（`auth/login`） | 10 次请求 / 分钟 |
| 所有其他端点 | 120 次请求 / 分钟 |

超出限制会返回 HTTP 429，并带有 `Retry-After` 和 `X-RateLimit-*` 响应头。

---

## auth

### `POST /api/auth/login`

认证并创建会话。

**请求体：** `{username, password}`  
**返回：** `{user: {id, username, role}, portal_url}`  
**访问权限：** 公开

### `GET /api/auth/me`

返回当前会话的用户对象。

**返回：** `{id, username, email, role}`  
**访问权限：** 任意已认证用户

### `POST /api/auth/logout`

销毁当前会话。

**访问权限：** 任意已认证用户

### `POST /api/auth/change-password`

更改当前用户自己的密码。

**请求体：** `{current_password, new_password, confirm_password}`  
**访问权限：** 任意已认证用户

---

## accounts

### `GET /api/accounts/list`

列出主机账户。

**查询参数：** `page`、`per_page`、`search`、`status`  
**返回：** 分页列表，每个账户包含 domain_count、email_count、db_count  
**访问权限：** 管理员（所有账户）、经销商（自己的账户）

### `GET /api/accounts/get?id=<id>`

获取单个账户及其域名和磁盘使用情况。

**访问权限：** 管理员、经销商（自己的账户）

### `POST /api/accounts/create`

创建主机账户。创建 Linux 用户、主目录、虚拟主机、DNS 区域，并可选择发送欢迎电子邮件。

**请求体：**

```json
{
  "username": "john",
  "domain": "example.com",
  "email": "john@example.com",
  "password": "secret",
  "package_id": 1,
  "php_version": "8.3"
}
```

**访问权限：** 管理员、经销商

### `POST /api/accounts/suspend`

暂停账户（禁用虚拟主机，通知用户）。

**请求体：** `{id, reason?}`  
**访问权限：** 管理员、经销商（自己的账户）

### `POST /api/accounts/unsuspend`

重新启用已暂停的账户。

**请求体：** `{id}`  
**访问权限：** 管理员、经销商（自己的账户）

### `POST /api/accounts/terminate`

永久删除账户及其所有数据。

**请求体：** `{id}`  
**访问权限：** 仅管理员

### `POST /api/accounts/change-password`

重置账户的面板密码和系统密码。

**请求体：** `{account_id, password}`  
**访问权限：** 仅管理员

### `GET /api/accounts/usage?id=<id>`

返回磁盘、电子邮件、数据库、域名和 FTP 使用量与套餐限制的对比。

**访问权限：** 管理员、经销商（自己的账户）

---

## domains

### `GET /api/domains/list?account_id=<id>`

列出账户的域名。

**访问权限：** 管理员、经销商（自己的账户）、用户（自己的账户）

### `POST /api/domains/add`

向账户添加域名、子域名或重定向。

**请求体：**

```json
{
  "account_id": 1,
  "domain": "example.com",
  "type": "addon",
  "document_root": "/home/user/public_html/example",
  "php_version": "8.3"
}
```

`type` 值：`addon`、`subdomain`、`redirect`

对于重定向，包含 `redirect_to`（URL）和 `redirect_code`（301 或 302）。

**访问权限：** 管理员、经销商、用户

### `POST /api/domains/remove`

移除域名（不能移除主域名）。

**请求体：** `{account_id, domain_id}`  
**访问权限：** 管理员、经销商、用户

---

## email

### `GET /api/email/list?account_id=<id>`

列出账户的电子邮件账户。

**访问权限：** 管理员、经销商、用户

### `POST /api/email/create`

创建邮箱。

**请求体：** `{account_id, email, password, quota_mb?}`  
**访问权限：** 管理员、经销商、用户（受 `max_email` 套餐限制约束）

### `DELETE /api/email/delete`

删除邮箱。

**请求体：** `{id}`  
**访问权限：** 管理员、经销商、用户

### `POST /api/email/suspend`

暂停邮箱。

**请求体：** `{id}`  
**访问权限：** 管理员、经销商、用户

### `GET /api/webmail/login-url?account_id=<id>&email=<email>`

生成单点登录网络邮件 URL（有效期 5 分钟）。

**访问权限：** 管理员、经销商、用户

---

## dns

### `GET /api/dns/list?account_id=<id>`

列出账户的 DNS 区域。

**访问权限：** 管理员、经销商、用户

### `GET /api/dns/records?zone_id=<id>`

列出区域中的记录。

### `POST /api/dns/add-record`

添加 DNS 记录。

**请求体：**

```json
{
  "zone_id": 1,
  "type": "A",
  "name": "www",
  "value": "1.2.3.4",
  "ttl": 3600
}
```

**访问权限：** 管理员、经销商、用户

### `POST /api/dns/update-record`

更新现有记录。

**请求体：** `{record_id, name, value, ttl}`

### `POST /api/dns/delete-record`

删除记录。

**请求体：** `{record_id}`

### `POST /api/dkim/generate`

为域名生成 DKIM 密钥对。

**请求体：** `{account_id, domain}`

---

## databases

### `GET /api/databases/list?account_id=<id>`

列出账户的 MySQL 数据库。

**访问权限：** 管理员、经销商、用户

### `POST /api/databases/create`

创建数据库和 MySQL 用户。

**请求体：** `{account_id, db_name, db_user, db_pass}`  
**受 `max_databases` 套餐限制约束。**

### `DELETE /api/databases/delete`

删除数据库。

**请求体：** `{id}`

---

## ftp

### `GET /api/ftp/list?account_id=<id>`

列出 FTP 账户。

### `POST /api/ftp/create`

创建 FTP 账户。

**请求体：** `{account_id, username, password, home_dir}`  
**受 `max_ftp` 套餐限制约束。**

### `DELETE /api/ftp/delete`

删除 FTP 账户。

**请求体：** `{id}`

---

## ssl

### `GET /api/ssl/list?account_id=<id>`

列出账户的 SSL 证书。

### `POST /api/ssl/issue`

签发 Let's Encrypt 证书。域名必须能够公开解析。

**请求体：** `{account_id, domain}`

### `POST /api/ssl/delete`

移除 SSL 证书记录。

**请求体：** `{id}`

---

## files

文件管理器 API 与面向用户的文件管理器对应。所有路径都会根据账户的主目录进行验证；该目录之外的路径会被拒绝。

### `GET /api/files/list?account_id=<id>&path=<path>`

列出目录内容。

### `GET /api/files/read?account_id=<id>&path=<path>`

读取文本文件（最大 1 MB）。

### `POST /api/files/write`

写入/创建文件。

**请求体：** `{account_id, path, content}`

### `POST /api/files/mkdir`

创建目录。

**请求体：** `{account_id, path}`

### `DELETE /api/files/delete`

删除文件或目录。

**请求体：** `{account_id, path}`

### `POST /api/files/rename`

重命名或移动文件。

**请求体：** `{account_id, from, to}`

### `POST /api/files/chmod`

更改文件权限（最大限制为 0777）。

**请求体：** `{account_id, path, mode}`（例如 `"mode": "0755"`）

### `POST /api/files/upload`

上传文件。多部分表单数据：`account_id`、`path`、`file`。

---

## cron

### `GET /api/cron/list?account_id=<id>`

列出账户的 cron 任务。

### `POST /api/cron/save`

创建或更新 cron 任务。

**请求体：** `{account_id, id?, schedule, command, enabled}`

### `DELETE /api/cron/delete`

删除 cron 任务。

**请求体：** `{id}`

---

## packages

### `GET /api/packages/list`

列出所有主机套餐。

**访问权限：** 管理员、经销商

### `POST /api/packages/create`

创建套餐。

**请求体：**

```json
{
  "name": "Starter",
  "disk_mb": 5120,
  "max_email": 10,
  "max_databases": 5,
  "max_ftp": 5,
  "max_domains": 10,
  "max_subdomains": 20
}
```

### `POST /api/packages/update`

更新套餐。

**请求体：** `{id, ...与创建相同的字段}`

### `DELETE /api/packages/delete`

删除套餐（使用它的账户不受影响）。

**请求体：** `{id}`

---

## stats

### `GET /api/stats/account?account_id=<id>`

返回账户的使用统计信息。对于用户角色，`account_id` 会自动推断。

### `GET /api/stats/server`

返回最近 24 小时的历史服务器统计信息（CPU、内存、磁盘）。由 `collect-stats.php` cron 每 5 分钟填充。

**访问权限：** 仅管理员

---

## sessions

### `GET /api/sessions/list`

列出所有活动会话（管理员看到全部，用户看到自己的）。

### `DELETE /api/sessions/revoke`

撤销特定会话。

**请求体：** `{session_id}`  
**访问权限：** 管理员

### `DELETE /api/sessions/revoke-user`

撤销特定用户的所有会话。

**请求体：** `{user_id}`  
**访问权限：** 管理员

### `DELETE /api/sessions/revoke-all`

撤销面板上的所有活动会话。

**访问权限：** 管理员

---

## system

除非另有说明，所有系统操作都需要管理员权限。

### `GET /api/system/version`

返回面板版本、git 提交、PHP 版本、操作系统。无需认证。

### `GET /api/system/stats`

返回实时 CPU、内存、磁盘、运行时间和服务状态。

### `GET /api/system/check-update`

检查 GitHub 上是否有更新的 NovaCPX 提交。

### `POST /api/system/apply-update`

拉取最新代码并触发部署。

### `GET /api/system/check-os-update`

列出可用的 apt 软件包升级。

### `POST /api/system/apply-os-update`

运行 `apt-get upgrade` 并重启任何已停止的服务。

### `GET /api/system/audit-log`

查询审计日志。

**查询参数：** `page`、`per_page`、`user`、`action`、`date_from`、`date_to`

### `GET /api/system/server-options`

返回当前 Web/邮件/FTP/DNS 服务器选择及检测状态。

### `POST /api/system/save-option`

保存服务器选项。

**请求体：** `{key, value}` — 允许的键：`web_server`、`mail_server`、`ftp_server`、`dns_server`、`whmcs_api_key`、`whmcs_enabled`、`ns1_hostname`、`ns2_hostname`

### `GET /api/system/notify-settings`

返回通知设置（API 密钥已掩码）。

### `POST /api/system/save-notify-settings`

保存通知设置。

**请求体：** `{cybermail_api_key?, notify_from_email?, notify_from_name?, notify_admin_email?, notifications_enabled?}`

### `POST /api/system/test-notify`

发送测试电子邮件。

**请求体：** `{to}`

### `POST /api/system/service-action`

启动、停止或重启系统服务。

**请求体：** `{service, action}` — action：`start`、`stop`、`restart`

---

## branding

### `GET /api/branding/get`

返回当前经销商的白标设置。

**访问权限：** 经销商（自己的白标）、管理员（传入 `reseller_id` 参数）

### `POST /api/branding/save`

保存白标设置。

**请求体：** `{panel_name?, primary_color?, accent_color?, support_email?, support_url?, hide_powered_by?, custom_css?}`

### `POST /api/branding/upload-logo`

上传 Logo 图片。多部分：`logo` 文件字段。  
接受 PNG、JPG、SVG、WEBP（最大 512 KB）。

### `POST /api/branding/delete-logo`

移除当前 Logo 并恢复为默认 SVG。

---

## whmcs

WHMCS 计费桥接。使用 `X-WHMCS-Key: <key>` 请求头进行认证（在服务器选项中配置）。

### `POST /api/whmcs/create`

开通新的主机账户。

**请求体：** `{domain, username, password, email, package_id?}`

### `POST /api/whmcs/suspend`

按域名暂停账户。

**请求体：** `{domain, reason?}`

### `POST /api/whmcs/unsuspend`

按域名恢复账户。

**请求体：** `{domain}`

### `POST /api/whmcs/terminate`

按域名终止账户。

**请求体：** `{domain}`

### `POST /api/whmcs/changepackage`

将账户切换到不同的套餐。

**请求体：** `{domain, package_id}`

### `GET /api/whmcs/info?domain=<domain>`

返回域名的账户详情。

---

## docker

### `GET /api/docker/status`

引擎状态及容器/镜像数量。

### `GET /api/docker/containers?account_id=<id>`

列出账户的容器（管理员不传 account_id 时列出所有容器）。

### `POST /api/docker/container-action`

**请求体：** `{container_id, action}` — action：`start`、`stop`、`restart`、`remove`

### `GET /api/docker/logs?container_id=<id>`

返回容器的最后 100 行日志。

### `GET /api/docker/images`

列出已拉取的镜像。

### `POST /api/docker/pull`

拉取镜像。

**请求体：** `{image}` 例如 `"image": "nginx:latest"`

### `POST /api/docker/run`

运行新容器。

**请求体：** `{account_id, name, image, ports?, env?, volumes?}`  
容器名称命名空间为 `novacpx-<username>-<name>`。

### `GET /api/docker/catalog`

返回一键应用目录（9 个应用：WordPress、Ghost、Nextcloud、Gitea、Matomo、Vaultwarden、Node.js、Flask、static）。

### `POST /api/docker/launch-app`

从目录部署应用。

**请求体：** `{account_id, app_id, ...应用特定配置}`

---

## firewall

### `GET /api/firewall/rules`

列出 UFW 规则。

**访问权限：** 管理员

### `POST /api/firewall/add-rule`

添加 UFW 规则。

**请求体：** `{port, protocol, action, from_ip?}`

### `POST /api/firewall/delete-rule`

按编号移除规则。

**请求体：** `{rule_number}`

### `GET /api/firewall/fail2ban`

返回 Fail2Ban jail 状态和被封禁的 IP。

### `POST /api/firewall/unban`

从 jail 中解封 IP。

**请求体：** `{jail, ip}`
