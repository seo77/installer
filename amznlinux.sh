#!/bin/bash

set -o errexit
set -o nounset

yum install -y php php-devel php-pear \
               gcc rpm-build \
               git

ARCH=x86_64
RPM_BUILD_DIR=/usr/src/rpm/RPMS/
PHP_CONFIG_DIR=/etc/php.d
PHP_CONFIG=$PHP_CONFIG_DIR/php-scalr.ini

SCALR_INSTALL_LOCATION=/opt/scalr
SCALR_APP=$SCALR_INSTALL_LOCATION/app
SCALR_SQL=$SCALR_INSTALL_LOCATION/sql
SCALR_ID_FILE=$SCALR_APP/etc/id
SCALR_LOG_DIR="/var/log/scalr"
SCALR_PID_DIR="/var/run/scalr"

#TODO:Actually clone scalr!

SCALR_USER=apache


# Prepare dir for builds
BUILD_DIR=/tmp/$$-scalr-install
mkdir $BUILD_DIR
chmod 700 $BUILD_DIR
cd $BUILD_DIR


# Downloand PHP
PHP_VER=5.3.27
PHP_DISTRIB=php-$PHP_VER
wget http://us1.php.net/distributions/$PHP_DISTRIB.tar.bz2
bunzip2 $PHP_DISTRIB.tar.bz2
tar -xvf $PHP_DISTRIB.tar 

# Install extensions
EXTENSIONS_DIR=$BUILD_DIR/$PHP_DISTRIB/ext

function create_virtual_package {
    local pkg=$1
    local spec=$BUILD_DIR/$1.spec
    local arch=$ARCH
    cat > $spec << EOF
Summary: Scalr Virtual PHP Package: $pkg
Name: $pkg
Version: $PHP_VER
Release: 1
Group: System Environment/Base
License: PHP License v3.01
BuildArch: $arch
Provides: $pkg

%description

Meta package to make virtually installed packages available.

%files
EOF

    rpmbuild -bb $spec
    rpm -i $RPM_BUILD_DIR/$arch/$pkg-$PHP_VER*
}

function register_extension {
  echo "extension=$1.so" >> $PHP_CONFIG
}

function install_extension {
  CURR_DIR=`pwd`

  cd $EXTENSIONS_DIR/$1
  phpize
  ./configure
  make
  make install

  register_extension $1

  cd $CURR_DIR
  #TODO/ VirtualPackage
}


# Installing pcntl
install_extension pcntl
create_virtual_package php-pcntl

# Installing posix
install_extension posix
create_virtual_package php-posix

# Installing system v semaphores
install_extension sysvmsg
install_extension sysvsem
install_extension sysvshm
create_virtual_package php-sysvmsg
create_virtual_package php-sysvsem
create_virtual_package php-sysvshm

# Install snmp extension
yum install -y net-snmp-devel
install_extension snmp
create_virtual_package php-snmp

# Install mysql extensions
yum install -y mysql # RETARDED OS WANTS MYSQL FOR MYSQL_CONFIG

install_extension pdo
create_virtual_package php-pdo

install_extension mysqlnd  #TODO: Looks like the phpize config file has to be mv'ed ???
create_virtual_package php-mysqlnd

install_extension mysqli
create_virtual_package php-mysql

# Install dom extension
yum install -y libxml2-devel
install_extension dom
create_virtual_package php-dom

# Install mcrypt
yum install -y libmcrypt-devel
install_extension mcrypt
create_virtual_package php-mcrypt

# Install soap
install_extension soap
create_virtual_package php-soap

# Install PECL extensions
# SSH2
yum install -y libssh2-devel
pecl install ssh2-beta #TODO: I/O
create_virtual_package php-pecl-libssh2
register_extension ssh2

yum install -y libcurl-devel libzip-devel
pecl install pecl_http #TODO: I/O
create_virtual_package php-pecl-http
register_extension http

yum install -y libyaml-devel
pecl install yaml  #TODO: I/O
create_virtual_package php-pecl-yaml


# 



#  We'll need epel to install pwgen
yum --enablerepo=epel install pwgen

ROOT_MYSQL_USERNAME=root
ROOT_MYSQL_PASSWORD=`pwgen -s 40`

SCALR_MYSQL_USERNAME=scalr
SCALR_MYSQL_PASSWORD=`pwgen -s 40`

SCALR_MYSQL_DB=scalr

SCALR_ADMIN_USER=admin
SCALR_ADMIN_PASSWORD=`pwgen 20`

# Set mysql root password
/usr/bin/mysqladmin -u root password "$ROOT_MYSQL_PASSWORD"

MYSQL_CLIENT_FILE=$BUILD_DIR/mysql-client-file.ini
cat > $MYSQL_CLIENT_FILE << EOF
[client]
user=$ROOT_MYSQL_USERNAME
password=$ROOT_MYSQL_PASSWORD
EOF

# Create MySQL tables
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE -e "CREATE DATABASE $SCALR_MYSQL_DB;"
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE -e "GRANT ALL on $SCALR_MYSQL_DB.* to '$SCALR_MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$SCALR_MYSQL_PASSWORD';"
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/structure.sql
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/data.sql
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB -e "update account_users set password=SHA2(\"$SCALR_ADMIN_PASSWORD\", 256) where id=1";

