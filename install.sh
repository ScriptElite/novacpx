#!/usr/bin/env bash
# NovaCPX 安装程序 — Linux Web 主机控制面板
# 支持系统：Ubuntu 20.04/22.04/24.04，Debian 11/12
# 使用方法：curl -fsSL https://novacpx.io/install.sh | bash
#         或：bash install.sh [--nginx|--apache] [--no-mysql] [--no-postgres]

set -euo pipefail

NOVACPX_VERSION="1.0.0"
PANEL_DIR="/opt/novacpx"
WEB_ROOT="/srv/novacpx/public"
LOG="/var/log/novacpx-install.log"
DB_PATH="/var/lib/novacpx/panel.db"
PHP_DEFAULT="8.3"

# ── 控制面板端口设置（每个层级对应单独的端口）──────────────────────────────────
PORT_USER=8880       # 终端用户面板
PORT_RESELLER=8881   # 代理商面板
PORT_ADMIN=8882      # 管理员 / 数据中心面板
PORT_WEBMAIL=8883    # Roundcube 网页邮局

# ── 颜色样式 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG"; }
fail() { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG"; exit 1; }
info() { echo -e "${BLUE}[→]${NC} $*" | tee -a "$LOG"; }
step() { echo -e "\n${BOLD}━━━ $* ━━━${NC}" | tee -a "$LOG"; }

# ── 参数解析 ──────────────────────────────────────────────────────────────────
WEB_SERVER="nginx"
INSTALL_MYSQL=true
INSTALL_POSTGRES=true

for arg in "$@"; do
  case "$arg" in
    --nginx)       WEB_SERVER="nginx" ;;
    --apache)      WEB_SERVER="apache" ;;
    --no-mysql)    INSTALL_MYSQL=false ;;
    --no-postgres) INSTALL_POSTGRES=false ;;
  esac
done
# ── Banner ─────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
cat <<'EOF'

  ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗  ██████╗██████╗ ██╗  ██╗
  ████╗  ██║██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔══██╗╚██╗██╔╝
  ██╔██╗ ██║██║   ██║██║   ██║███████║██║     ██████╔╝ ╚███╔╝
  ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║██║     ██╔═══╝  ██╔██╗
  ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║╚██████╗██║     ██╔╝ ██╗
  ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚═╝  ╚═╝

  Linux Web Hosting Control Panel  |  v${NOVACPX_VERSION}
  ─────────────────────────────────────────────────────────────
EOF

echo ""

# ── 预检项目 ──────────────────────────────────────────────────────────────────
step "预检项目"

[[ $EUID -ne 0 ]] && fail "必须以 root 身份运行。请使用：sudo bash install.sh"

# 操作系统检测
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_VER="$VERSION_ID"
  OS_CODENAME="${VERSION_CODENAME:-}"
else
  fail "无法检测操作系统。未找到 /etc/os-release 文件。"
fi

case "$OS_ID" in
  ubuntu)
    case "$OS_VER" in
      20.04|22.04|24.04) log "检测到操作系统：Ubuntu $OS_VER" ;;
      *) fail "不支持 Ubuntu $OS_VER。请使用 20.04、22.04 或 24.04。" ;;
    esac
    ;;
  debian)
    case "$OS_VER" in
      11|12|13) log "检测到操作系统：Debian $OS_VER ($OS_CODENAME)" ;;
      *) fail "不支持 Debian $OS_VER。请使用 Debian 11 (Bullseye)、12 (Bookworm) 或 13 (Trixie)。" ;;
    esac
    ;;
  *) fail "不支持的操作系统：$OS_ID。NovaCPX 支持 Ubuntu 20/22/24 以及 Debian 11/12/13。" ;;
esac

log "Web 服务器：$WEB_SERVER"
log "MySQL：$INSTALL_MYSQL | PostgreSQL：$INSTALL_POSTGRES"

# 检查最低系统要求
TOTAL_RAM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
TOTAL_DISK=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
log "内存：${TOTAL_RAM}MB | 剩余磁盘空间：${TOTAL_DISK}GB"
[[ $TOTAL_RAM -lt 512 ]] && warn "内存较低 (${TOTAL_RAM}MB)。建议配置 1GB 以上以获得最佳性能。"
[[ $TOTAL_DISK -lt 5 ]] && fail "磁盘空间不足。需要 5GB 以上可用空间。"

# ── 生成密钥凭据 ──────────────────────────────────────────────────────────────
step "正在生成密钥凭据"

DB_WP_USER="novacpx_wp"
DB_WP_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!@#$' | head -c 20)
ADMIN_PASS=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)
SECRET_KEY=$(openssl rand -hex 32)
mkdir -p /root/.novacpx
cat > /root/.novacpx/credentials.txt <<CREDS
NovaCPX 安装凭据 — $(date)
==========================================
用户面板：       https://$(hostname -I | awk '{print $1}'):${PORT_USER}
代理商面板：     https://$(hostname -I | awk '{print $1}'):${PORT_RESELLER}
管理員面板：     https://$(hostname -I | awk '{print $1}'):${PORT_ADMIN}
网页邮局：       https://$(hostname -I | awk '{print $1}'):${PORT_WEBMAIL}
管理员账号：     admin
管理员密码：     $ADMIN_PASS
面板数据库：     ${DB_PATH}  (SQLite — 无需认证凭据)
DB WP 用户名：   $DB_WP_USER
DB WP 密码：     $DB_WP_PASS
==========================================
请妥善保存此文件，它不会再次显示。
CREDS
chmod 600 /root/.novacpx/credentials.txt
log "凭据已保存至 /root/.novacpx/credentials.txt"

