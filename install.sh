#!/bin/bash

# Set debug
set -o errexit
set -o nounset

if [ "$(id -u)" != "0" ]; then
  echo "The install script should be run as root" 1>&2
  exit 1
fi

# Check which version this is
wrong_version () {
  echo "This installer is for Ubuntu 12.04 \"Precise\" and up"
  echo "It is not compatible with your system"
  exit 1
}
LSB_RELEASE=/etc/lsb-release

if [ ! -f $LSB_RELEASE ]; then
  wrong_version
fi

source $LSB_RELEASE || wrong_version

if [ $DISTRIB_ID != "Ubuntu" ] || [ "$DISTRIB_RELEASE" '<' "12.04" ]; then
  wrong_version
fi

# Check we are on a supported Kernel
KERNEL_UNSUPPORTED_MIN=2.6.30
KERNEL_UNSUPPORTED_MAX=2.6.39
KERNEL_VERSION=`uname -r`

if [ ! "$KERNEL_VERSION" '<' "$KERNEL_UNSUPPORTED_MIN" ] && [ ! "$KERNEL_VERSION" '>' "$KERNEL_UNSUPPORTED_MAX" ] ; then
  echo "Scalr does not support Linux Kernels $KERNEL_UNSUPPORTED_MIN to $KERNEL_UNSUPPORTED_MAX"
  echo "Please consider upgrading your Kernel."
  exit 1
fi


# Import our trap lib
source libtrap.sh

echo
echo "======================"
echo "    Creating Users    "
echo "======================"
echo

SERVICE_USER=root  # Already exists
WEB_USER=www-data
useradd --system $WEB_USER || true  # It should already exist

SCALR_GROUP=scalr  # Needs creation
groupadd --force $SCALR_GROUP  # We don't want this to exist already

for user in $SERVICE_USER $WEB_USER
do
  usermod --append --groups $SCALR_GROUP $user
done

# Add latest PHP repo
echo
echo "======================"
echo "    Installing PHP    "
echo "======================"
echo

apt-get update
apt-get install -y python-software-properties
add-apt-repository -y ppa:ondrej/php5
apt-get update && apt-get upgrade -y
apt-get install -y php5 php5-mysql php5-curl php-pear php5-mcrypt php5-snmp

# Install common dependencies for PECL packages
echo
echo "===================================="
echo "    Installing PECL Dependencies    "
echo "===================================="
echo
apt-get install -y build-essential php5-dev libmagic-dev php-pear

# Install PECL HTTP
echo
echo "============================"
echo "    Installing PECL HTTP    "
echo "============================"
echo
apt-get install -y libcurl3 libcurl4-gnutls-dev
printf "\n\n\n\n" | pecl install pecl_http || true  # We need to "accept" the prompts.
echo extension=http.so > /etc/php5/mods-available/http.ini
php5enmod http

# Install PECL RRD
echo
echo "==========================="
echo "    Installing PECL RRD    "
echo "==========================="
echo
apt-get install -y librrd-dev
pecl install rrd || true
echo extension=rrd.so > /etc/php5/mods-available/rrd.ini
php5enmod rrd

# Install PECL YAML
echo
echo "============================"
echo "    Installing PECL YAML    "
echo "============================"
echo
apt-get install -y libyaml-dev
printf "\n" | pecl install yaml || true
echo extension=yaml.so > /etc/php5/mods-available/yaml.ini
php5enmod yaml

# Install PECL SSH
echo
echo "==========================="
echo "    Installing PECL SSH    "
echo "==========================="
echo
apt-get install -y libssh2-1-dev
printf "\n" | pecl install ssh2-beta || true
echo extension=ssh2.so > /etc/php5/mods-available/ssh2.ini
php5enmod ssh2

# Disable disabled functions
echo
echo "==========================="
echo "   Changing PHP settings   "
echo "==========================="
echo
echo "removing disabled functions"
sed -i '/^disable_functions/d' /etc/php5/apache2/php.ini
sed -i '/^disable_functions/d' /etc/php5/cli/php.ini
echo "enabling short open tags"
sed -i -r 's/short_open_tag = .+/short_open_tag = On/g' /etc/php5/apache2/php.ini
sed -i -r 's/short_open_tag = .+/short_open_tag = On/g' /etc/php5/cli/php.ini

