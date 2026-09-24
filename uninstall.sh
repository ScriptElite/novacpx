#!/usr/bin/env bash
# NovaCPX 卸载程序
# 备份所有内容，然后干净地移除所有 NovaCPX 组件。
# 用法：bash uninstall.sh [--yes]

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${BOLD}━━━ $* ━━━${NC}"; }

[[ $EUID -ne 0 ]] && fail "以 root 身份运行"

SKIP_CONFIRM="${1:-}"
DB_PATH=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('/etc/novacpx/config.ini'); print(c.get('database','path',fallback='/var/lib/novacpx/panel.db'))" 2>/dev/null || echo "/var/lib/novacpx/panel.db")
BACKUP_DIR="/tmp/novacpx-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_ARCHIVE="${BACKUP_DIR}.tar.gz"

echo ""
echo -e "${BOLD}NovaCPX 卸载程序${NC}"
echo "这将完全移除 NovaCPX 及所有托管账户。"
echo ""

# ── 步骤 1：创建完整备份 ─────────────────────────────────────────────
step "在移除前创建完整备份"

mkdir -p "$BACKUP_DIR"/{db,configs,accounts,logs,certs,nginx,systemd,cron}

# 数据库
[[ -f "$DB_PATH" ]] && {
    cp "$DB_PATH" "$BACKUP_DIR/db/panel.db"
    log "数据库已备份"
}

# 所有账户主目录
if [[ -f "$DB_PATH" ]]; then
    while IFS='|' read -r user home; do
        [[ -d "$home" ]] && cp -a "$home" "$BACKUP_DIR/accounts/" 2>/dev/null && log "账户：$user ($home)"
    done < <(sqlite3 "$DB_PATH" "SELECT username, home_dir FROM accounts;" 2>/dev/null)
fi

# 配置文件
[[ -d /etc/novacpx ]] && cp -a /etc/novacpx "$BACKUP_DIR/configs/" && log "NovaCPX 配置"
[[ -d /var/lib/novacpx ]] && cp -a /var/lib/novacpx "$BACKUP_DIR/db/var-lib-novacpx" 2>/dev/null

# Nginx 虚拟主机
cp /etc/nginx/sites-available/novacpx-*.conf "$BACKUP_DIR/nginx/" 2>/dev/null || true
log "Nginx 虚拟主机"

# 每个账户的 SSL 证书
[[ -d /etc/novacpx/ssl/accounts ]] && cp -a /etc/novacpx/ssl/accounts "$BACKUP_DIR/certs/" && log "SSL 证书"

# Systemd 单元
cp /etc/systemd/system/novacpx*.service "$BACKUP_DIR/systemd/" 2>/dev/null || true
log "Systemd 单元"

# Cron
cp /etc/cron.d/novacpx "$BACKUP_DIR/cron/" 2>/dev/null || true
log "Cron 任务"

# 日志
[[ -d /var/log/novacpx ]] && cp -a /var/log/novacpx "$BACKUP_DIR/logs/" && log "日志"

# DNS 区域
[[ -d /var/cache/bind ]] && cp -a /var/cache/bind "$BACKUP_DIR/configs/bind-cache" 2>/dev/null || true
[[ -f /etc/bind/named.conf.local ]] && cp /etc/bind/named.conf.local "$BACKUP_DIR/configs/" 2>/dev/null || true

# 邮件配置
[[ -d /etc/postfix ]] && cp -a /etc/postfix "$BACKUP_DIR/configs/postfix" 2>/dev/null || true
[[ -d /etc/dovecot ]] && cp -a /etc/dovecot "$BACKUP_DIR/configs/dovecot" 2>/dev/null || true