# ── 系统更新 ──────────────────────────────────────────────────────────────────
step "正在更新系统软件包"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >> "$LOG" 2>&1
apt-get upgrade -y -qq >> "$LOG" 2>&1
apt-get install -y -qq curl wget gnupg2 lsb-release ca-certificates \
  software-properties-common apt-transport-https zip unzip git \
  sudo cron logrotate ufw fail2ban sshpass sqlite3 >> "$LOG" 2>&1
log "系统软件包更新完成"

# ── PHP 多版本安装配置 ────────────────────────────────────────────────────────
step "正在安装 PHP (多版本)"

# Ubuntu 使用 ondrej/php PPA 存储库；Debian 使用 sury 存储库
if [[ "$OS_ID" == "ubuntu" ]]; then
  add-apt-repository -y ppa:ondrej/php >> "$LOG" 2>&1
elif [[ "$OS_ID" == "debian" ]]; then
  curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-php.gpg
  echo "deb https://packages.sury.org/php/ $OS_CODENAME main" > /etc/apt/sources.list.d/sury-php.list
fi

apt-get update -qq >> "$LOG" 2>&1

PHP_VERSIONS=("7.4" "8.1" "8.2" "8.3" "8.4" "8.5")
PHP_EXTENSIONS="cli fpm common mysql pgsql sqlite3 gd curl mbstring xml zip bcmath intl soap redis imagick opcache"

for VER in "${PHP_VERSIONS[@]}"; do
  info "正在安装 PHP $VER..."
  PKGS=""
  for EXT in $PHP_EXTENSIONS; do
    PKGS="$PKGS php${VER}-${EXT}"
  done
  apt-get install -y -qq php${VER} $PKGS >> "$LOG" 2>&1 || warn "PHP $VER：部分扩展可能不可用"
  log "PHP $VER 安装完成"
done

# 设置默认 PHP CLI 版本
update-alternatives --set php /usr/bin/php${PHP_DEFAULT} >> "$LOG" 2>&1 || true
log "默认 PHP CLI：$PHP_DEFAULT"

# ── Web 服务器 ────────────────────────────────────────────────────────────────
step "正在安装 Web 服务器 ($WEB_SERVER)"

if [[ "$WEB_SERVER" == "nginx" ]]; then
  apt-get install -y -qq nginx >> "$LOG" 2>&1
  systemctl enable nginx >> "$LOG" 2>&1
  # 转发 Authorization 标头至 PHP-FPM —— nginx 默认会剥离该标头，
  # 否则会导致全面板所有依赖 Bearer-token 的 API 调用静默失效。
  echo 'fastcgi_param HTTP_AUTHORIZATION $http_authorization;' >> /etc/nginx/fastcgi_params
  log "nginx 安装完成"

  PANEL_WEB_CONF="/etc/nginx/sites-available/novacpx"
  cat > "$PANEL_WEB_CONF" <<NGXCONF
# NovaCPX — 运行于三个独立端口上的三个控制面板

# ── 用户面板 (8880) ───────────────────────────────────────────────────────────
server {
    listen ${PORT_USER} ssl http2;
    server_name _;
    root ${WEB_ROOT}/user;
    index index.php;
    ssl_certificate     /etc/novacpx/ssl/novacpx.crt;
    ssl_certificate_key /etc/novacpx/ssl/novacpx.key;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api/ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME ${WEB_ROOT}/api/index.php; }
    location ~ \.php$ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; }
    location /assets/ { root ${WEB_ROOT}; }
    location ~ /\.ht { deny all; }
}

# ── 代理商面板 (8881) ─────────────────────────────────────────────────────────
server {
    listen ${PORT_RESELLER} ssl http2;
    server_name _;
    root ${WEB_ROOT}/reseller;
    index index.php;
    ssl_certificate     /etc/novacpx/ssl/novacpx.crt;
    ssl_certificate_key /etc/novacpx/ssl/novacpx.key;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api/ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME ${WEB_ROOT}/api/index.php; }
    location ~ \.php$ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; }
    location /assets/ { root ${WEB_ROOT}; }
    location ~ /\.ht { deny all; }
}

# ── 管理员面板 (8882) ─────────────────────────────────────────────────────────
server {
    listen ${PORT_ADMIN} ssl http2;
    server_name _;
    root ${WEB_ROOT}/admin;
    index index.php;
    ssl_certificate     /etc/novacpx/ssl/novacpx.crt;
    ssl_certificate_key /etc/novacpx/ssl/novacpx.key;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api/ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME ${WEB_ROOT}/api/index.php; }
    location ~ \.php$ { fastcgi_pass unix:/run/php/php${PHP_DEFAULT}-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; }
    location /assets/ { root ${WEB_ROOT}; }
    location ~ /\.ht { deny all; }
}
NGXCONF
  ln -sf "$PANEL_WEB_CONF" /etc/nginx/sites-enabled/novacpx
  # 允许 www-data 用户组管理客户的虚拟主机配置文件
  chown root:www-data /etc/nginx/sites-available /etc/nginx/sites-enabled
  chmod 775 /etc/nginx/sites-available /etc/nginx/sites-enabled

