#!/bin/bash

# Função para solicitar entrada do usuário
get_input() {
    read -p "$1: " value
    echo $value
}

# Função para solicitar entrada do usuário
get_input() {
    read -p "$1: " value
    echo $value
}

# Obter o IP interno automaticamente
get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

# Solicitar informações do usuário
db_user=$(get_input "Input your MariaDB user")
db_pass=$(get_input "Input your MariaDB PASSWORD")

# Obter o IP interno automaticamente
server_ip=$(get_internal_ip)
echo "IP interno detectado: $server_ip"

# Atualizar e instalar pacotes
echo "Atualizando e instalando pacotes..."
sudo add-apt-repository ppa:ondrej/php -y && sudo apt update && sudo apt upgrade -y

sudo apt update && sudo apt install php8.2 libapache2-mod-php8.2 php8.2-cli php8.2-curl php8.2-common php8.2-intl php8.2-gd php8.2-mbstring php8.2-mysqli php8.2-pdo php8.2-mysql php8.2-xml php8.2-zip php8.2-imap php8.2-ldap -y php8.2-curl php8.2-soap php8.2-bcmath

# Configurar Apache
echo "Configurando Apache..."
sudo a2enmod rewrite
sudo systemctl restart apache2

# Instalar e configurar MariaDB
echo "Instalando e configurando MariaDB..."
sudo apt install mariadb-server mariadb-client -y

# Nota: mysql_secure_installation requer interação manual
echo "Execute 'sudo mysql_secure_installation' manual after the script finishes."

# Configurar banco de dados
echo "Configurando banco de dados..."
sudo mysql -e "CREATE DATABASE PMVC;
CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON PMVC.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;"

# Iniciar e habilitar MariaDB
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Instalar SSH e nano
echo "Instalando SSH e nano..."
sudo apt install ssh

# Configurar SuiteCRM
echo "Configurando SuiteCRM..."
cd /var/www/html
sudo mkdir crm
cd /var/www/html/crm
sudo wget https://suitecrm.com/download/147/suite86/564058/suitecrm-8-6-1.zip 
sudo unzip suitecrm-8-6-1.zip
sudo chown -R www-data:www-data /var/www/html/crm
sudo chmod -R 755 /var/www/html/crm

# Configurar VirtualHost
echo "Configurando VirtualHost..."
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

# Configurar php.ini
echo "Configurando php.ini..."
sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 50M/' /etc/php/8.2/apache2/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.2/apache2/php.ini

sudo systemctl restart apache2

# Ajustar permissões
echo "Ajustando permissões..."
sudo find /var/www/html/crm -type d -not -perm 2755 -exec chmod 2755 {} \;
sudo find /var/www/html/crm -type f -not -perm 0644 -exec chmod 0644 {} \;
sudo find /var/www/html/crm ! -user www-data -exec chown www-data:www-data {} \;
sudo chmod +x /var/www/html/crm/bin/console

echo "Script concluído. Lembre-se de executar 'sudo mysql_secure_installation' manualmente."
echo "Você pode acessar o SuiteCRM abrindo um navegador e acessando http://$server_ip"