# 压缩备份——如果 tar 失败则中止，而不是静默删除未备份的文件
tar -czf "$BACKUP_ARCHIVE" -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)" || {
    echo -e "${RED}[✗]${NC} 备份归档创建失败。卸载已中止以保护你的数据。"
    echo "    暂存目录保留在：$BACKUP_DIR"
    exit 1
}
rm -rf "$BACKUP_DIR"
BACKUP_SIZE=$(du -sh "$BACKUP_ARCHIVE" | cut -f1)
log "备份归档：$BACKUP_ARCHIVE ($BACKUP_SIZE)"

echo ""
echo -e "${BOLD}备份完成。${NC}"
echo ""
echo "要在继续之前下载备份："
echo "  scp root@$(hostname -I | awk '{print $1}'):${BACKUP_ARCHIVE} ./"
echo ""
echo "或临时提供服务："
echo "  cd $(dirname $BACKUP_ARCHIVE) && python3 -m http.server 9999 &"
echo "  # 下载：http://$(hostname -I | awk '{print $1}'):9999/$(basename $BACKUP_ARCHIVE)"
echo ""

if [[ "$SKIP_CONFIRM" != "--yes" ]]; then
    read -r -p "继续卸载？此操作无法撤销。[yes/no]：" CONFIRM
    [[ "$CONFIRM" != "yes" ]] && { warn "已中止。"; exit 0; }
fi

# ── 步骤 2：停止所有 NovaCPX 服务 ────────────────────────────────────
step "停止服务"
systemctl stop novacpx-web 2>/dev/null && log "已停止 novacpx-web" || true
systemctl disable novacpx-web 2>/dev/null || true

# ── 步骤 3：移除托管账户 ──────────────────────────────────────────────
step "移除托管账户"
if [[ -f "$DB_PATH" ]]; then
    while IFS='|' read -r username home_dir; do
        [[ -z "$username" ]] && continue
        # 移除 Linux 用户和主目录
        id "$username" &>/dev/null && userdel -r "$username" 2>/dev/null && log "已移除用户：$username" || true
        # 移除 PHP-FPM 池
        rm -f "/etc/php/8.3/fpm/pool.d/${username}.conf" 2>/dev/null || true
        # 移除 nginx 虚拟主机
        rm -f "/etc/nginx/sites-available/novacpx-${username}.conf" \
              "/etc/nginx/sites-enabled/novacpx-${username}.conf" 2>/dev/null || true
    done < <(sqlite3 "$DB_PATH" "SELECT username, home_dir FROM accounts;" 2>/dev/null)
fi

# 同时清理任何剩余的 novacpx 虚拟主机
rm -f /etc/nginx/sites-available/novacpx-*.conf \
       /etc/nginx/sites-enabled/novacpx-*.conf 2>/dev/null || true
log "Nginx 虚拟主机已移除"

# 如果存在则移除 webacct
id webacct &>/dev/null && userdel -r webacct 2>/dev/null || true

# ── 步骤 4：移除 PHP-FPM 池 ──────────────────────────────────────────
step "移除 PHP-FPM 池"
for f in /etc/php/*/fpm/pool.d/novacpx-*.conf /etc/php/*/fpm/pool.d/webacct.conf; do
    [[ -f "$f" ]] && rm -f "$f" && log "已移除池：$f" || true
done
systemctl reload php8.3-fpm 2>/dev/null || true

# ── 步骤 5：移除 systemd 单元 ────────────────────────────────────────
step "移除 systemd 单元"
for svc in novacpx-web; do
    systemctl stop "$svc" 2>/dev/null; systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/${svc}.service"
    rm -rf "/etc/systemd/system/${svc}.service.d"
    log "已移除：$svc"
done
systemctl daemon-reload

# ── 步骤 6：移除 sudoers ─────────────────────────────────────────────
step "移除 sudoers 规则"
for f in novacpx novacpx-firewall novacpx-panel novacpx-services; do
    rm -f "/etc/sudoers.d/$f" && log "已移除 sudoers：$f" || true
done
# 移除添加到主 sudoers 的任何 novacpx 条目
sed -i '/Defaults:www-data !requiretty/d' /etc/sudoers 2>/dev/null || true