else
  apt-get install -y -qq apache2 libapache2-mod-fcgid >> "$LOG" 2>&1
  a2enmod ssl rewrite proxy_fcgi setenvif headers >> "$LOG" 2>&1
  systemctl enable apache2 >> "$LOG" 2>&1
  log "Apache2 安装完成"

  # 配置 Apache 监听全部四个面板端口
  for PORT in $PORT_USER $PORT_RESELLER $PORT_ADMIN $PORT_WEBMAIL; do
    grep -q "Listen $PORT" /etc/apache2/ports.conf 2>/dev/null || echo "Listen $PORT" >> /etc/apache2/ports.conf
  done

  PANEL_WEB_CONF="/etc/apache2/sites-available/novacpx.conf"
  cat > "$PANEL_WEB_CONF" <<APCONF
# NovaCPX — 运行于三个独立端口上的三个控制面板

# ── 用户面板 (8880) ───────────────────────────────────────────────────────────
<VirtualHost *:${PORT_USER}>
    DocumentRoot ${WEB_ROOT}/user
    SSLEngine on
    SSLCertificateFile    /etc/novacpx/ssl/novacpx.crt
    SSLCertificateKeyFile /etc/novacpx/ssl/novacpx.key
    Alias /assets ${WEB_ROOT}/assets
    Alias /api    ${WEB_ROOT}/api
    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch "\.php\$">
        SetHandler "proxy:unix:/run/php/php${PHP_DEFAULT}-fpm.sock|fcgi://localhost/"
    </FilesMatch>
    Header always set X-NovaCPX-Portal "user"
</VirtualHost>

# ── 代理商面板 (8881) ─────────────────────────────────────────────────────────
<VirtualHost *:${PORT_RESELLER}>
    DocumentRoot ${WEB_ROOT}/reseller
    SSLEngine on
    SSLCertificateFile    /etc/novacpx/ssl/novacpx.crt
    SSLCertificateKeyFile /etc/novacpx/ssl/novacpx.key
    Alias /assets ${WEB_ROOT}/assets
    Alias /api    ${WEB_ROOT}/api
    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch "\.php\$">
        SetHandler "proxy:unix:/run/php/php${PHP_DEFAULT}-fpm.sock|fcgi://localhost/"
    </FilesMatch>
    Header always set X-NovaCPX-Portal "reseller"
</VirtualHost>

# ── 管理员面板 (8882) ─────────────────────────────────────────────────────────
<VirtualHost *:${PORT_ADMIN}>
    DocumentRoot ${WEB_ROOT}/admin
    SSLEngine on
    SSLCertificateFile    /etc/novacpx/ssl/novacpx.crt
    SSLCertificateKeyFile /etc/novacpx/ssl/novacpx.key
    Alias /assets ${WEB_ROOT}/assets
    Alias /api    ${WEB_ROOT}/api
    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch "\.php\$">
        SetHandler "proxy:unix:/run/php/php${PHP_DEFAULT}-fpm.sock|fcgi://localhost/"
    </FilesMatch>
    Header always set X-NovaCPX-Portal "admin"
</VirtualHost>
APCONF
  a2ensite novacpx >> "$LOG" 2>&1
  a2enconf php${PHP_DEFAULT}-fpm >> "$LOG" 2>&1 || true
fi

# 启用 PHP-FPM 服务
for VER in "${PHP_VERSIONS[@]}"; do
  systemctl enable php${VER}-fpm >> "$LOG" 2>&1 && systemctl start php${VER}-fpm >> "$LOG" 2>&1 || true
  # 允许无限制执行时间，以便长时运行的面板任务（软件包安装、WordPress 等）不会被中断终止
  grep -q "php_admin_value\[max_execution_time\]" /etc/php/${VER}/fpm/pool.d/www.conf 2>/dev/null || \
    echo "php_admin_value[max_execution_time] = 0" >> /etc/php/${VER}/fpm/pool.d/www.conf
done

# ── MySQL ─────────────────────────────────────────────────────────────────────
if $INSTALL_MYSQL; then
  step "正在安装 MySQL 8"
  apt-get install -y -qq mysql-server >> "$LOG" 2>&1
  systemctl enable mysql >> "$LOG" 2>&1
  systemctl start mysql >> "$LOG" 2>&1
  # 用于 WordPress 数据库调配的高权用户（创建数据库 + 创建用户 + 授权）
  mysql -e "CREATE USER IF NOT EXISTS '${DB_WP_USER}'@'localhost' IDENTIFIED BY '${DB_WP_PASS}';" >> "$LOG" 2>&1
  mysql -e "GRANT ALL PRIVILEGES ON \`wp\_%\`.* TO '${DB_WP_USER}'@'localhost';" >> "$LOG" 2>&1
  mysql -e "GRANT CREATE USER ON *.* TO '${DB_WP_USER}'@'localhost' WITH GRANT OPTION;" >> "$LOG" 2>&1
  mysql -e "FLUSH PRIVILEGES;" >> "$LOG" 2>&1
  log "MySQL 安装完成且数据库创建完毕"
fi

