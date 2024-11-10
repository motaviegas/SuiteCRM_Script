#!/bin/bash

# Function to request user input
get_input() {
    read -p "$1: " value
    echo $value
}

# Function to print a box with text
print_box() {
    local message="$1"
    local width=80
    local padding=2
    local line=""
    
    # Create the top/bottom border line
    printf "\n"
    printf "╔"
    for ((i=0; i<width-2; i++)); do printf "═"; done
    printf "╗\n"
    
    # Split message into words and create lines that fit within the box
    local current_line=""
    for word in $message; do
        if [ ${#current_line} -eq 0 ]; then
            current_line="$word"
        elif [ $((${#current_line} + ${#word} + 1)) -lt $((width - 2*padding)) ]; then
            current_line="$current_line $word"
        else
            printf "║ %-$((width-4))s ║\n" "$current_line"
            current_line="$word"
        fi
    done
    # Print the last line if any
    if [ ${#current_line} -gt 0 ]; then
        printf "║ %-$((width-4))s ║\n" "$current_line"
    fi
    
    # Create the bottom border
    printf "╚"
    for ((i=0; i<width-2; i++)); do printf "═"; done
    printf "╝\n\n"
}

# Function to automatically get the internal IP
get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

# Store all user inputs for final summary
declare -A user_inputs

# Clear screen and show welcome message
clear
print_box "Welcome to SuiteCRM Installation Script"

# Request user information
echo "Please provide the following information:"
echo "----------------------------------------"
db_user=$(get_input "Enter your MariaDB username")
user_inputs["Database Username"]=$db_user

db_pass=$(get_input "Enter your MariaDB password")
user_inputs["Database Password"]=$db_pass

db_name=$(get_input "Enter your database name (default: CRM)")
db_name=${db_name:-CRM}  # Use CRM as default if empty
user_inputs["Database Name"]=$db_name

# Automatically get the internal IP
server_ip=$(get_internal_ip)
user_inputs["Server IP"]=$server_ip
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

# Configure database
echo "Configuring main database..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF

# Verify if database was created
if sudo mysql -u root -e "USE $db_name"; then
    echo "Database $db_name created successfully."
else
    echo "Failed to create database $db_name. Please check MySQL root permissions."
    exit 1
fi

# Verify if user was created
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

# Clear screen for final instructions
clear

# Show MySQL secure installation instructions
print_box "MySQL Secure Installation Instructions:

1. Just press enter (there is no root password)
2. Switch to unix_socket authentication [Y/n] Y
3. Change the root password? [Y/n] y
4. Put your DB root password and take note of it!!!
5. Remove anonymous users? [Y/n] Y
6. Disallow root login remotely? [Y/n] Y
7. Remove test database and access to it? [Y/n] Y
8. Reload privilege tables now? [Y/n] Y"

# Run mysql_secure_installation
sudo mysql_secure_installation

# Clear screen for final summary
clear

# Create and show installation summary
summary="Installation Summary\n\n"
for key in "${!user_inputs[@]}"; do
    summary+="$key: ${user_inputs[$key]}\n"
done

print_box "$summary"

# Show final instructions
print_box "Installation Complete!

You can now access your CRM by opening a web browser and navigating to:
http://$server_ip

Make sure to keep these credentials safe for future reference."
