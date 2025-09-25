#!/bin/bash

# Script to install SuiteCRM 8.9.0 for production only

set -e

# Function to request user input
get_input() {
    read -p "$1: " value
    echo "$value"
}

# Function to automatically get the internal IP
get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

# Function to check if a command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Check if running as root or with sudo
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

# Set installation mode to production
install_mode="prod"
echo "Installation mode: production"

# Request user information
db_user=$(get_input "Enter your MariaDB username")
db_pass=$(get_input "Enter your MariaDB password")
admin_username=$(get_input "Enter SuiteCRM admin username (e.g., admin)")
admin_password=$(get_input "Enter SuiteCRM admin password")

# Automatically get the internal IP
server_ip=$(get_internal_ip)
if [ -z "$server_ip" ]; then
    echo "Error: Could not retrieve server IP."
    exit 1
fi
echo "IP retrieved: $server_ip"

# Update and install essential packages
echo "Updating and installing essential packages..."
apt update && apt upgrade -y
check_status "Failed to update and upgrade packages"
apt install -y unzip wget curl git
check_status "Failed to install essential packages"

# Install PHP 8.3 and required extensions
echo "Installing PHP 8.3 and extensions..."
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.3 libapache2-mod-php8.3 php8.3-cli php8.3-curl php8.3-common php8.3-intl php8.3-gd php8.3-mbstring php8.3-mysql php8.3-xml php8.3-zip php8.3-imap php8.3-ldap php8.3-soap php8.3-bcmath php8.3-opcache  php8.3-apcu 
check_status "Failed to install PHP packages"

# Install Composer if not present
echo "Installing Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    check_status "Failed to install Composer"
fi

# Configure Apache
echo "Configuring Apache Server..."
a2enmod rewrite
check_status "Failed to enable mod_rewrite"
systemctl restart apache2
check_status "Failed to restart Apache"

# Disable default Apache site
echo "Disabling default Apache site..."
a2dissite 000-default.conf
check_status "Failed to disable default site"

# Disable directory listing globally
echo "Disabling directory listing globally..."
cat << EOF | tee /etc/apache2/conf-available/disable-directory-listing.conf
<Directory /var/www/>
    Options -Indexes
</Directory>
EOF
a2enconf disable-directory-listing
check_status "Failed to configure directory listing"

# Install and configure MariaDB
echo "Installing MariaDB..."
apt install -y mariadb-server mariadb-client
check_status "Failed to install MariaDB"

# Secure MariaDB installation (run manually as it requires interaction)
echo "Please run 'sudo mysql_secure_installation' manually after the script finishes. If you have a MariaDB root password set, use it there."

# Configure database
echo "Configuring main database..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS CRM CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
check_status "Failed to create database CRM"
mysql -u root -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
check_status "Failed to create user $db_user"
mysql -u root -e "GRANT ALL PRIVILEGES ON CRM.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;"
check_status "Failed to grant privileges"

# Verify database creation
if mysql -u root -e "USE CRM"; then
    echo "Database CRM created successfully."
else
    echo "Failed to create database CRM. Please check MySQL root permissions."
    exit 1
fi

# Verify user creation
if mysql -u root -e "SELECT User FROM mysql.user WHERE User='$db_user';" | grep -q "$db_user"; then
    echo "User $db_user created successfully."
else
    echo "Failed to create user $db_user. Please check MySQL root permissions."
    exit 1
fi

# Start and enable MariaDB
systemctl start mariadb
systemctl enable mariadb
check_status "Failed to start/enable MariaDB"

# Install SuiteCRM
echo "Installing and configuring SuiteCRM..."
cd /var/www/html
rm -rf crm
mkdir crm
chown -R www-data:www-data crm
chmod -R 775 crm
cd /var/www/html/crm
wget -O suitecrm-8.9.0.zip https://suitecrm.com/download/166/suite89/565428/suitecrm-8-9-0.zip
check_status "Failed to download SuiteCRM"

# Verify downloaded file
if [ ! -f suitecrm-8.9.0.zip ]; then
    echo "Error: SuiteCRM zip file not found."
    exit 1
fi

# Unzip SuiteCRM and handle subdirectory
echo "Unzipping SuiteCRM..."
unzip suitecrm-8.9.0.zip
check_status "Failed to unzip SuiteCRM"