# ── PostgreSQL ────────────────────────────────────────────────────────────────
if $INSTALL_POSTGRES; then
  step "正在安装 PostgreSQL"
  apt-get install -y -qq postgresql postgresql-contrib >> "$LOG" 2>&1
  systemctl enable postgresql >> "$LOG" 2>&1
  log "PostgreSQL 安装完成"
fi

# ── BIND9 DNS ─────────────────────────────────────────────────────────────────
step "正在安装 BIND9 DNS 服务器"
apt-get install -y -qq bind9 bind9utils bind9-doc >> "$LOG" 2>&1
systemctl enable named >> "$LOG" 2>&1

cat > /etc/bind/named.conf.options <<BINDCONF
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-recursion { localhost; };
    listen-on { any; };
    forwarders { 8.8.8.8; 1.1.1.1; };
    dnssec-validation auto;
    auth-nxdomain no;
};
BINDCONF

systemctl restart named >> "$LOG" 2>&1
log "BIND9 DNS 安装完成"

# ── Postfix + Dovecot (邮件服务器) ───────────────────────────────────────────
step "正在安装邮件服务器 (Postfix + Dovecot)"
HOSTNAME=$(hostname -f)
debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install -y -qq postfix postfix-mysql dovecot-core dovecot-imapd \
  dovecot-pop3d dovecot-lmtpd dovecot-mysql spamassassin >> "$LOG" 2>&1
systemctl enable postfix dovecot >> "$LOG" 2>&1
log "邮件服务器安装完成 (Postfix + Dovecot)"

# ── ProFTPD ───────────────────────────────────────────────────────────────────
step "正在安装 ProFTPD"
apt-get install -y -qq proftpd-basic proftpd-mod-mysql >> "$LOG" 2>&1
systemctl enable proftpd >> "$LOG" 2>&1
log "ProFTPD 安装完成"

# ── OpenDKIM ─────────────────────────────────────────────────────────────────
step "正在安装 OpenDKIM"
apt-get install -y -qq opendkim opendkim-tools >> "$LOG" 2>&1
mkdir -p /etc/opendkim/keys
cat >> /etc/opendkim/opendkim.conf <<DKIM
Mode                    sv
Canonicalization        relaxed/simple
KeyTable                /etc/opendkim/key.table
SigningTable            refile:/etc/opendkim/signing.table
ExternalIgnoreList      refile:/etc/opendkim/trusted.hosts
InternalHosts           refile:/etc/opendkim/trusted.hosts
DKIM
touch /etc/opendkim/key.table /etc/opendkim/signing.table
echo "127.0.0.1\nlocalhost" > /etc/opendkim/trusted.hosts
chown -R opendkim:opendkim /etc/opendkim
# 将 OpenDKIM 集成接入 Postfix
postconf -e "milter_default_action = accept" >> "$LOG" 2>&1
postconf -e "smtpd_milters = local:/run/opendkim/opendkim.sock" >> "$LOG" 2>&1
postconf -e "non_smtpd_milters = local:/run/opendkim/opendkim.sock" >> "$LOG" 2>&1
systemctl enable opendkim >> "$LOG" 2>&1
log "OpenDKIM 安装完成"

# ── SSL 证书 ─────────────────────────────────────────────────────────────────
step "正在生成自签名 SSL 证书 (面板专享)"
mkdir -p /etc/novacpx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/novacpx/ssl/novacpx.key \
  -out /etc/novacpx/ssl/novacpx.crt \
  -subj "/CN=$(hostname -I | awk '{print $1}')/O=NovaCPX/C=US" >> "$LOG" 2>&1
chmod 600 /etc/novacpx/ssl/novacpx.key
log "SSL 证书生成完毕"

# 安装用于 Let's Encrypt 的 certbot
apt-get install -y -qq certbot >> "$LOG" 2>&1
log "已安装用于 Let's Encrypt SSL 的 Certbot"

# ── Roundcube Webmail ─────────────────────────────────────────────────────────
step "正在安装 Roundcube Webmail (端口 ${PORT_WEBMAIL})"
apt-get install -y -qq roundcube roundcube-mysql php8.3-intl php8.3-ldap >> "$LOG" 2>&1
RC_ROOT="/usr/share/roundcube"
mkdir -p /etc/novacpx/roundcube

# Roundcube 配置
RC_DB_PASS=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)
mysql -e "CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >> "$LOG" 2>&1
mysql -e "CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY '${RC_DB_PASS}';" >> "$LOG" 2>&1
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';" >> "$LOG" 2>&1
mysql roundcube < /usr/share/dbconfig-common/data/roundcube/install/mysql 2>/dev/null || true

cat > /etc/roundcube/config.inc.php <<RCCONF
<?php
\$config['db_dsnw'] = 'mysql://roundcube:${RC_DB_PASS}@localhost/roundcube';
\$config['default_host'] = 'localhost';
\$config['default_port'] = 143;
\$config['smtp_server'] = 'localhost';
\$config['smtp_port'] = 587;
\$config['des_key'] = '$(openssl rand -base64 24 | head -c 24)';
\$config['plugins'] = ['archive','attachment_reminder','emoticons','markasjunk','newmail_notifier','zipdownload'];
\$config['skin'] = 'elastic';
\$config['session_lifetime'] = 60;
\$config['product_name'] = 'NovaCPX Webmail';
RCCONF

