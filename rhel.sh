#!/bin/bash

rpm -Uvh http://mirror.webtatic.com/yum/el6/latest.rpm
yum install -y php55w php55w-devel php55w-common php55w-pear



# pecl pecl_http
yum install -y zlib-devel libcurl-devel
printf "\n\n\n\n" | pecl install pecl_http-stable || true  # We need to "accept" the prompts.
echo extension=http.so > /etc/php.d/http.ini  #TODO: This will not work, loads before iconv.


# pecl rrdtool
yum install -y rrdtool-devel
pecl install rrd || true
echo extension=rrd.so > /etc/php.d/rrd.ini


# Notes
# Beta version for PECL http
# Don't enable default /var/www/html/
# http://docs.fedoraproject.org/en-US/Fedora/11/html/Security-Enhanced_Linux/sect-Security-Enhanced_Linux-Troubleshooting-Top_Three_Causes_of_Problems.html
# /usr/sbin/semanage fcontext -a -t httpd_sys_content_t "/var/www/scalr(/.*)?"

#yum install pdns pdns-backend-mysql