# Check if SuiteCRM extracted into a subdirectory
if [ -d "SuiteCRM-8.9.0" ]; then
    echo "SuiteCRM extracted into subdirectory 'SuiteCRM-8.9.0'. Moving contents..."
    mv SuiteCRM-8.9.0/* .
    mv SuiteCRM-8.9.0/.* . 2>/dev/null || true
    rmdir SuiteCRM-8.9.0
    check_status "Failed to move SuiteCRM files from subdirectory"
fi

rm suitecrm-8.9.0.zip

# Verify key SuiteCRM files
echo "Verifying SuiteCRM directory structure..."
if [ ! -d "public" ]; then
    echo "Error: SuiteCRM directory structure is incomplete. Missing public directory."
    exit 1
fi

# Create missing directories if they don't exist
echo "Creating missing directories (if any)..."
mkdir -p /var/www/html/crm/{cache,custom,modules,public,upload}

# Set permissions
echo "Setting SuiteCRM permissions..."
chown -R www-data:www-data /var/www/html/crm
find /var/www/html/crm -type d -not -perm 2755 -exec chmod 2755 {} \;
find /var/www/html/crm -type f -not -perm 0644 -exec chmod 0644 {} \;
for dir in cache custom modules public upload; do
    if [ -d "/var/www/html/crm/$dir" ]; then
        chmod -R 775 "/var/www/html/crm/$dir"
    else
        echo "Warning: Directory /var/www/html/crm/$dir does not exist, but was created earlier."
    fi
done
if [ -d "/var/www/html/crm/config" ] || [ -d "/var/www/html/crm/config_override" ]; then
    chmod -R 775 /var/www/html/crm/config*
else
    echo "Warning: Config directory not found, creating it..."
    mkdir -p /var/www/html/crm/config
    chmod -R 775 /var/www/html/crm/config
fi
if [ -f "/var/www/html/crm/bin/console" ]; then
    chmod +x /var/www/html/crm/bin/console
else
    echo "Warning: bin/console not found, skipping chmod."
fi

# Run CLI installer for production
echo "Running CLI installer..."
cd /var/www/html/crm
su www-data -s /bin/bash -c "./bin/console suitecrm:app:install -u \"$admin_username\" -p \"$admin_password\" -U \"$db_user\" -P \"$db_pass\" -H \"127.0.0.1\" -N \"CRM\" -S \"http://$server_ip\" -d \"no\" --sys_check_option \"true\""
check_status "Failed to run CLI installer"

# Re-set permissions after installation
echo "Re-setting permissions after installation..."
chown -R www-data:www-data /var/www/html/crm
find /var/www/html/crm -type d -not -perm 2755 -exec chmod 2755 {} \;
find /var/www/html/crm -type f -not -perm 0644 -exec chmod 0644 {} \;
for dir in cache custom modules public upload; do
    chmod -R 775 "/var/www/html/crm/$dir"
done
chmod -R 775 /var/www/html/crm/config*
if [ -f "/var/www/html/crm/bin/console" ]; then
    chmod +x /var/www/html/crm/bin/console
fi

# Configure VirtualHost
echo "Configuring VirtualHost..."
cat << EOF | tee /etc/apache2/sites-available/crm.conf
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot /var/www/html/crm/public
    ServerName $server_ip
    <Directory /var/www/html/crm/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/crm_error.log
    CustomLog \${APACHE_LOG_DIR}/crm_access.log combined
</VirtualHost>
EOF
a2ensite crm.conf
check_status "Failed to enable crm.conf"
systemctl reload apache2
check_status "Failed to reload Apache"

# Configure php.ini
echo "Setting php.ini..."
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.3/apache2/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/8.3/apache2/php.ini
sed -i 's/post_max_size = .*/post_max_size = 50M/' /etc/php/8.3/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.3/apache2/php.ini
sed -i 's/;date.timezone =.*/date.timezone = UTC/' /etc/php/8.3/apache2/php.ini

# Configure OPcache for performance
echo "Configuring OPcache..."
cat << EOF >> /etc/php/8.3/apache2/php.ini
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
EOF

systemctl restart apache2
check_status "Failed to restart Apache after php.ini changes"

echo "SuiteCRM 8.9.0 production installation completed."
echo "Please run 'sudo mysql_secure_installation' manually and follow the instructions."
echo "Access your SuiteCRM instance at: http://$server_ip"
echo "Login with admin username: $admin_username"
echo "Enjoy and good luck!"
