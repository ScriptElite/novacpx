# NovaCPX — 管理员指南

## 访问管理面板

管理面板运行在端口 **8882** 上。导航到 `https://<服务器IP>:8882` 并使用你的管理员凭据登录。

全新安装时，浏览器会显示自签名证书警告。接受它，或者将 `/etc/novacpx/ssl/` 中的证书替换为受信任的证书并重启 Apache。

## 仪表盘

仪表盘显示实时服务器统计信息（CPU、内存、磁盘、运行时间）、正在运行的服务及其重启/停止控制按钮，以及 NovaCPX 版本信息。

点击 **Check for Updates** 查看是否有新版本可用。

## 账户

**Accounts → All Accounts** 列出服务器上的所有主机账户。在此页面你可以：

- 按域名或用户名**搜索**
- **暂停 / 恢复**账户（暂停会禁用 Web 虚拟主机并向账户持有人发送电子邮件通知）
- 为任意账户**更改密码**
- **永久删除**账户（删除文件、数据库、DNS 区域、电子邮件账户——不可逆）

### 创建账户

**Accounts → Create Account**

| 字段 | 说明 |
|------|------|
| 用户名 | 小写字母和数字。会创建一个 Linux 系统用户。 |
| 域名 | 账户的主域名。会自动创建 DNS 区域和虚拟主机。 |
| 电子邮件 | 账户持有人的电子邮件。用于接收欢迎通知。 |
| 密码 | 最少 8 个字符。同时设置为 Linux 系统密码。 |
| 套餐 | 应用于该账户的磁盘/资源限制。 |
| PHP 版本 | 每个账户的 PHP-FPM 池版本。 |
| 经销商 | （可选）将账户分配给某个经销商。 |

创建后，如果启用了通知，欢迎电子邮件（包含登录凭据）会发送给账户持有人。

## 经销商

**Accounts → Resellers** 管理经销商子管理员账户。经销商可以创建和管理自己的客户账户、设置每个客户的 Docker 配额，并应用白标品牌。

要创建经销商，请转到 **Accounts → Create Account** 并选择 **Reseller** 角色。

## 套餐

定义主机方案。每个套餐对以下项目设置限制：

- 磁盘（MB）
- 电子邮件账户
- MySQL 数据库
- FTP 账户
- 域名
- 子域名

没有套餐的账户没有强制限制。

## DNS

### DNS 区域

列出服务器上的所有 DNS 区域。你可以直接添加、编辑和删除 DNS 记录。区域由 BIND9 管理，并通过 `rndc` 重新加载。

支持的记录类型：A、AAAA、CNAME、MX、TXT、NS、SRV、CAA。

### 域名服务器

设置创建新区域时使用的全局 NS1/NS2 主机名。保存后，点击 **Check All** 验证域名服务器是否正确解析。

## 服务

### Web 服务器

显示 Apache 或 Nginx 配置。在 Web 服务器之间切换。切换脚本在后台运行——约 30 秒后再次查看页面以确认。

### PHP 管理器

安装或移除 PHP 版本（7.4、8.1、8.2、8.3）。每个版本都有自己的 PHP-FPM 池。账户可以分配任意已安装的版本。

### MySQL 管理器

显示 MySQL 状态和正在运行的数据库。如果安装了 phpMyAdmin，会提供指向它的链接。

### 邮件服务器

显示 Postfix/Dovecot 状态。切换邮件服务器堆栈（postfix-dovecot 或 postfix-dovecot-rspamd）。

### FTP 服务器

显示 FTP 守护进程状态。在 ProFTPD、vsftpd 和 PureFTPD 之间切换。

### Nginx Proxy Manager

用于附加服务的反向代理管理。Nginx Proxy Manager 作为 Docker 容器运行。使用 **Setup** 进行配置。

### WordPress 管理器

通过 WP-CLI 一键安装 WordPress。操作包括：安装、更新、切换维护模式、克隆到暂存环境。

### Docker

完整的 Docker Engine 管理：

- **容器** — 运行、停止、启动、重启、删除、查看日志
- **镜像** — 拉取、列出、删除
- **卷**和**网络** — 列出、删除
- **Compose 堆栈** — 从 YAML 创建、启动/停止、查看日志

## 安全

### SSL 管理器

查看所有账户的 SSL 证书。证书通过 Certbot（Let's Encrypt）签发。域名必须能够公开解析，签发才能成功。

### 防火墙 / Fail2Ban

管理 UFW 规则（按端口、协议和 IP 允许/拒绝）。查看和解封 Fail2Ban jail 条目。NovaCPX jail 监控：

- SSH 暴力破解（`sshd`）
- 面板登录失败（`novacpx-auth`）
- API 滥用（`novacpx-api`）
- PHP 错误泛滥（`novacpx-php`）
- Postfix SMTP 认证（`postfix-auth`）