# 8883 端口上的 Webmail 虚拟主机配置
if [[ "$WEB_SERVER" == "nginx" ]]; then
  cat >> "$PANEL_WEB_CONF" <<WMNGX

# ── Webmail (8883) ────────────────────────────────────────────────────────────
server {
    listen ${PORT_WEBMAIL} ssl http2;
    server_name _;
    root ${RC_ROOT};
    index index.php;
    ssl_certificate     /etc/novacpx/ssl/novacpx.crt;
    ssl_certificate_key /etc/novacpx/ssl/novacpx.key;
    location / { try_files \$uri \$uri/ /index.php; }
    location ~ \.php$ { fastcgi_pass unix:/run/php/php8.3-fpm.sock; include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; }
    location ~ /\.(ht|git) { deny all; }
}
WMNGX
else
  cat >> "$PANEL_WEB_CONF" <<WMAP

# ── Webmail (8883) ────────────────────────────────────────────────────────────
<VirtualHost *:${PORT_WEBMAIL}>
    DocumentRoot ${RC_ROOT}
    SSLEngine on
    SSLCertificateFile    /etc/novacpx/ssl/novacpx.crt
    SSLCertificateKeyFile /etc/novacpx/ssl/novacpx.key
    <Directory ${RC_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php8.3-fpm.sock|fcgi://localhost/"
    </FilesMatch>
    Header always set X-NovaCPX-Portal "webmail"
</VirtualHost>
WMAP
fi

log "Roundcube webmail 已成功安装于端口 ${PORT_WEBMAIL}"

# ── 面板安装 ──────────────────────────────────────────────────────────────────
step "正在安装 NovaCPX 面板"
mkdir -p "$WEB_ROOT" "$PANEL_DIR"

if [[ ! -d /opt/novacpx-src ]]; then
  info "正在克隆 NovaCPX 源码..."
  git clone --quiet https://github.com/scriptelite/novacpx.git /opt/novacpx-src >> "$LOG" 2>&1
fi

# 从 GitHub 安装面板文件
if [[ -d /opt/novacpx-src ]]; then
  cp -r /opt/novacpx-src/panel/public/. "$WEB_ROOT/"
  mkdir -p "$WEB_ROOT/api" "$WEB_ROOT/lib"
  cp -r /opt/novacpx-src/panel/api/. "$WEB_ROOT/api/"
  cp -r /opt/novacpx-src/panel/lib/. "$WEB_ROOT/lib/"
  cp -r /opt/novacpx-src/panel/lib /opt/novacpx/lib
  cp /opt/novacpx-src/VERSION "$WEB_ROOT/VERSION" 2>/dev/null || true
fi

# 写入配置文件
mkdir -p /etc/novacpx
cat > /etc/novacpx/config.ini <<CONFIG
[database]
path     = ${DB_PATH}
wp_user  = ${DB_WP_USER}
wp_pass  = ${DB_WP_PASS}

[panel]
secret        = ${SECRET_KEY}
port_user     = ${PORT_USER}
port_reseller = ${PORT_RESELLER}
port_admin    = ${PORT_ADMIN}
port_webmail  = ${PORT_WEBMAIL}
webroot       = ${WEB_ROOT}
version       = ${NOVACPX_VERSION}

[web]
server      = ${WEB_SERVER}
php_default = ${PHP_DEFAULT}
CONFIG
chown root:www-data /etc/novacpx/config.ini
chmod 640 /etc/novacpx/config.ini

# 创建 SQLite 面板数据库
mkdir -p /var/lib/novacpx
if [[ -f /opt/novacpx-src/db/schema.sql ]]; then
  sqlite3 "$DB_PATH" < /opt/novacpx-src/db/schema.sql >> "$LOG" 2>&1
  # 创建管理员账号
  ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT);")
  sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO users (username,password,email,role,status) VALUES ('admin','${ADMIN_HASH}','root@localhost','admin','active');" >> "$LOG" 2>&1
  # 填充反向代理默认设置
  sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO settings (key, value) VALUES ('proxy_mode','disabled'),('proxy_apache_port','80');" >> "$LOG" 2>&1
  log "SQLite 面板数据库已创建，管理员账号已填充"
fi
chown www-data:www-data /var/lib/novacpx
chown www-data:www-data "$DB_PATH"
chmod 660 "$DB_PATH"

# 设置目录权限
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 750 "$WEB_ROOT"

# ── 防火墙配置 ────────────────────────────────────────────────────────────────
step "正在配置防火墙 (UFW)"
ufw --force reset >> "$LOG" 2>&1
ufw default deny incoming >> "$LOG" 2>&1
ufw default allow outgoing >> "$LOG" 2>&1
ufw allow ssh >> "$LOG" 2>&1
ufw allow 80/tcp >> "$LOG" 2>&1    # HTTP
ufw allow 443/tcp >> "$LOG" 2>&1   # HTTPS
ufw allow ${PORT_USER}/tcp     >> "$LOG" 2>&1  # NovaCPX 用户面板
ufw allow ${PORT_RESELLER}/tcp >> "$LOG" 2>&1  # NovaCPX 代理商面板
ufw allow ${PORT_ADMIN}/tcp    >> "$LOG" 2>&1  # NovaCPX 管理员面板
ufw allow ${PORT_WEBMAIL}/tcp  >> "$LOG" 2>&1  # Roundcube 网页邮局
ufw allow 21/tcp >> "$LOG" 2>&1    # FTP
ufw allow 20/tcp >> "$LOG" 2>&1    # FTP 数据传输
ufw allow 25/tcp >> "$LOG" 2>&1    # SMTP
ufw allow 587/tcp >> "$LOG" 2>&1   # SMTP 提交
ufw allow 465/tcp >> "$LOG" 2>&1   # SMTPS
ufw allow 110/tcp >> "$LOG" 2>&1   # POP3
ufw allow 995/tcp >> "$LOG" 2>&1   # POP3S
ufw allow 143/tcp >> "$LOG" 2>&1   # IMAP
ufw allow 993/tcp >> "$LOG" 2>&1   # IMAPS
ufw allow 53/tcp >> "$LOG" 2>&1    # DNS
ufw allow 53/udp >> "$LOG" 2>&1    # DNS
ufw --force enable >> "$LOG" 2>&1
log "防火墙配置完成"

