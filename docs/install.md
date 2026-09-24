# NovaCPX — 安装指南

## 系统要求

| 项目 | 最低要求 |
|------|---------|
| 操作系统 | Ubuntu 20.04 / 22.04 / 24.04，Debian 11 / 12 |
| 内存 | 1 GB（推荐 2 GB） |
| 磁盘 | 10 GB 可用空间 |
| CPU | 1 vCPU |
| 权限 | Root 或 sudo |
| 端口 | 80, 443, 8880, 8881, 8882, 8883, 21, 22, 25, 143, 993, 53 |

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/myronblair/novacpx/main/install.sh | bash
```

或下载后手动运行：

```bash
wget https://raw.githubusercontent.com/myronblair/novacpx/main/install.sh
bash install.sh
```

### 安装器参数

| 参数 | 作用 |
|------|------|
| `--nginx` | 使用 Nginx 代替 Apache（默认：Apache） |
| `--apache` | 强制使用 Apache（默认） |
| `--no-mysql` | 跳过 MySQL 安装 |
| `--no-postgres` | 跳过 PostgreSQL 安装 |

安装器是**幂等的**——可在已有安装上安全地重复运行。已完成的步骤会自动跳过。

## 安装器执行的操作

1. 检测操作系统并验证最低要求
2. 安装 PHP 7.4、8.1、8.2 和 8.3（Ubuntu 使用 ondrej/php PPA；Debian 使用 sury）
3. 安装并配置 Web 服务器（Apache 或 Nginx），监听端口 8880/8881/8882
4. 安装 MySQL 并创建 `novacpx` 数据库和 `novacpx_user` 账户
5. 安装 PostgreSQL（可选，用于客户数据库）
6. 安装并配置 BIND9 用于 DNS 区域管理
7. 安装 Postfix + Dovecot 用于虚拟邮件托管
8. 安装 ProFTPD 用于 FTP 账户管理
9. 安装 OpenDKIM 并将其接入 Postfix
10. 在端口 8883 上安装 Roundcube 网络邮件
11. 安装 Certbot 用于 Let's Encrypt SSL
12. 安装 Fail2Ban 并配置 5 个 jail（sshd + 4 个 NovaCPX 专用 jail）
13. 配置 UFW 防火墙规则
14. 将面板文件复制到 `/srv/novacpx/public/`
15. 设置 systemd 服务和 cron 任务
16. 为面板端口生成自签名 SSL 证书
17. 创建管理员用户并打印凭据

## 安装后

安装器完成后会打印：

```
NovaCPX installed successfully!

Admin panel:  https://<server-ip>:8882
Username:     admin
Password:     <generated>

User panel:   https://<server-ip>:8880
Reseller panel: https://<server-ip>:8881
Webmail:      https://<server-ip>:8883
```

登录管理面板并：

1. 在 **DNS → Nameservers** 下设置你的域名服务器
2. 在 **Settings** 中配置你的服务器 IP
3. 在 **Packages** 下创建你的第一个主机套餐
4. 在 **Accounts → Create** 下创建你的第一个主机账户

## 文件布局

```
/srv/novacpx/public/    Web 根目录（所有面板文件）
  admin/                管理面板前端
  reseller/             经销商面板前端
  user/                 用户面板前端
  api/                  API 后端（PHP）
    endpoints/          每个资源一个文件
  lib/                  共享 PHP 类
  assets/               CSS、JS、图片
  errors/               自定义错误页面

/opt/novacpx/           二进制文件和运行时库
  bin/                  Cron 脚本
  lib/                  指向 /srv/novacpx/public/lib 的符号链接

/opt/novacpx-src/       Git 仓库克隆
/etc/novacpx/           配置文件
  config.ini            主配置（数据库凭据、面板密钥、端口）
  ssl/                  面板 TLS 证书
/var/log/novacpx/       日志文件
```

## 配置文件

`/etc/novacpx/config.ini`：

```ini
[database]
host     = localhost
name     = novacpx
user     = novacpx_user
pass     = <generated>

[panel]
secret   = <generated>      ; 会话令牌的 HMAC 密钥
port_user     = 8880
port_reseller = 8881
port_admin    = 8882
port_webmail  = 8883
webroot  = /srv/novacpx/public
version  = 1.0.0

[web]
server       = apache        ; apache | nginx
php_default  = 8.3

[deploy]
webhook_secret = <generated>
repo_path      = /opt/novacpx-src
web_root       = /srv/novacpx/public
branch         = main
```

## 自动部署（GitHub webhook）

安装器会设置自动部署流水线，使推送到 `main` 分支的更改在一分钟内上线。

1. Webhook 处理程序位于 `https://<server>:8882/deploy/webhook.php`
2. 添加 GitHub webhook：**Settings → Webhooks → Add webhook**
   - Payload URL：`https://<server>:8882/deploy/webhook.php`
   - Content type：`application/json`
   - Secret：`config.ini` 中 `webhook_secret` 的值
   - Events：**Just the push event**
3. Cron 运行器 `/usr/local/bin/novacpx-deploy` 每分钟运行一次并处理部署队列
4. 在任何文件上线之前都会验证 PHP 语法；错误的提交会被自动拒绝

## 升级

```bash
cd /opt/novacpx-src
git pull origin main
```

部署运行器会处理其余所有事项（文件同步、数据库迁移、PHP-FPM 重载）。或者如果已配置 webhook，只需推送到你的 GitHub 远程仓库即可。

## 卸载

没有自动化卸载程序。要移除 NovaCPX：

```bash
rm -rf /srv/novacpx /opt/novacpx /opt/novacpx-src /etc/novacpx
mysql -e "DROP DATABASE novacpx; DROP USER 'novacpx_user'@'localhost';"
rm /etc/apache2/sites-enabled/novacpx.conf   # 或 nginx 对应文件
rm /etc/cron.d/novacpx
```

服务软件包（Apache、Postfix、Dovecot、BIND9 等）是共享的系统服务，会保留在原处。
