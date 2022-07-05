CREATE DATABASE postfixadmin;
CREATE USER 'postfixadmin'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON postfixadmin.* TO 'postfixadmin'@'localhost' IDENTIFIED BY 'password' WITH GRANT OPTION;
FLUSH PRIVILEGES;
