#!/bin/bash

# Set debug
set -o errexit
set -o nounset

if [ "$(id -u)" != "0" ]; then
   echo "The install script should be run as root" 1>&2
   exit 1
fi

# Add latest PHP repo
echo "--- Installing PHP"
add-apt-repository -y ppa:ondrej/php5
apt-get update && apt-get upgrade -y
apt-get install -y php5 php5-mysql php5-curl php-pear php5-mcrypt php5-snmp

# Install common dependencies for PECL packages
echo "--- Installing PECL dependencies"
apt-get install -y build-essential php5-dev libmagic-dev php-pear

# Install PECL HTTP
echo "--- Installing PECL HTTP"
apt-get install -y libcurl3 libcurl4-gnutls-dev
pecl install -f pecl_http
echo extension=http.so > /etc/php5/conf.d/30-http.ini

# Install PECL RRD
echo "--- Installing PECL RRD"
apt-get install -y librrd-dev
pecl install -f rrd
echo extension=rrd.so > /etc/php5/conf.d/40-rrd.ini

# Install PECL YAML
echo "--- Installing PECL YAML"
apt-get install -y libyaml-dev
pecl install -f yaml
echo extension=yaml.so > /etc/php5/conf.d/50-yaml.ini

# Install PECL SSH
echo "--- Installing PECL SSH"
apt-get install -y libssh2-1-dev 
pecl install -f ssh2-beta
echo extension=ssh2.so > /etc/php5/conf.d/60-ssh2.ini


# Passwords
apt-get install -y pwgen
PASSWORDS=~/scalr-passwords
echo "--- Creating passwords dir at $PASSWORDS"
mkdir -p $PASSWORDS

echo "--- Generating Root MySQL password"
MYSQL_PWFILE=$PASSWORDS/root-mysql
pwgen -s 40 > $MYSQL_PWFILE
ROOT_MYSQL=`cat $MYSQL_PWFILE`
echo mysql-server-5.5 mysql-server/root_password password $ROOT_MYSQL | debconf-set-selections
echo mysql-server-5.5 mysql-server/root_password_again password $ROOT_MYSQL | debconf-set-selections
MYSQL_CLIENT_FILE=$PASSWORDS/root-mysql-client
echo "[client]" > $MYSQL_CLIENT_FILE
echo "user=root" >> $MYSQL_CLIENT_FILE
echo "password=$ROOT_MYSQL" >> $MYSQL_CLIENT_FILE
chmod 600 $MYSQL_CLIENT_FILE

echo "--- Generating Scalr MySQL password"
SCALR_PWFILE=$PASSWORDS/scalr-mysql
pwgen -s 40 > $SCALR_PWFILE
SCALR_MYSQL_USERNAME=scalr
SCALR_MYSQL_PASSWORD=`cat $SCALR_PWFILE`
SCALR_MYSQL_DB=scalr

# Install MySQL
echo "--- Installing MySQL"
apt-get install -y mysql-server
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --execute="CREATE DATABASE $SCALR_MYSQL_DB;"
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --execute="GRANT ALL on $SCALR_MYSQL_DB.* to '$SCALR_MYSQL_USERNAME'@'localhost' IDENTIFIED BY '$SCALR_MYSQL_PASSWORD'"


# Install Scalr
echo "--- Installing Scalr"
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

# Configure database
echo "--- Loading database structure"
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/structure.sql
mysql --defaults-extra-file=$MYSQL_CLIENT_FILE --database=$SCALR_MYSQL_DB < $SCALR_SQL/data.sql

# Configure Scalr
echo "--- Configuring Scalr"

SCALR_USER=www-data
SCALR_LOG_DIR="/var/log/scalr"
SCALR_PID_DIR="/var/run/scalr"
SCALR_ID_FILE=$SCALR_APP/etc/id

# Required folders and files
mkdir -p $SCALR_LOG_DIR $SCALR_PID_DIR
touch $SCALR_ID_FILE
chown $SCALR_USER:$SCALR_USER $SCALR_LOG_DIR $SCALR_PID_DIR $SCALR_ID_FILE

cat > $SCALR_APP/etc/config.yml << EOF
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
    ip_pool: ['8.8.8.8'] 
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

# Install Virtualhost
echo "--- Configuring Apache"
cat > /etc/apache2/sites-available/scalr << EOF
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

a2enmod rewrite
a2dissite default
a2ensite scalr
service apache2 restart

# Install crontab
echo "--- Installing crontab for $SCALR_USER"
CRON_FILE=/tmp/$$-scalr-cron
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
rm $CRON_FILE
