# Function to request user input
get_input() {
    read -p "$1: " value
    echo $value
}

# Function to automatically get the internal IP
get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

# Request user information
db_user=$(get_input "Enter your MariaDB username")
db_pass=$(get_input "Enter your MariaDB password")

# Automatically get the internal IP
server_ip=$(get_internal_ip)
echo "IP retrieved: $server_ip"

# Update and install essential packages
echo "Updating and installing essential packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install unzip wget -y

# Update and install PHP packages
echo "Updating and installing PHP packages..."
sudo add-apt-repository ppa:ondrej/php -y && sudo apt update && sudo apt upgrade -y
sudo apt update && sudo apt install php8.2 libapache2-mod-php8.2 php8.2-cli php8.2-curl php8.2-common php8.2-intl php8.2-gd php8.2-mbstring php8.2-mysqli php8.2-pdo php8.2-mysql php8.2-xml php8.2-zip php8.2-imap php8.2-ldap -y php8.2-curl php8.2-soap php8.2-bcmath

# Configure Apache
echo "Configuring Apache Server..."
sudo a2enmod rewrite
sudo systemctl restart apache2

# Disable directory listing globally
echo "Disabling directory listing globally..."
cat << EOF | sudo tee /etc/apache2/conf-available/disable-directory-listing.conf
<Directory /var/www/>
    Options -Indexes
</Directory>
EOF
sudo a2enconf disable-directory-listing

# Install and configure MariaDB
echo "Installing MariaDB..."
sudo apt install mariadb-server mariadb-client -y

# Note: mysql_secure_installation requires manual interaction
echo "Execute 'sudo mysql_secure_installation' manually after the script finishes."

# Configure database
echo "Configuring main database..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS CRM CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON CRM.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF

# Verificar se o banco de dados foi criado
if sudo mysql -u root -e "USE CRM"; then
    echo "Database CRM created successfully."
else
    echo "Failed to create database CRM. Please check MySQL root permissions."
    exit 1
fi

# Verificar se o usuário foi criado
if sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User='$db_user';" | grep -q "$db_user"; then
    echo "User $db_user created successfully."
else
    echo "Failed to create user $db_user. Please check MySQL root permissions."
    exit 1
fi

# Start and enable MariaDB
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Configure SuiteCRM
echo "Installing and configuring SuiteCRM..."
cd /var/www/html
sudo mkdir crm
cd /var/www/html/crm
sudo wget https://suitecrm.com/download/148/suite87/564667/suitecrm-8-7-1.zip
#!/bin/bash 
sudo unzip suitecrm-8-7-1.zip
sudo chown -R www-data:www-data /var/www/html/crm
sudo chmod -R 755 /var/www/html/crm

# Configure VirtualHost
echo "Configuring VirtualHost..."
cat << EOF | sudo tee /etc/apache2/sites-available/crm.conf
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot /var/www/html/crm/public
    ServerName $server_ip
    <Directory /var/www/html/crm/public>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
sudo a2ensite crm.conf
sudo systemctl reload apache2

# Configure php.ini
echo "Setting php.ini..."
sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.2/apache2/php.ini
sudo systemctl restart apache2

# Adjust permissions
echo "Adjusting permissions..."
sudo find /var/www/html/crm -type d -not -perm 2755 -exec chmod 2755 {} \;
sudo find /var/www/html/crm -type f -not -perm 0644 -exec chmod 0644 {} \;
sudo find /var/www/html/crm ! -user www-data -exec chown www-data:www-data {} \;
sudo chmod +x /var/www/html/crm/bin/console

echo "The script has finished. Before opening the web browser, you must run 'sudo mysql_secure_installation' manually and follow the instructions."
echo "You can now complete the installation of your CRM from the web browser using this address: http://$server_ip"
echo "Remember all the usernames and passwords you previously defined. Enjoy and good luck!"
