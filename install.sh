#/bin/bash

# APACHE2, MARIADB E PHP7

cd /tmp

apt update \
&& apt upgrade -y \
&& apt install apache2 apache2-utils mariadb-server mariadb-client curl\
  libapache2-mod-php php php-mysql php-cli php-pear php-gmp php-gd php-bcmath\
  php-mbstring php-curl php-xml php-zip php-imap php-intl php-ldap php-imagick wget;

a2enmod rewrite;

# Removendo assinatura do servidor

sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf \
&& sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf;

systemctl restart apache2;

# phpMyAdmin

wget https://files.phpmyadmin.net/phpMyAdmin/5.2.0/phpMyAdmin-5.2.0-all-languages.tar.gz;
tar -vxzf phpMyAdmin-5.2.0-all-languages.tar.gz -C /usr/share/
mv /usr/share/phpMyAdmin-5.2.0-all-languages /usr/share/phpmyadmin;
mkdir /etc/phpmyadmin;
touch /etc/phpmyadmin/htpasswd.setup;
mkdir -p /var/lib/phpmyadmin/tmp;
chown -R www-data:www-data /var/lib/phpmyadmin;

a2enconf phpmyadmin;
systemctl restart apache2;