# Passwords
echo
echo "=========================="
echo "    Creating Passwords    "
echo "=========================="
echo
apt-get install -y pwgen

# MySQL root password
ROOT_MYSQL=`pwgen -s 40`
echo mysql-server-5.5 mysql-server/root_password password $ROOT_MYSQL | debconf-set-selections
echo mysql-server-5.5 mysql-server/root_password_again password $ROOT_MYSQL | debconf-set-selections

# Securely authenticate to MySQL
MYSQL_CLIENT_FILE=~/$$-root-mysql-client
echo "[client]" > $MYSQL_CLIENT_FILE
chmod 600 $MYSQL_CLIENT_FILE
set +o nounset  # The trap lib uses eval and dynamic variable names
trap_append "rm $MYSQL_CLIENT_FILE" SIGINT SIGTERM EXIT  # Remove the auth file when exiting
set -o nounset
echo "user=root" >> $MYSQL_CLIENT_FILE
echo "password=$ROOT_MYSQL" >> $MYSQL_CLIENT_FILE

# Scalr MySQL user
SCALR_MYSQL_USERNAME=scalr
SCALR_MYSQL_PASSWORD=`pwgen -s 40`
SCALR_MYSQL_DB=scalr

# Scalr admin user
SCALR_ADMIN_PASSWORD=`pwgen 20`

# Install MySQL
echo
echo "========================"
echo "    Installing MySQL    "
echo "========================"
echo
apt-get install -y mysql-server
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --execute="CREATE DATABASE $SCALR_MYSQL_DB;"
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --execute="GRANT ALL on $SCALR_MYSQL_DB.* to '$SCALR_MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$SCALR_MYSQL_PASSWORD'"


# Install Scalr
echo
echo "========================"
echo "    Installing Scalr    "
echo "========================"
echo

SCALR_REPO=https://github.com/Scalr/scalr.git
SCALR_INSTALL=/var/scalr
SCALR_APP=$SCALR_INSTALL/app
SCALR_SQL=$SCALR_INSTALL/sql
apt-get install -y git
git clone $SCALR_REPO $SCALR_INSTALL

# We have to be in the correct folder to install.
curr_dir=`pwd`
cd $SCALR_APP/python
python setup.py install
cd $curr_dir

# We have to create the cache folder
SCALR_CACHE=$SCALR_APP/cache
mkdir --mode=770 $SCALR_CACHE
chown $SERVICE_USER:$SCALR_GROUP $SCALR_CACHE

# Configure database
echo
echo "==================================="
echo "    Configuring Scalr Database     "
echo "==================================="
echo
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/structure.sql
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/data.sql

# Configure Scalr
echo
echo "=========================="
echo "    Configuring Scalr     "
echo "=========================="
echo

SCALR_LOG_DIR="/var/log/scalr"
SCALR_PID_DIR="/var/run/scalr"
SCALR_ID_FILE=$SCALR_APP/etc/id
SCALR_CONFIG_FILE=$SCALR_APP/etc/config.yml

# Required folders and files
mkdir --mode=775 --parents $SCALR_LOG_DIR $SCALR_PID_DIR
chown $SERVICE_USER:$SCALR_GROUP $SCALR_LOG_DIR $SCALR_PID_DIR

touch $SCALR_ID_FILE
chown $SERVICE_USER:$SCALR_GROUP $SCALR_ID_FILE
chmod 664 $SCALR_ID_FILE

# Process "names" for Python scripts (useful later for start-stop-daemon matching)
POLLER_NAME=poller
POLLER_LOG=$SCALR_LOG_DIR/$POLLER_NAME.log
POLLER_PID=$SCALR_PID_DIR/$POLLER_NAME.pid

MESSAGING_NAME=messaging
MESSAGING_LOG=$SCALR_LOG_DIR/$MESSAGING_NAME.log
MESSAGING_PID=$SCALR_PID_DIR/$MESSAGING_NAME.pid

