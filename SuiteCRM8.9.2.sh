#!/usr/bin/env bash

# SuiteCRM 8.9.2 Production Installer for Ubuntu 24.04 LTS
# Version: 0.3.9 – added cron package + silent install tolerance

set -euo pipefail

SUITE_VERSION="8.9.2"
ZIP_NAME="SuiteCRM-${SUITE_VERSION}.zip"
DOWNLOAD_URL="https://github.com/suitecrm/SuiteCRM-Core/releases/download/v${SUITE_VERSION}/${ZIP_NAME}"
DEFAULT_INSTALL_DIR="/var/www/html/crm"
DB_NAME="CRM"

PHP_VER_TARGET="8.3"
MIN_PHP="8.1"
MAX_PHP="8.3"

MIN_RAM_GB=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_step()    { echo -e "${BLUE}==>${NC} $1"; }
echo_success() { echo -e "${GREEN}✔ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
echo_error()   { echo -e "${RED}✖ $1${NC}"; exit 1; }

confirm() {
    read -p "$1 [Y/n] " -n 1 -r choice </dev/tty
    echo
    [[ "$choice" =~ ^[Yy]$ ]] || [[ -z "$choice" ]] && return 0 || return 1
}

get_version() {
    $1 2>&1 | grep -oP "$2" || echo "not found"
}

clear
echo -e "${BLUE}SuiteCRM ${SUITE_VERSION} Installer – Ubuntu 24.04${NC}"
echo

[[ $EUID -ne 0 ]] && echo_error "Run with sudo."

echo_step "Resources check"
ram=$(free -g | awk '/^Mem:/ {print $7}')
[[ "$ram" -lt $MIN_RAM_GB ]] && echo_warning "Low RAM (${ram} GB)"

echo_step "Database choice"
echo "1) MariaDB (recommended)"
echo "2) MySQL"
read -p "Choice [1]: " db_choice
db_choice=${db_choice:-1}

if [[ $db_choice == 1 ]]; then
    DB_ENGINE="mariadb"
    DB_PACKAGE="mariadb-server"
    DB_CLIENT="mariadb"
else
    DB_ENGINE="mysql"
    DB_PACKAGE="mysql-server"
    DB_CLIENT="mysql"
fi

echo_step "Installed versions"
apache_ver=$(get_version "apache2 -v" 'Apache/([\d.]+)')
php_ver=$(php -v 2>&1 | grep -oP '\d+\.\d+' | head -1 || echo "")
db_ver=$(${DB_CLIENT} --version 2>&1 | grep -oP 'Ver\s+\K[\d.]+' || echo "not found")

echo "  Apache:  ${apache_ver}"
echo "  PHP:     ${php_ver}"
echo "  ${DB_ENGINE^}: ${db_ver}"

if [[ -n "$php_ver" ]]; then
    if (( $(echo "$php_ver < $MIN_PHP" | bc -l) )); then
        echo_warning "PHP ${php_ver} too old"
        confirm "Purge & install PHP ${PHP_VER_TARGET}?" && apt purge -y php* >/dev/null 2>&1 || true
    elif (( $(echo "$php_ver > $MAX_PHP" | bc -l) )); then
        echo_error "PHP ${php_ver} newer than supported max (${MAX_PHP}). Uninstall first."
    fi
fi

echo_step "Configuration"

read -p "Install path [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
INSTALL_DIR="${INSTALL_DIR%/}"

read -p "Server IP/domain [$(hostname -I | awk '{print $1}')] : " server_host
server_host=${server_host:-$(hostname -I | awk '{print $1}')}

read -p "Admin username [admin]: " admin_user
admin_user=${admin_user:-admin}

read -s -p "Admin password (empty=auto): " admin_pass; echo
[[ -z "$admin_pass" ]] && admin_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')

read -s -p "${DB_ENGINE^} root password (empty=auto): " db_root_pass; echo
[[ -z "$db_root_pass" ]] && db_root_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')

read -p "DB user [suitecrm]: " db_user
db_user=${db_user:-suitecrm}

read -s -p "DB user password (empty=auto): " db_pass; echo
[[ -z "$db_pass" ]] && db_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')

confirm "Proceed?" || exit 0

echo_step "Packages"
apt update -y && apt upgrade -y
apt install -y apache2 "${DB_PACKAGE}" curl wget unzip git openssl bc cron software-properties-common

add-apt-repository ppa:ondrej/php -y || true
apt update -y
apt install -y php${PHP_VER_TARGET} libapache2-mod-php${PHP_VER_TARGET} \
    php${PHP_VER_TARGET}-{mysql,curl,zip,gd,mbstring,xml,intl,bcmath,soap,ldap,apcu,opcache}

a2enmod rewrite headers expires

echo_step "Database setup"
systemctl enable --now "${DB_ENGINE}"

root_pass_to_use=""
if "${DB_CLIENT}" -u root -e "SELECT 1" >/dev/null 2>&1; then
    root_pass_to_use="${db_root_pass}"
    "${DB_CLIENT}" -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass_to_use}';
