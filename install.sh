#/bin/bash

EMAIL_SERVER_DIR=${PWD}

tar -vxzf $EMAIL_SERVER_DIR/config.tar.gz -C $EMAIL_SERVER_DIR/

# APACHE2, MARIADB E PHP7

cd /tmp

apt update \
&& apt upgrade -y \
&& apt install apache2 apache2-utils mariadb-server mariadb-client curl\
  libapache2-mod-php php php-mysql php-cli php-pear php-gmp php-gd php-bcmath\
  php-mbstring php-curl php-xml php-zip php-imap php-intl php-ldap php-sqlite3 php-imagick wget;

a2enmod rewrite;

mv /etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf.orig
cp $EMAIL_SERVER_DIR/etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-enabled/000-default.conf

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
cp $EMAIL_SERVER_DIR/etc/apache2/conf-available/phpmyadmin.conf /etc/apache2/conf-available/phpmyadmin.conf

a2enconf phpmyadmin;
systemctl restart apache2;

mariadb < $EMAIL_SERVER_DIR/usr/share/phpmyadmin/sql/create_database.sql
mariadb phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql

cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
cat $EMAIL_SERVER_DIR/usr/share/phpmyadmin/config.hazevedo.inc.php >> /usr/share/phpmyadmin/config.inc.php

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

cp $EMAIL_SERVER_DIR/etc/apache2/conf-enabled/postfixadmin.conf /etc/apache2/conf-enabled/postfixadmin.conf
cp $EMAIL_SERVER_DIR/opt/postfixadmin/config.local.inc.php /opt/postfixadmin/config.local.php

systemctl reload apache2

echo "\$CONF['encrypt'] = 'md5';" >> /opt/postfixadmin/config.inc.php
echo "\$CONF['default_language'] = 'pt-br';" >> /opt/postfixadmin/config.inc.php
echo "\$CONF['configured'] = 'true';" >> /opt/postfixadmin/config.inc.php
sed -i 's/change-this-to-your.domain.tld/hazevedo.dev/' /opt/postfixadmin/config.inc.php

mariadb < $EMAIL_SERVER_DIR/opt/postfixadmin/create_database.sql

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

cp /etc/postfix/master.cf /etc/postfix/master.cf.orig

echo "# Dovecot" >> /etc/postfix/master.cf
echo "dovecot   unix  -       n       n       -       -       pipe" >> /etc/postfix/master.cf
echo "  flags=DRhu user=vmail:vmail argv=/usr/lib/dovecot/deliver -d ${recipient}" >> /etc/postfix/master.cf

cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.orig
sed -i -e 's/#listen/listen/' /etc/dovecot/dovecot.conf

cp /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.orig
sed -i -e 's/#driver =/driver = mysql/' /etc/dovecot/dovecot-sql.conf.ext

echo " " >> /etc/dovecot/dovecot.conf
echo "service stats {" >> /etc/dovecot/dovecot.conf
echo "    unix_listener stats-reader {" >> /etc/dovecot/dovecot.conf
echo "        user = vmail" >> /etc/dovecot/dovecot.conf
echo "        group = vmail" >> /etc/dovecot/dovecot.conf
echo "        mode = 0660" >> /etc/dovecot/dovecot.conf
echo "    }" >> /etc/dovecot/dovecot.conf
echo " " >> /etc/dovecot/dovecot.conf
echo "    unix_listener stats-writer {" >> /etc/dovecot/dovecot.conf
echo "        user = vmail" >> /etc/dovecot/dovecot.conf
echo "        group = vmail" >> /etc/dovecot/dovecot.conf
echo "        mode = 0660" >> /etc/dovecot/dovecot.conf
echo "    }" >> /etc/dovecot/dovecot.conf
echo "}" >> /etc/dovecot/dovecot.conf

sed -i -e "s/#connect =/connect = host=localhost dbname=postfixadmin user=postfixadmin password=$MINHASENHA/" /etc/dovecot/dovecot-sql.conf.ext
sed -i -e 's/#default_pass_scheme/default_pass_scheme/' /etc/dovecot/dovecot-sql.conf.ext

echo "" >> /etc/dovecot/dovecot-sql.conf.ext
echo "user_query = SELECT concat('/var/vmail/', maildir) as home, concat('maildir:/var/vmail/', maildir) as mail, 5000 AS uid, 5000 AS gid, concat('*:bytes=', (quota)) AS quota_rule FROM mailbox WHERE username = '%u' AND active = '1';" >> /etc/dovecot/dovecot-sql.conf.ext
echo "" >> /etc/dovecot/dovecot-sql.conf.ext
echo "password_query = SELECT username as user, password, concat('/var/vmail/', maildir) as userdb_home, concat('maildir:/var/vmail/', maildir) as userdb_mail, 5000 as userdb_uid, 5000 as userdb_gid, concat('*:bytes=', (quota)) AS userdb_quota_rule FROM mailbox WHERE username = '%u' AND active = '1';" >> /etc/dovecot/dovecot-sql.conf.ext

cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.orig
sed -i -e 's/#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i -e 's/auth_mechanisms = plain/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
sed -i -e 's/!include auth-system.conf.ext/#!include auth-system.conf.ext/' /etc/dovecot/conf.d/10-auth.conf
sed -i -e 's/#!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf

cp /etc/dovecot/conf.d/10-logging.conf /etc/dovecot/conf.d/10-logging.conf.orig
sed -i -e 's/#log_path/log_path/' /etc/dovecot/conf.d/10-logging.conf
sed -i -e 's/#log_timestamp = "%b %d %H:%M:%S "/log_timestamp = "%Y-%m-%d %H:%M:%S "/' /etc/dovecot/conf.d/10-logging.conf

cp /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.orig