# TODO: Here again, race condition
cat > $SCALR_CONFIG_FILE << EOF
scalr:
  connections:
    mysql: &connections_mysql
      host: 'localhost'
      port: ~
      name: $SCALR_MYSQL_DB
      user: $SCALR_MYSQL_USERNAME
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
    log_file: "$MESSAGING_LOG"
    pid_file: "$MESSAGING_PID"
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
    rrd_db_dir: '/var/lib/rrdcached/db'
    images_path: '$SCALR_APP/www/graphics'
    graphics_url: '/graphics'
    log_file: "$POLLER_LOG"
    pid_file: "$POLLER_PID"
EOF

chown $SERVICE_USER:$SCALR_GROUP $SCALR_CONFIG_FILE
chmod 660 $SCALR_CONFIG_FILE

# Install Rrdcached
echo
echo "==========================="
echo "    Configuring rrdcached  "
echo "==========================="
echo
# Workaround for https://bugs.launchpad.net/ubuntu/+source/rrdtool/+bug/985341
if [ "$DISTRIB_RELEASE" '=' "12.04" ]; then
    mkdir -p /var/lib/rrdcached/db /var/lib/rrdcached/journal
    chown $(printf %q "$USER"):$(printf %q "$(groups | awk '{print $1}')") /var/lib/rrdcached/db /var/lib/rrdcached/journal
fi
apt-get install -y rrdcached

cat >> /etc/default/rrdcached << EOF
OPTS="-s $SCALR_GROUP"
OPTS="\$OPTS -l unix:/var/run/rrdcached.sock"
OPTS="\$OPTS -j /var/lib/rrdcached/journal/ -F"
OPTS="\$OPTS -b /var/lib/rrdcached/db/ -B"
EOF

mkdir --mode=775 $SCALR_APP/www/graphics/
chown $SERVICE_USER:$SCALR_GROUP $SCALR_APP/www/graphics/

mkdir --mode=775 /var/lib/rrdcached/db/{x1x6,x2x7,x3x8,x4x9,x5x0}
chown $SERVICE_USER:$SCALR_GROUP /var/lib/rrdcached/db/{x1x6,x2x7,x3x8,x4x9,x5x0}

service rrdcached restart

# Install Virtualhost
echo
echo "==========================="
echo "    Configuring Apache     "
echo "==========================="
echo

SCALR_SITE_NAME=scalr
SCALR_SITE_PATH=/etc/apache2/sites-available/$SCALR_SITE_NAME

cat > $SCALR_SITE_PATH << EOF
<VirtualHost *:80>
ServerName scalr.mydomain.com
ServerAdmin scalr@mydomain.com
DocumentRoot $SCALR_APP/www

<Directory $SCALR_APP/www>
Options -Indexes +FollowSymLinks +MultiViews
AllowOverride All
Order allow,deny
allow from all
Require all granted
</Directory>

ErrorLog $SCALR_LOG_DIR/scalr-error.log
CustomLog $SCALR_LOG_DIR/scalr-access.log combined
LogLevel warn
</VirtualHost>
EOF

a2enmod rewrite

# Disable all Apache default sites, however they're called
a2dissite default || true
a2dissite 000-default || true

# Try adding our site, whichever configuration works
a2ensite $SCALR_SITE_NAME || mv $SCALR_SITE_PATH $SCALR_SITE_PATH.conf && a2ensite $SCALR_SITE_NAME

service apache2 restart

# Install crontab
echo
echo "============================="
echo "    Configuring Cronjobs     "
echo "============================="
echo
CRON_FILE=/tmp/$$-scalr-cron  #TODO: Fix insecure race condition on creation here
crontab -u $SERVICE_USER -l > $CRON_FILE.bak || true  # Back up, ignore errors

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
EOF

crontab -u $SERVICE_USER $CRON_FILE
rm $CRON_FILE

echo
echo "===================================="
echo "    Configuring Daemon Services     "
echo "===================================="
echo

INIT_DIR=/etc/init

