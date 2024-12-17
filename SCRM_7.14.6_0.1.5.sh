#!/bin/bash
#Installing SuiteCRM 7.14.6
#1. Function definitions
get_input() {
    read -p "$1: " value
    echo $value
}

get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

#2. User input collection
db_user=$(get_input "Enter your MariaDB username")
db_pass=$(get_input "Enter your MariaDB password")
server_ip=$(get_internal_ip)
echo "IP retrieved: $server_ip"

#3. System updates and essential packages
echo "Updating and installing essential packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install unzip wget apache2 dialog -y

#4. PHP installation and configuration
echo "Updating and installing PHP packages..."
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install php8.2 libapache2-mod-php8.2 php8.2-cli php8.2-curl php8.2-common php8.2-intl \
php8.2-gd php8.2-mbstring php8.2-mysqli php8.2-pdo php8.2-mysql php8.2-xml php8.2-zip \
php8.2-imap php8.2-ldap php8.2-curl php8.2-soap php8.2-bcmath php8.2-opcache -y

#5. Apache configuration
echo "Configuring Apache Server..."
sudo a2enmod rewrite headers
sudo systemctl restart apache2

#6. MariaDB installation and configuration
echo "Installing MariaDB..."
sudo apt install mariadb-server mariadb-client -y

#7. Database setup
echo "Configuring main database..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS CRM CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON CRM.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF

#8. SuiteCRM installation
echo "Installing and configuring SuiteCRM 7.14.6..."
cd /var/www
sudo rm -rf html
sudo mkdir html
cd html
sudo wget https://suitecrm.com/download/141/suite714/564663/suitecrm-7-14-6.zip
sudo unzip suitecrm-7-14-6.zip -d temp
sudo mv temp/SuiteCRM-7.14.6/* .
sudo rm -rf temp suitecrm-7-14-6.zip

#9. Apache VirtualHost configuration
cat << EOF | sudo tee /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ServerName $server_ip

    <Directory /var/www/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

#10. PHP configuration
sudo tee /etc/php/8.2/apache2/conf.d/suitecrm.ini << EOF
memory_limit = 256M
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
max_input_time = 300
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE & ~E_WARNING
display_errors = Off
EOF

#11. Directory permissions setup - More permissive for initial setup
echo "Setting initial permissions..."
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 775 /var/www/html

#12. Special directories creation and permissions
sudo -u www-data mkdir -p /var/www/html/cache/{images,modules,pdf,upload,xml,themes}
sudo -u www-data mkdir -p /var/www/html/custom
sudo -u www-data touch /var/www/html/config.php
sudo -u www-data touch /var/www/html/config_override.php

#13. Create main .htaccess
cat << EOF | sudo tee /var/www/html/.htaccess
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    Options +FollowSymLinks
    
    # Allow direct access to specific directories
    RewriteCond %{REQUEST_URI} ^/(cache|custom|modules|themes|upload|install)/ [OR]
    RewriteCond %{REQUEST_URI} \.(jpg|jpeg|png|gif|css|js|ico)$ [OR]
    RewriteCond %{REQUEST_URI} ^/index\.php
    RewriteRule ^ - [L]
</IfModule>

<FilesMatch "\.(jpg|jpeg|png|gif|css|js|ico)$">
    Allow from all
</FilesMatch>
EOF

#14. Set proper ownership and permissions for .htaccess
sudo chown www-data:www-data /var/www/html/.htaccess
sudo chmod 644 /var/www/html/.htaccess

#15. Apache configuration verification and restart
sudo apache2ctl configtest
sudo systemctl restart apache2

#16. Final security adjustments
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;
sudo chmod -R 775 /var/www/html/cache
sudo chmod -R 775 /var/www/html/custom
sudo chmod -R 775 /var/www/html/modules
sudo chmod -R 775 /var/www/html/upload
sudo chmod 775 /var/www/html/config.php
sudo chmod 775 /var/www/html/config_override.php

#17. Installation complete message
echo ""
echo "###################################################"
echo "Installation completed!"
echo "The script has finished. Before opening the web browser, you must run:"
echo ""
echo " sudo mysql_secure_installation "
echo ""
echo "and manually and follow the instructions as in the Github."
echo "https://github.com/motaviegas/SuiteCRM_Script/blob/main/installation%20guide"
echo ""
echo "To access the web installation page:"
echo "2. Access your SuiteCRM installation at: http://$server_ip"
echo "3. Complete the web-based setup using these database credentials:"
echo ""
echo "   Database Name: CRM"
echo "   Database User: $db_user"
echo "   Database Password: $db_pass"
echo ""
echo "If you encounter 'Forbidden error' while opening the webpage, run in your terminal:"
echo "sudo chmod -R 775 /var/www/html"
echo "sudo chown -R www-data:www-data /var/www/html"
echo ""
echo "Good luck!!!"