cp $EMAIL_SERVER_DIR/etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf

mkdir /var/lib/dovecot/sieve/
cp /etc/dovecot/conf.d/90-sieve.conf /etc/dovecot/conf.d/90-sieve.conf.orig
sed -i -e 's/sieve = file:~\/sieve;active=~\/.dovecot.sieve/sieve = ~\/dovecot.sieve/' /etc/dovecot/conf.d/90-sieve.conf
sed -i -e 's/#sieve_default =/sieve_default =/' /etc/dovecot/conf.d/90-sieve.conf

echo 'require ["fileinto"];' >> /var/lib/dovecot/sieve/default.sieve
echo '# rule:[Spam]' >> /var/lib/dovecot/sieve/default.sieve
echo 'if header :contains "X-Spam-Flag" "YES" {' >> /var/lib/dovecot/sieve/default.sieve
echo '        fileinto "Junk";' >> /var/lib/dovecot/sieve/default.sieve
echo '}' >> /var/lib/dovecot/sieve/default.sieve

sievec /var/lib/dovecot/sieve/default.sieve
chown -R vmail:vmail /var/lib/dovecot

cp /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.orig
sed -i -e 's/mail_location = mbox:~\/mail:INBOX=\/var\/mail\/%u/mail_location = mbox:~\/mail:INBOX=\/var\/vmail\/%u/' /etc/dovecot/conf.d/10-mail.conf

sed -i -e 's/inbox = yes/inbox = yes\n  /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    } /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      special_use = \Junk /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      auto = subscribe /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    mailbox Junk { /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    } /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      special_use = \Sent /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      auto = subscribe /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    mailbox Sent { /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    } /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      special_use = \Drafts /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      auto = subscribe /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    mailbox Drafts { /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n    } /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      special_use = \Trash /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n      auto = subscribe /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n  mailbox Trash { /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/inbox = yes/inbox = yes\n  /' /etc/dovecot/conf.d/10-mail.conf
sed -i -e 's/#mail_plugins =/mail_plugins = quota/' /etc/dovecot/conf.d/10-mail.conf

cp /etc/dovecot/conf.d/20-managesieve.conf  /etc/dovecot/conf.d/20-managesieve.conf.orig

cp $EMAIL_SERVER_DIR/etc/dovecot/conf.d/20-managesieve.conf /etc/dovecot/conf.d/20-managesieve.conf

echo "protocols = $protocols sieve" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "service managesieve-login {" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "}" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "service managesieve {" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "}" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "protocol sieve {" >> /etc/dovecot/conf.d/20-managesieve.conf
echo "}" >> /etc/dovecot/conf.d/20-managesieve.conf

cp /etc/dovecot/conf.d/15-lda.conf /etc/dovecot/conf.d/15-lda.conf.orig
sed -i -e 's/#mail_plugins = $mail_plugins/mail_plugins = $mail_plugins sieve quota/' /etc/dovecot/conf.d/15-lda.conf

cp /etc/dovecot/conf.d/20-imap.conf /etc/dovecot/conf.d/20-imap.conf.orig
sed -i -e 's/#mail_plugins = $mail_plugins/mail_plugins = $mail_plugins quota imap_quota/' /etc/dovecot/conf.d/20-imap.conf

cp /etc/dovecot/conf.d/20-pop3.conf /etc/dovecot/conf.d/20-pop3.conf.orig
sed -i -e 's/#mail_plugins = $mail_plugins/mail_plugins = $mail_plugins quota/' /etc/dovecot/conf.d/20-pop3.conf

cp /etc/dovecot/conf.d/90-quota.conf /etc/dovecot/conf.d/90-quota.conf.orig
sed -i -e 's/#quota = maildir/quota = maildir/' /etc/dovecot/conf.d/90-quota.conf
sed -i -e 's/#quota_rule =/quota_rule =/' /etc/dovecot/conf.d/90-quota.conf
sed -i -e 's/#quota_rule2 =/quota_rule2 =/' /etc/dovecot/conf.d/90-quota.conf
sed -i -e 's/#quota_warning/quota_warning/' /etc/dovecot/conf.d/90-quota.conf

echo "service quota-warning {" >> /etc/dovecot/conf.d/90-quota.conf
echo "  executable = script /usr/local/bin/quota-warning.sh" >> /etc/dovecot/conf.d/90-quota.conf
echo "  user = root" >> /etc/dovecot/conf.d/90-quota.conf
echo "  unix_listener quota-warning {" >> /etc/dovecot/conf.d/90-quota.conf
echo "    user = vmail" >> /etc/dovecot/conf.d/90-quota.conf
echo "  }" >> /etc/dovecot/conf.d/90-quota.conf
echo "}" >> /etc/dovecot/conf.d/90-quota.conf

cp $EMAIL_SERVER_DIR/usr/local/bin/quota-warning.sh /usr/local/bin/quota-warning.sh

chmod +x /usr/local/bin/quota-warning.sh
systemctl restart dovecot postfix
systemctl status dovecot postfix

# WebMail RoundCube

sed -i -e "s/^;date\.timezone =.*$/date\.timezone = 'America\/Sao_Paulo'/" /etc/php/7.4/apache2/php.ini
systemctl restart apache2

cd /var/www/html
wget https://github.com/roundcube/roundcubemail/releases/download/1.5.3/roundcubemail-1.5.3-complete.tar.gz
tar -vxzf roundcubemail*
mv roundcubemail-1.5.3 webmail
rm roundcubemail-1.5.3-complete.tar.gz

cp $EMAIL_SERVER_DIR/opt/roundcub/create_database.sql /var/www/html/webmail/installer/create_database.sql
mariadb < /var/www/html/webmail/installer/create_database.sql

chown www-data. /var/www/html/webmail/ -R