prepare_init () {
  local daemon_name=$1
  local daemon_desc=$2
  local daemon_pidfile=$3
  local daemon_proc=$4
  local daemon_args=$5


  cat > $INIT_DIR/$daemon_name.conf << EOF
description "$daemon_desc"

start on runlevel [2345]
stop on runlevel [!2345]

respawn
respawn limit 10 5

expect daemon

console none

pre-start script
  if [ ! -r $SCALR_CONFIG_FILE ]; then
    logger -is -t "\$UPSTART_JOB" "ERROR: Config file is not readable"
    exit 1
  fi
  mkdir --mode=775 --parents $SCALR_PID_DIR
  chown $SERVICE_USER:$SCALR_GROUP $SCALR_PID_DIR
end script

exec start-stop-daemon --start --chuid $SERVICE_USER:$SCALR_GROUP --pidfile $daemon_pidfile --exec $daemon_proc -- $daemon_args
EOF
# We can't use setuid / setgid: we need pre-start to run as root.
}

PYTHON=`command -v python`

prepare_init "$POLLER_NAME" "Scalr Stats Poller Daemon" "$POLLER_PID" "$PYTHON" "-m scalrpy.stats_poller -c $SCALR_CONFIG_FILE --start --interval 120"
prepare_init "$MESSAGING_NAME" "Scalr Messaging Daemon" "$MESSAGING_PID" "$PYTHON" "-m scalrpy.messaging -c $SCALR_CONFIG_FILE --start"

service $POLLER_NAME start
service $MESSAGING_NAME start

echo
echo "==========================="
echo "    Configuring System     "
echo "==========================="
echo

echo "kernel.msgmnb = 524288" > /etc/sysctl.d/60-scalr.conf

service procps start

echo
echo "==========================="
echo "    Configuring Users     "
echo "==========================="
echo
apt-get install -y hashalot
HASHED_PASSWORD=`echo $SCALR_ADMIN_PASSWORD | sha256 -x`
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB \
  --execute="UPDATE account_users SET password='$HASHED_PASSWORD' WHERE id=1"

echo
echo "==========================="
echo "    Validating Install     "
echo "==========================="
echo

CRYPTOKEY_PATH=$SCALR_APP/etc/.cryptokey
touch $CRYPTOKEY_PATH  # TODO: Race condition
chown $SERVICE_USER:$SCALR_GROUP $CRYPTOKEY_PATH
chmod 660 $CRYPTOKEY_PATH

set +o nounset
trap_append "chmod 440 $CRYPTOKEY_PATH" SIGINT SIGTERM EXIT  # Restore ownership of the cryptokey
set -o nounset

for user in $SERVICE_USER $WEB_USER
do
  sudo -u $user php $SCALR_APP/www/testenvironment.php || true # We don't want to exit on an error
done


echo
echo "=============================="
echo "    Done Installing Scalr     "
echo "=============================="
echo

echo "Scalr is installed to:                 $SCALR_INSTALL"
echo "Scalr web is running under user:       $WEB_USER"
echo "Scalr services are running under user: $SERVICE_USER"
echo
echo "==================================="
echo "    Auto-generated credentials     "
echo "==================================="
echo
echo "Passwords have automatically been generated"
echo "MySQL root:$ROOT_MYSQL"
echo "MySQL $SCALR_MYSQL_USERNAME:$SCALR_MYSQL_PASSWORD"
echo
echo "You may log in using the credentials:"
echo "Username: admin"
echo "Password: $SCALR_ADMIN_PASSWORD"

echo
echo "==================================="
echo "    Next steps                     "
echo "==================================="
echo


echo "Configuration"
echo "-------------"
echo "    Some optional modules have not been installed: DNS, LDAP"
echo "    You should configure security settings in $SCALR_APP/etc/config.yml"
echo

echo "Quickstart Roles"
echo "----------------"
echo "Scalr provides, free of charge, up-to-date role images for AWS"
echo "Those will help you get started with Scalr. To get access:"
echo "    1. Copy the contents of $SCALR_ID_FILE: `cat $SCALR_ID_FILE`"
echo "    2. Submit them to this form: http://goo.gl/qD4mpa"
echo "    3. Run: \$ php $SCALR_APP/tools/sync_shared_roles.php"

echo