FLUSH PRIVILEGES;
EOF
else
    echo_warning "Root password already set"
    read -s -p "Current root password (empty = keep current): " current_root; echo

    if [[ -n "$current_root" ]]; then
        if ! "${DB_CLIENT}" -u root -p"${current_root}" -e "SELECT 1" >/dev/null 2>&1; then
            echo_error "Wrong current root password"
        fi
        if confirm "Change root password?"; then
            root_pass_to_use="${db_root_pass}"
            "${DB_CLIENT}" -u root -p"${current_root}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass_to_use}';
FLUSH PRIVILEGES;
EOF
        else
            root_pass_to_use="${current_root}"
        fi
    else
        root_pass_to_use=""
    fi
fi

if [[ -n "$root_pass_to_use" ]]; then
    "${DB_CLIENT}" -u root -p"${root_pass_to_use}" <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
else
    "${DB_CLIENT}" -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
fi

echo_success "Database ready"

echo_step "SuiteCRM download & direct extract"

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
rm -f "${ZIP_NAME}" 2>/dev/null || true

wget --show-progress "${DOWNLOAD_URL}" -O "${ZIP_NAME}"

unzip -q -o "${ZIP_NAME}"
rm -f "${ZIP_NAME}"

echo_step "Permissions"
chown -R www-data:www-data "${INSTALL_DIR}"
find "${INSTALL_DIR}" -type d -exec chmod 2755 {} \+ 2>/dev/null || true
find "${INSTALL_DIR}" -type f -exec chmod 0644 {} \+ 2>/dev/null || true
chmod -R 775 "${INSTALL_DIR}"/public/legacy/{cache,custom,modules,upload} 2>/dev/null || true
chmod -R 775 "${INSTALL_DIR}"/config* 2>/dev/null || true
chmod +x "${INSTALL_DIR}/bin/console" 2>/dev/null || true

echo_step "CLI install"
cd "${INSTALL_DIR}"
su www-data -s /bin/bash -c "./bin/console suitecrm:app:install \
    -u \"${admin_user}\" -p \"${admin_pass}\" \
    -U \"${db_user}\" -P \"${db_pass}\" \
    -H \"127.0.0.1\" -N \"${DB_NAME}\" \
    -S \"http://${server_host}\" -d \"no\" --sys_check_option \"true\"" || echo_warning "CLI install finished with warnings (normal in some cases)"

echo_step "Apache + PHP + cron"
cat <<EOF > /etc/apache2/sites-available/crm.conf
<VirtualHost *:80>
    DocumentRoot ${INSTALL_DIR}/public
    ServerName ${server_host}
    <Directory ${INSTALL_DIR}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/crm_error.log
    CustomLog \${APACHE_LOG_DIR}/crm_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf 2>/dev/null || true
a2ensite crm.conf
systemctl reload apache2

sed -i "s/memory_limit =.*/memory_limit = 512M/" /etc/php/${PHP_VER_TARGET}/apache2/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 50M/" /etc/php/${PHP_VER_TARGET}/apache2/php.ini
sed -i "s/post_max_size =.*/post_max_size = 50M/" /etc/php/${PHP_VER_TARGET}/apache2/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 300/" /etc/php/${PHP_VER_TARGET}/apache2/php.ini
sed -i "s|;date.timezone =.*|date.timezone = UTC|" /etc/php/${PHP_VER_TARGET}/apache2/php.ini

cat <<EOF >> /etc/php/${PHP_VER_TARGET}/apache2/php.ini

[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
EOF

systemctl restart apache2

(crontab -l 2>/dev/null; echo "* * * * * www-data php ${INSTALL_DIR}/bin/console scheduler") | crontab -

clear
echo -e "${GREEN}SuiteCRM ${SUITE_VERSION} installed${NC}"
echo
echo "Path:           ${INSTALL_DIR}"
echo "URL:            http://${server_host}"
echo "Admin:          ${admin_user} / ${admin_pass}"
echo "Database:       ${DB_ENGINE} / ${DB_NAME}"
echo "DB user:        ${db_user} / ${db_pass}"
echo "DB root pass:   ${root_pass_to_use:-"(unchanged - use existing)"}"
echo
echo "Next:"
echo "  Open http://${server_host} in browser and log in"
echo "  sudo mysql_secure_installation   (recommended)"
echo "  Optional SSL: sudo apt install certbot python3-certbot-apache && sudo certbot --apache"
echo