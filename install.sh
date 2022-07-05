#/bin/bash

PATH=${PWD}

tar -vxzf $PATH/config.tar.gz -C $PATH/

# APACHE2, MARIADB E PHP7

cd /tmp

apt update \
&& apt upgrade -y \
&& apt install apache2 apache2-utils mariadb-server mariadb-client curl\
  libapache2-mod-php php php-mysql php-cli php-pear php-gmp php-gd php-bcmath\
  php-mbstring php-curl php-xml php-zip php-imap php-intl php-ldap php-sqlite3 php-imagick wget;

a2enmod rewrite;

mv /etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf.orig
cp $PATH/etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf

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

mkdir -p /etc/apache2/conf-available
cp $PATH/etc/apache2/conf-available/phpmyadmin.conf /etc/apache2/conf-available/phpmyadmin.conf

a2enconf phpmyadmin;
systemctl restart apache2;

mariadb < $PATH/usr/share/phpmyadmin/sql/create_database.sql
mariadb phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql

cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
cat $PATH/usr/share/phpmyadmin/config.hazevedo.inc.php >> /usr/share/phpmyadmin/config.inc.php

# POSTFIX / DOVECOTE / DKIM / SPF

debconf-set-selections <<< "postfix postfix/mailname string mail.hazevedo.dev"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt install --assume-yes postfix postfix-mysql dovecot-core dovecot-mysql dovecot-imapd\
  dovecot-pop3d dovecot-lmtpd dovecot-sieve dovecot-managesieved openssl\
  opendkim opendkim-tools postfix-policyd-spf-python postfix-pcre

echo "root: postmaster@hrazevedo.dev" >> /etc/aliases

newaliases

# PostfixAdmin

cd /opt
git clone https://github.com/postfixadmin/postfixadmin.git
cd /opt/postfixadmin
bash install.sh
chown -R www-data. /opt/postfixadmin

systemctl reload apache2

echo "\$CONF['encrypt'] = 'md5';" >> /opt/postfixadmin/config.inc.php
echo "\$CONF['default_language'] = 'pt-br';" >> /opt/postfixadmin/config.inc.php

sed -i 's/change-this-to-your.domain.tld/hazevedo.dev/' /opt/postfixadmin/config.inc.php

mariadb < $PATH/opt/postfixadmin/create_database.sql

groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/vmail
mkdir /var/vmail
chown vmail:vmail /var/vmail

cp /etc/postfix/main.cf /etc/postfix/main.cf.orig

MINHASENHA='password'

# mysql_virtual_alias_maps.cf

echo "
hosts = localhost
user = postfixadmin
password = $MINHASENHA
dbname = postfixadmin
query = SELECT goto FROM alias WHERE address='%s' AND active = '1'
" >> /etc/postfix/mysql_virtual_alias_maps.cf

# mysql_virtual_mailbox_maps.cf

echo "
hosts = localhost
user = postfixadmin
password = $MINHASENHA
dbname = postfixadmin
query = SELECT maildir FROM mailbox WHERE username='%s' AND active = '1'
" >> /etc/postfix/mysql_virtual_mailbox_maps.cf

# mysql_sender_login_maps.cf

echo "
hosts = localhost
user = postfixadmin
password = $MINHASENHA
dbname = postfixadmin
query = SELECT username AS allowedUser FROM mailbox WHERE username='%s' AND active = 1 UNION SELECT goto FROM alias WHERE address='%s' AND active = '1'
" >> /etc/postfix/mysql_sender_login_maps.cf

# mysql_virtual_domains_maps.cf

echo "
hosts = localhost
user = postfixadmin
password = $MINHASENHA
dbname = postfixadmin
query = SELECT domain FROM domain WHERE domain='%s' AND active = '1'
" >> /etc/postfix/mysql_virtual_domains_maps.cf

cd /etc/postfix
ls -lh mysql_*
chmod o-rwx,g+r mysql_*
chgrp postfix mysql_*