# ── 步骤 7：移除 cron 任务 ───────────────────────────────────────────
step "移除 cron 任务"
rm -f /etc/cron.d/novacpx && log "已移除 /etc/cron.d/novacpx" || true
# 移除 NovaCPX 添加的 root crontab 条目
crontab -l 2>/dev/null | grep -v "novacpx" | crontab - 2>/dev/null || true
log "Root crontab 已清理"

# ── 步骤 8：移除 nginx 默认覆盖 ──────────────────────────────────────
step "恢复 nginx 默认配置"
# 恢复默认站点（移除我们添加的 444 返回）
cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.htm;
    server_name _;
    location / { try_files $uri $uri/ =404; }
}
NGINX
nginx -t 2>/dev/null && systemctl reload nginx && log "nginx 已恢复"

# ── 步骤 9：移除 NovaCPX 添加的邮件/DNS 配置 ─────────────────────────
step "移除邮件/DNS 配置"
# 移除托管域名的 opendkim 签名条目
[[ -f /etc/opendkim/signing.table ]] && > /etc/opendkim/signing.table || true
[[ -f /etc/opendkim/key.table ]]     && > /etc/opendkim/key.table     || true
rm -rf /etc/opendkim/keys/* 2>/dev/null || true
systemctl reload opendkim 2>/dev/null || true
log "DKIM 配置已清除"

# 移除托管域名的 DNS 区域
rm -f /etc/bind/zones/db.novacpx.* 2>/dev/null || true
# 从 named.conf.local 中移除 novacpx 条目
[[ -f /etc/bind/named.conf.local ]] && \
    sed -i '/novacpx/d' /etc/bind/named.conf.local 2>/dev/null || true
systemctl reload named 2>/dev/null || true
log "DNS 区域已清除"

# Postfix 虚拟邮箱映射
[[ -f /etc/postfix/novacpx_virtual_domains ]] && {
    rm -f /etc/postfix/novacpx_virtual_domains /etc/postfix/novacpx_virtual_mailbox \
          /etc/postfix/novacpx_virtual_aliases 2>/dev/null || true
    postmap /etc/postfix/novacpx_* 2>/dev/null || true
    systemctl reload postfix 2>/dev/null || true
    log "Postfix 虚拟表已清除"
}

# ── 步骤 10：移除所有 NovaCPX 文件 ───────────────────────────────────
step "移除 NovaCPX 文件"
rm -rf /srv/novacpx          && log "已移除 /srv/novacpx"
rm -rf /opt/novacpx-src      && log "已移除 /opt/novacpx-src"
rm -rf /opt/novacpx          && log "已移除 /opt/novacpx"
rm -rf /var/lib/novacpx      && log "已移除 /var/lib/novacpx"
rm -rf /var/log/novacpx      && log "已移除 /var/log/novacpx"
rm -rf /etc/novacpx          && log "已移除 /etc/novacpx"
rm -f  /etc/nginx/htpasswd.webacct 2>/dev/null || true
rm -f  /usr/local/bin/novacpx* /usr/local/bin/novacpx-* 2>/dev/null || true
# 移除 fail2ban 过滤器
rm -f /etc/fail2ban/filter.d/novacpx-*.conf \
       /etc/fail2ban/jail.d/novacpx*.conf 2>/dev/null || true
systemctl reload fail2ban 2>/dev/null || true
log "fail2ban 过滤器已移除"

# ── 完成 ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}NovaCPX 已完全卸载。${NC}"
echo ""
echo "备份归档保留在：$BACKUP_ARCHIVE"
echo ""
echo "仍在运行的服务（未移除，NovaCPX 并不拥有这些）："
echo "  nginx, php8.3-fpm, postfix, dovecot, bind9, fail2ban"
echo "  （如果不再需要，请单独停止/移除它们）"
echo ""
