#!/bin/bash

source libtest
source $INSTALLER_HOME/lib/*

### PHP INSTALLATION ###

testInstallPHPCore () {
  run_installs && install_php_core &> /dev/null

  local min_php="PHP 5.5.0"
  local php_version=`php -v | head -n1`
  if [[ $php_version < $min_php ]]; then
    fail "PHP version \"$php_version\" < \"$min_php\""
  fi
}


### PHP MODULES ###


ensureModuleInstalled () {
  local module=$1
  for sapi in $PHP_SAPIS
  do
    php5query -s $sapi -m $module || fail "Module $module not installed for $sapi"
  done
}


testInstallPHPPackages () {
  run_installs && install_php_extension_packages &> /dev/null

  pear &> /dev/null || fail "pear is not installed"

  for module in mysql curl mcrypt snmp
  do
    ensureModuleInstalled $module
  done
}


testInstallPECLs () {
  echo "Installing PECL shared packages"
  run_installs && install_pecl_shared &> /dev/null

  echo "Testing pecl SSH"
  run_installs && install_pecl_ssh &> /dev/null
  ensureModuleInstalled ssh2

  echo "Testing pecl RRD"
  run_installs && install_pecl_rrd &> /dev/null
  ensureModuleInstalled rrd

  echo "Testing pecl YAML"
  run_installs && install_pecl_yaml &> /dev/null
  ensureModuleInstalled yaml

  echo "Testing pecl HTTP"
  run_installs && install_pecl_http &> /dev/null
  ensureModuleInstalled http
}


### PHP CONFIGURATION ###
testConfigurePHP () {
  run_installs && configure_php

  for sapi in $PHP_SAPIS
  do
    assertEquals "short_open_tag not On for $sapi" 1 "`php -c /etc/php5/$sapi/php.ini -r \"echo(ini_get('short_open_tag'));\"`"
    assertNull "pnctl functions disabled for $sapi" "`php -c /etc/php5/$sapi/php.ini -r \"echo(ini_get('disable_functions'));\"`"
  done
}


suite () {
  #suite_addTest "testInstallPHPCore"
  #suite_addTest "testInstallPHPPackages"
  #suite_addTest "testInstallPECLs"
  #suite_addTest "testConfigurePHP"
}

source $TEST_RUNNER_SHUNIT