### 审计日志

所有管理员、经销商和用户操作的完整日志。可按用户名、操作类型和日期范围筛选。点击任意行可展开原始 JSON 详细信息负载。

### 2FA 管理器

管理 TOTP 双因素认证。管理员可以查看哪些账户启用了 2FA，并在用户丢失验证器时为其重置（撤销）2FA。

### 会话

查看所有活动登录会话。撤销单个会话或某个特定用户的所有会话。用于在密码重置后强制登出。

## 系统

### 更新

检查 NovaCPX 和操作系统更新。结果缓存 12 小时，因此页面可即时加载；点击 **↻ Refresh now** 强制进行实时检查。

**更新通道**（在设置中配置）：

| 通道 | GitHub 分支 | 版本规则 |
|------|------------|---------|
| 稳定版 | `main` | 主/次版本发布（例如 1.1.0） |
| 测试版 | `beta` | 补丁和预发布版本（例如 1.1.1-beta.3） |

更新页面显示你已安装的版本、你所在通道的最新可用版本以及待处理的提交。点击 **Update NovaCPX** 进行拉取和部署。部署前会验证 PHP 语法；如果更新后面板宕机，它会从备份自动恢复。

**操作系统升级**会实时流式输出 `apt-get upgrade` 的输出。升级前会备份 Web 根目录。

### 备份

按账户安排和管理备份：

- **Backup now** — 立即备份文件 + 数据库
- **Download** — 下载备份归档
- **Restore** — 从备份恢复文件和数据库
- **Schedule** — 为每个账户设置自动备份频率
- 可选的 rclone/S3 远程目标

### Cloudflare

按账户管理 Cloudflare API 密钥。拉取/推送 DNS 区域记录，为每条记录切换 CDN 代理。

### 服务器选项

配置 NovaCPX 管理哪些服务：

| 设置 | 选项 |
|------|------|
| Web 服务器 | apache、nginx、openlitespeed、caddy |
| 邮件服务器 | postfix-dovecot、postfix-dovecot-rspamd |
| FTP 服务器 | proftpd、vsftpd、pureftpd |
| DNS 服务器 | bind9、powerdns、nsd、none |
| WHMCS | 启用并配置计费桥接 API 密钥 |

### 通知

配置通过 CyberMail 发送的电子邮件警报：

| 字段 | 说明 |
|------|------|
| CyberMail API 密钥 | 来自 platform.cyberpersons.com |
| 发件人电子邮件 | 发件地址（必须是已验证的发件人域名） |
| 发件人名称 | 电子邮件客户端中显示的显示名称 |
| 管理员警报电子邮件 | 接收所有通知的管理员副本 |
| 通知 | 启用或禁用所有出站通知 |

点击 **Send Test Email** 验证配置。

通知触发条件：

- 账户创建 → 向新用户发送欢迎电子邮件 + 管理员警报
- 账户暂停 → 向账户持有人发送通知 + 管理员警报
- 磁盘配额 ≥ 85% → 每日警告（cron，06:00）
- SSL 证书将在 ≤ 14 天内到期 → 到期通知（cron，06:00）

### 设置

面板全局设置。所有值在页面打开时从数据库加载，并单独保存。

| 设置 | 描述 |
|------|------|
| 面板名称 | 浏览器标题和侧边栏中显示的名称 |
| 默认 PHP 版本 | 应用于新账户的 PHP 版本（7.4、8.1、8.2、8.3） |
| 主域名服务器 | 用户设置 DNS 时显示的 NS1 主机名 |
| 辅助域名服务器 | NS2 主机名 |
| 更新通道 | **稳定版**（main 分支）或**测试版**（beta 分支）——控制更新页面检查并从哪个 GitHub 分支部署 |

## WHMCS 计费桥接

NovaCPX 在 `/api/whmcs/<action>` 暴露了一个与 WHMCS 兼容的服务器模块 API。在 **Server Options** 中启用它并设置 API 密钥。WHMCS 模块调用这些端点来自动开通、暂停和终止账户。

支持的操作：`create`、`suspend`、`unsuspend`、`terminate`、`changepackage`、`info`。

使用 `X-WHMCS-Key: <api_key>` 请求头进行认证。

## 日志文件

| 文件 | 内容 |
|------|------|
| `/var/log/novacpx/deploy.log` | 自动部署活动 |
| `/var/log/novacpx/stats-collector.log` | 服务器统计 cron 输出 |
| `/var/log/novacpx/notify-checks.log` | 磁盘/SSL 通知 cron 输出 |
| `/var/log/novacpx/switch-*.log` | 服务切换脚本输出 |