# we have to install the python deps
#TODO: Installer doesn't support amazon linux
cd $SCALR_APP/python
python setup.py install

# Some folders have a required ownership

SCALR_CACHE=$SCALR_APP/cache
mkdir -p $SCALR_CACHE $SCALR_LOG_DIR $SCALR_PID_DIR
touch $SCALR_ID_FILE
chown $SCALR_USER:$SCALR_USER $SCALR_ID_FILE $SCALR_CACHE $SCALR_LOG_DIR $SCALR_PID_DIR


# Configure Scalr
cat > $SCALR_APP/etc/config.yml << EOF
scalr:
  connections:
    mysql: &connections_mysql
      host: 'localhost'
      port: ~
      name: '$SCALR_MYSQL_DB'
      user: '$SCALR_MYSQL_USERNAME'
      pass: '$SCALR_MYSQL_PASSWORD'
  ui:
    support_url: 'https://groups.google.com/d/forum/scalr-discuss'
    wiki_url: 'http://wiki.scalr.com'
  pma_instance_ip_address: '127.0.0.1'
  auth_mode: scalr
  instances_connection_policy: public
  allowed_clouds:
   - ec2
   - openstack
   - cloudstack
   - idcf
   - gce
   - eucalyptus
   - rackspace
   - rackspacenguk
   - rackspacengus
  endpoint:
    scheme: http
    host: 'endpoint url here'
  aws:
    security_group_name: 'scalr.ip-pool'
    ip_pool: ['8.8.8.8/32']
    security_group_prefix: 'scalr.'
  billing:
    enabled: no
    chargify_api_key: ''
    chargify_domain: ''
    emergency_phone_number: ''
  dns:
    mysql:
      host: 'localhost'
      port: ~
      name: 'scalr'
      user: 'scalr'
      pass: 'scalr'
    static:
      enabled: no
      nameservers: ['ns1.example-dns.net', 'ns2.example-dns.net']
      domain_name: 'example-dns.net'
    global:
      enabled: no
      nameservers: ['ns1.example.net', 'ns2.example.net', 'ns3.example.net', 'ns4.example.net']
      default_domain_name: 'provide.domain.here.in'
  msg_sender:
    connections:
      mysql:
        <<: *connections_mysql
        driver: 'mysql+pymysql'
        pool_recycle: 120
        pool_size: 10
    pool_size: 50
    log_file: "$SCALR_LOG_DIR/messaging.log"
    pid_file: "$SCALR_PID_DIR/messaging.pid"
  stats_poller:
    connections:
      mysql:
        <<: *connections_mysql
        driver: 'mysql+pymysql'
        pool_recycle: 120
        pool_size: 4
    metrics: ['cpu', 'la', 'mem', 'net']
    farm_procs: 2
    serv_thrds: 100
    rrd_thrds: 2
    rrd_db_dir: '/tmp/rrd_db_dir'
    images_path: '/var/www/graphics'
    graphics_url: 'http://example.com/graphics'
    log_file: '$SCALR_LOG_DIR/stats-poller.log'
    pid_file: '$SCALR_PID_DIR/stats-poller.pid'
EOF


CRON_FILE=$BUILD_DIR/scalr-cron
crontab -u $SCALR_USER -l > $CRON_FILE.bak || true  # Back up, ignore errors

cat > $CRON_FILE << EOF
* * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --Scheduler
*/5 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --UsageStatsPoller
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron-ng/cron.php --Scaling
* * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --DBQueueEvent
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --SzrMessaging
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --BundleTasksManager
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron-ng/cron.php --DeployManager
*/15 * * * * /usr/bin/php -q $SCALR_APP/cron-ng/cron.php --MetricCheck
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron-ng/cron.php --Poller
*/10 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --MySQLMaintenance
* * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --DNSManagerPoll
17 5 * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --RotateLogs
*/2 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --EBSManager
*/20 * * * * /usr/bin/php -q $SCALR_APP/cron/cron.php --RolesQueue
*/5 * * * * /usr/bin/php -q $SCALR_APP/cron-ng/cron.php --DbMsrMaintenance
*/5 * * * * python -m scalrpy.stats_poller -c $SCALR_APP/etc/config.yml -i 120 --start
*/5 * * * * python -m scalrpy.messaging -c $SCALR_APP/etc/config.yml --start
EOF

crontab -u $SCALR_USER $CRON_FILE


#TODO: Cryptokey

cat > /etc/httpd/conf.d/scalr.conf << EOF
<VirtualHost *:80>
ServerName scalr.mydomain.com
ServerAdmin scalr@mydomain.com
DocumentRoot $SCALR_APP/www

<Directory $SCALR_APP/www>
Options -Indexes FollowSymLinks MultiViews
AllowOverride All
Order allow,deny
allow from all
</Directory>

ErrorLog $SCALR_LOG_DIR/scalr-error.log
CustomLog $SCALR_LOG_DIR/scalr-access.log combined
LogLevel warn
</VirtualHost>
EOF

echo "127.0.0.1 $(hostname)" >> /etc/hosts