# ── Fail2Ban 防护配置 ─────────────────────────────────────────────────────────
step "正在配置 Fail2Ban"

# 自动检测本地 IP 并列入白名单（本地环回 + 所有私有网卡 IP + 其对应的 /24 子网）
LOCAL_IPS="127.0.0.0/8 ::1"
while read -r cidr; do
  ip="${cidr%%/*}"
  LOCAL_IPS="$LOCAL_IPS $ip"
  # 为私有 IP 网段自动追加 /24 子网
  case "$ip" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
      subnet=$(echo "$ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
      LOCAL_IPS="$LOCAL_IPS $subnet"
      ;;
  esac
done < <(ip -4 addr show 2>/dev/null | grep 'inet ' | awk '{print $2}')
# 去重处理
LOCAL_IPS=$(echo "$LOCAL_IPS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
log "Fail2Ban 白名单列表：$LOCAL_IPS"

cat > /etc/fail2ban/jail.local <<F2B
[DEFAULT]
bantime   = 3600
findtime  = 600
maxretry  = 5
ignoreip  = ${LOCAL_IPS}

[sshd]
enabled = true

[novacpx-user]
enabled  = true
port     = ${PORT_USER}
logpath  = /var/log/novacpx/access.log
maxretry = 10

[novacpx-reseller]
enabled  = true
port     = ${PORT_RESELLER}
logpath  = /var/log/novacpx/access.log
maxretry = 10

[novacpx-admin]
enabled  = true
port     = ${PORT_ADMIN}
logpath  = /var/log/novacpx/access.log
maxretry = 5

[novacpx-webmail]
enabled  = true
port     = ${PORT_WEBMAIL}
logpath  = /var/log/novacpx/access.log
maxretry = 10
F2B
chown root:www-data /etc/fail2ban/jail.local
chmod 664 /etc/fail2ban/jail.local

# 安装 NovaCPX 过滤规则定义文件
for jail in novacpx-user novacpx-reseller novacpx-admin novacpx-webmail; do
  cp /opt/novacpx-src/deploy/fail2ban/${jail}.conf /etc/fail2ban/filter.d/ 2>/dev/null || \
  cat > /etc/fail2ban/filter.d/${jail}.conf << 'FILTER'
[Definition]
failregex = ^.+ FAILED LOGIN from <HOST>
ignoreregex =
FILTER
done

# 创建供 www-data 可写的 NovaCPX 访问日志文件
mkdir -p /var/log/novacpx
chown www-data:www-data /var/log/novacpx
touch /var/log/novacpx/access.log
chown www-data:www-data /var/log/novacpx/access.log
chmod 664 /var/log/novacpx/access.log

systemctl enable fail2ban >> "$LOG" 2>&1
systemctl restart fail2ban >> "$LOG" 2>&1
log "Fail2Ban 配置完成"

# ── NovaCPX 面板的 Sudoers 权限配置（www-data 需要 root 权限以管理防火墙/OpenDKIM 等） ──
cat > /etc/sudoers.d/novacpx-firewall <<SUDOERS
Defaults:www-data !requiretty
# 防火墙 / 安全
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw status
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw status verbose
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw allow *
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw deny *
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw delete *
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw reload
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw enable
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw disable
www-data ALL=(root) NOPASSWD: /usr/sbin/ufw logging *
www-data ALL=(root) NOPASSWD: /usr/bin/fail2ban-client *
# Web 服务器
www-data ALL=(root) NOPASSWD: /bin/systemctl start apache2
www-data ALL=(root) NOPASSWD: /bin/systemctl stop apache2
www-data ALL=(root) NOPASSWD: /bin/systemctl restart apache2
www-data ALL=(root) NOPASSWD: /bin/systemctl reload apache2
www-data ALL=(root) NOPASSWD: /bin/systemctl enable apache2
www-data ALL=(root) NOPASSWD: /bin/systemctl start nginx
www-data ALL=(root) NOPASSWD: /bin/systemctl stop nginx
www-data ALL=(root) NOPASSWD: /bin/systemctl restart nginx
www-data ALL=(root) NOPASSWD: /bin/systemctl reload nginx
www-data ALL=(root) NOPASSWD: /bin/systemctl enable nginx
www-data ALL=(root) NOPASSWD: /usr/sbin/nginx *
# 邮件服务器
www-data ALL=(root) NOPASSWD: /bin/systemctl start postfix
www-data ALL=(root) NOPASSWD: /bin/systemctl stop postfix
www-data ALL=(root) NOPASSWD: /bin/systemctl restart postfix
www-data ALL=(root) NOPASSWD: /bin/systemctl reload postfix
www-data ALL=(root) NOPASSWD: /bin/systemctl start dovecot
www-data ALL=(root) NOPASSWD: /bin/systemctl stop dovecot
www-data ALL=(root) NOPASSWD: /bin/systemctl restart dovecot
www-data ALL=(root) NOPASSWD: /bin/systemctl reload dovecot
www-data ALL=(root) NOPASSWD: /bin/systemctl start rspamd
www-data ALL=(root) NOPASSWD: /bin/systemctl stop rspamd
www-data ALL=(root) NOPASSWD: /bin/systemctl restart rspamd
www-data ALL=(root) NOPASSWD: /bin/systemctl enable rspamd
www-data ALL=(root) NOPASSWD: /bin/systemctl disable rspamd
www-data ALL=(root) NOPASSWD: /usr/sbin/postqueue -f
# FTP 服务器
www-data ALL=(root) NOPASSWD: /bin/systemctl start proftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl stop proftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl restart proftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl reload proftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl enable proftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl start vsftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl stop vsftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl restart vsftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl enable vsftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl start pure-ftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl stop pure-ftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl restart pure-ftpd
www-data ALL=(root) NOPASSWD: /bin/systemctl enable pure-ftpd
# DNS 服务器
www-data ALL=(root) NOPASSWD: /bin/systemctl start named
www-data ALL=(root) NOPASSWD: /bin/systemctl stop named
www-data ALL=(root) NOPASSWD: /bin/systemctl restart named
www-data ALL=(root) NOPASSWD: /bin/systemctl reload named
www-data ALL=(root) NOPASSWD: /bin/systemctl start bind9
www-data ALL=(root) NOPASSWD: /bin/systemctl stop bind9
www-data ALL=(root) NOPASSWD: /bin/systemctl restart bind9
www-data ALL=(root) NOPASSWD: /bin/systemctl start pdns
www-data ALL=(root) NOPASSWD: /bin/systemctl stop pdns
www-data ALL=(root) NOPASSWD: /bin/systemctl restart pdns
www-data ALL=(root) NOPASSWD: /bin/systemctl start nsd
www-data ALL=(root) NOPASSWD: /bin/systemctl stop nsd
www-data ALL=(root) NOPASSWD: /bin/systemctl restart nsd
# 数据库服务器
www-data ALL=(root) NOPASSWD: /bin/systemctl start mysql
www-data ALL=(root) NOPASSWD: /bin/systemctl stop mysql
www-data ALL=(root) NOPASSWD: /bin/systemctl restart mysql
www-data ALL=(root) NOPASSWD: /bin/systemctl start mariadb
www-data ALL=(root) NOPASSWD: /bin/systemctl stop mariadb
www-data ALL=(root) NOPASSWD: /bin/systemctl restart mariadb
# 安全服务
www-data ALL=(root) NOPASSWD: /bin/systemctl start fail2ban
www-data ALL=(root) NOPASSWD: /bin/systemctl stop fail2ban
www-data ALL=(root) NOPASSWD: /bin/systemctl restart fail2ban
www-data ALL=(root) NOPASSWD: /bin/systemctl reload fail2ban
# PHP-FPM 服务
www-data ALL=(root) NOPASSWD: /bin/systemctl reload php*-fpm
www-data ALL=(root) NOPASSWD: /bin/systemctl restart php*-fpm
www-data ALL=(root) NOPASSWD: /bin/systemctl start php*-fpm
www-data ALL=(root) NOPASSWD: /bin/systemctl stop php*-fpm
www-data ALL=(root) NOPASSWD: /usr/bin/tee /etc/php/*/fpm/pool.d/*
www-data ALL=(root) NOPASSWD: /bin/rm -f /etc/php/*/fpm/pool.d/*.conf
www-data ALL=(root) NOPASSWD: /usr/bin/rm -f /etc/php/*/fpm/pool.d/*.conf
# Web 配置文件管理（仅限指定作用域路径）
www-data ALL=(root) NOPASSWD: /usr/bin/tee /etc/nginx/conf.d/*
www-data ALL=(root) NOPASSWD: /usr/bin/tee /etc/nginx/sites-available/*
www-data ALL=(root) NOPASSWD: /usr/bin/tee /etc/nginx/sites-enabled/*
www-data ALL=(root) NOPASSWD: /usr/bin/tee /etc/apache2/conf-enabled/*
www-data ALL=(root) NOPASSWD: /bin/ln -sf /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*
www-data ALL=(root) NOPASSWD: /bin/rm /etc/nginx/sites-available/novacpx-*
www-data ALL=(root) NOPASSWD: /bin/rm /etc/nginx/sites-enabled/novacpx-*
# 账号管理（用户创建与家目录管理）
www-data ALL=(root) NOPASSWD: /usr/sbin/useradd *
www-data ALL=(root) NOPASSWD: /usr/sbin/userdel *
www-data ALL=(root) NOPASSWD: /usr/sbin/usermod *
www-data ALL=(root) NOPASSWD: /usr/sbin/chpasswd
www-data ALL=(root) NOPASSWD: /bin/mkdir *
www-data ALL=(root) NOPASSWD: /bin/chown *
www-data ALL=(root) NOPASSWD: /bin/chmod *
# SSL 与 DKIM 密钥
www-data ALL=(root) NOPASSWD: /usr/bin/certbot *
www-data ALL=(root) NOPASSWD: /usr/bin/opendkim-genkey *
www-data ALL=(root) NOPASSWD: /usr/sbin/rndc reload
www-data ALL=(root) NOPASSWD: /usr/sbin/named-checkzone *
SUDOERS
chmod 440 /etc/sudoers.d/novacpx-firewall
log "Sudoers 提权规则已安装"

# ── 定时任务 (Cron) ───────────────────────────────────────────────────────────
step "正在设置定时任务 (Cron Jobs)"
cat > /etc/cron.d/novacpx <<CRON
# NovaCPX 系统定时任务
*/5  * * * * www-data /usr/bin/php${PHP_DEFAULT} ${WEB_ROOT}/bin/collect-stats.php >> /var/log/novacpx/cron.log 2>&1
0    0 * * * www-data /usr/bin/php${PHP_DEFAULT} ${WEB_ROOT}/bin/notify-checks.php >> /var/log/novacpx/cron.log 2>&1
0    * * * * root     /usr/local/bin/novacpx-ssl-renew >> /var/log/novacpx/ssl.log 2>&1
0    2 * * * root     /usr/local/bin/novacpx-backup >> /var/log/novacpx/backup.log 2>&1
*/1  * * * * root     /usr/local/bin/novacpx-dns-sync >> /var/log/novacpx/dns.log 2>&1
CRON

# PHP-FPM 池清理 + 延迟重载（以 root 权限每分钟运行一次）
# 在重载前清理已删除 Linux 用户的孤立 Pool 配置文件，
# 避免 PHP-FPM 因找不到引用的用户而导致服务启动失败。
((crontab -l 2>/dev/null || true) | grep -v "novacpx-fpm-reload" || true; echo '* * * * * for f in /etc/php/*/fpm/pool.d/*.conf; do [[ "$f" == *"www.conf"* ]] && continue; u=$(basename "$f" .conf); id "$u" &>/dev/null || rm -f "$f"; done; for flag in /tmp/novacpx-fpm-reload-*; do [ -f "$flag" ] && ver=$(basename "$flag" | sed s/novacpx-fpm-reload-//) && rm -f "$flag" && systemctl reload php${ver}-fpm 2>/dev/null; done') | crontab -
mkdir -p /var/log/novacpx
log "定时任务设置完成"

# ── 禁用冲突的 Web 服务器 ──────────────────────────────────────────────────────
step "正在禁用冲突的 Web 服务器"
if [[ "$WEB_SERVER" == "nginx" ]]; then
  systemctl stop apache2 2>/dev/null || true
  systemctl disable apache2 2>/dev/null || true
  # 将 Nginx 默认站点替换为 444 连接直接关闭，
  # 避免未匹配的虚拟主机意外展示 Apache 的默认 HTML 页面
  cat > /etc/nginx/sites-available/default <<'NGINXDEFAULT'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
NGINXDEFAULT
  log "Apache2 已禁用；Nginx 默认站点已设置为返回 444 错误码"
fi

# ── 重启服务 ──────────────────────────────────────────────────────────────────
step "正在禁用 php-fpm 的 systemd 沙盒隔离（面板需要读写 /etc 与 /home 目录）"
for VER in "${PHP_VERSIONS[@]}"; do
  mkdir -p /etc/systemd/system/php${VER}-fpm.service.d
  cat > /etc/systemd/system/php${VER}-fpm.service.d/override.conf <<OVERRIDE
[Service]
ProtectSystem=false
ProtectHome=false
OVERRIDE
done
systemctl daemon-reload >> "$LOG" 2>&1
for VER in "${PHP_VERSIONS[@]}"; do
  systemctl restart php${VER}-fpm >> "$LOG" 2>&1
done
log "php-fpm 沙盒限制已解除"

step "正在启动所有服务"
if [[ "$WEB_SERVER" == "nginx" ]]; then
  systemctl restart nginx >> "$LOG" 2>&1
else
  systemctl restart apache2 >> "$LOG" 2>&1
fi
$INSTALL_MYSQL && systemctl restart mysql >> "$LOG" 2>&1
systemctl restart postfix dovecot proftpd named opendkim >> "$LOG" 2>&1
log "所有服务已成功启动"

# ── 完成 ──────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
cat <<DONE

  ╔══════════════════════════════════════════════════════════════╗
  ║                 NovaCPX 安装完成！                           ║
  ╠══════════════════════════════════════════════════════════════╣
  ║  用户面板：     https://${SERVER_IP}:${PORT_USER}
  ║  代理商面板：   https://${SERVER_IP}:${PORT_RESELLER}
  ║  管理员面板：   https://${SERVER_IP}:${PORT_ADMIN}
  ║  网页邮局：     https://${SERVER_IP}:${PORT_WEBMAIL}
  ║  管理员账号：   admin
  ║  管理员密码：   ${ADMIN_PASS}
  ╠══════════════════════════════════════════════════════════════╣
  ║  认证凭据存储于： /root/.novacpx/credentials.txt            ║
  ║  安装日志路径：   ${LOG}
  ╚══════════════════════════════════════════════════════════════╝

DONE
