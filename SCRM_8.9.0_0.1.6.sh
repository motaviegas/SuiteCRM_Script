#!/bin/bash

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

# Request user information
db_user=$(get_input "Enter your MariaDB username")
db_pass=$(get_input "Enter your MariaDB password")

# Automatically get the internal IP
server_ip=$(get_internal_ip)
if [ -z "$server_ip" ]; then
    echo "Error: Could not retrieve server IP."
    exit 1
fi
echo "IP retrieved: $server_ip"

# Update and install essential packages
echo "Updating and installing essential packages..."
sudo apt update && sudo apt upgrade -y
check_status "Failed to update and upgrade packages"
sudo apt install -y unzip wget curl git
check_status "Failed to install essential packages"

# Install PHP 8.2 and required extensions
echo "Installing PHP 8.2 and extensions..."
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install -y php8.2 libapache2-mod-php8.2 php8.2-cli php8.2-curl php8.2-common php8.2-intl php8.2-gd php8.2-mbstring php8.2-mysql php8.2-xml php8.2-zip php8.2-imap php8.2-ldap php8.2-soap php8.2-bcmath php8.2-opcache
check_status "Failed to install PHP packages"

# Install Composer
echo "Installing Composer..."
sudo apt install -y composer
check_status "Failed to install Composer"

# Install Node.js and npm (required for SuiteCRM 8.x frontend)
echo "Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs
check_status "Failed to install Node.js and npm"

# Configure Apache
echo "Configuring Apache Server..."
sudo a2enmod rewrite
check_status "Failed to enable mod_rewrite"
sudo systemctl restart apache2
check_status "Failed to restart Apache"

# Disable default Apache site
echo "Disabling default Apache site..."
sudo a2dissite 000-default.conf
check_status "Failed to disable default site"

# Disable directory listing globally
echo "Disabling directory listing globally..."
cat << EOF | sudo tee /etc/apache2/conf-available/disable-directory-listing.conf
<Directory /var/www/>
    Options -Indexes
</Directory>
EOF
sudo a2enconf disable-directory-listing
check_status "Failed to configure directory listing"

# Install and configure MariaDB
echo "Installing MariaDB..."
sudo apt install -y mariadb-server mariadb-client
check_status "Failed to install MariaDB"

# Secure MariaDB installation (run manually as it requires interaction)
echo "Please run 'sudo mysql_secure_installation' manually after the script finishes."

# Configure database
echo "Configuring main database..."
sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS CRM CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
check_status "Failed to create database CRM"
sudo mysql -u root -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
check_status "Failed to create user $db_user"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON CRM.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;"
check_status "Failed to grant privileges"

# Verify database creation
if sudo mysql -u root -e "USE CRM"; then
    echo "Database CRM created successfully."
else
    echo "Failed to create database CRM. Please check MySQL root permissions."
    exit 1
fi

# Verify user creation
if sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User='$db_user';" | grep -q "$db_user"; then
    echo "User $db_user created successfully."
else
    echo "Failed to create user $db_user. Please check MySQL root permissions."
    exit 1
fi

# Start and enable MariaDB
sudo systemctl start mariadb
sudo systemctl enable mariadb
check_status "Failed to start/enable MariaDB"

# Install SuiteCRM
echo "Installing and configuring SuiteCRM..."
cd /var/www/html
sudo rm -rf crm
sudo mkdir crm
cd /var/www/html/crm
sudo wget -O suitecrm-8.9.0.zip https://suitecrm.com/download/166/suite89/565428/suitecrm-8-9-0.zip
check_status "Failed to download SuiteCRM"

# Verify downloaded file
if [ ! -f suitecrm-8.9.0.zip ]; then
    echo "Error: SuiteCRM zip file not found."
    exit 1
fi

sudo unzip suitecrm-8.9.0.zip
check_status "Failed to unzip SuiteCRM"
sudo rm suitecrm-8.9.0.zip

# Install Composer dependencies
echo "Running Composer install..."
sudo composer install --no-interaction
check_status "Failed to run composer install"

# Install Node.js dependencies and build frontend
echo "Running npm install and build..."
sudo npm install
check_status "Failed to run npm install"
sudo npm run build
check_status "Failed to build frontend assets"

# Set permissions as per SuiteCRM 8.x requirements
echo "Setting SuiteCRM permissions..."
sudo chown -R www-data:www-data /var/www/html/crm
sudo chmod -R 755 /var/www/html/crm
sudo chmod -R 775 /var/www/html/crm/{cache,custom,modules,public,upload}
sudo chmod -R 775 /var/www/html/crm/config*
sudo chmod +x /var/www/html/crm/bin/console

# Configure VirtualHost
echo "Configuring VirtualHost..."
cat << EOF | sudo tee /etc/apache2/sites-available/crm.conf
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
sudo a2ensite crm.conf
check_status "Failed to enable crm.conf"
sudo systemctl reload apache2
check_status "Failed to reload Apache"

# Configure php.ini
echo "Setting php.ini..."
sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/;date.timezone =.*/date.timezone = UTC/' /etc/php/8.2/apache2/php.ini
sudo systemctl restart apache2
check_status "Failed to restart Apache after php.ini changes"

echo "SuiteCRM installation completed."
echo "Please run 'sudo mysql_secure_installation' manually and follow the instructions."
echo "Complete the installation via the web browser at: http://$server_ip"
echo "Use the database credentials you provided (username: $db_user, database: CRM)."
echo "Enjoy and good luck!"
