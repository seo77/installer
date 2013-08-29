Scalr Installer
===============

An Experimental installer for [Scalr Open Source][0].


Usage
=====

### Download ###

Log in to the server you'd like to install Scalr on, and run the following
commands, preferably as root.

    curl https://raw.github.com/Scalr/installer/master/install.sh > install.sh
    curl https://raw.github.com/Scalr/installer/master/install.sh > libtrap.sh


### Install ###

Run the following, as root.

    bash install.sh


### Configure ###

Edit `/var/scalr/app/etc/config.yml`, and configure the following keys:

  + `scalr.endpoint.scheme`: The protocol over which Scalr should be accessed
    on your server (HTTP if you didn't set up SSL)
  + `scalr.endpoint.host`: A Host (or IP) at which the server you installed
    Scalr on can be reached from your Cloud(s).
  + `scalr.aws.ip_pool`: A CIDR-formatted subnet containing the IP of your
    Scalr server (only if using AWS)


### Run it ###

Visit your server on port 80 to get started. The output of the install script
will contain your login credentials.


Supported OSes
==============

  + Ubuntu 12.04 and up


Roadmap
=======

  + Add support for all Scalr-supported OSes
  + Create packages
  + Implement as Chef recipe


License
=======

Apache 2.0


[![githalytics.com alpha](https://cruel-carlota.pagodabox.com/fc7a1fe68697f6ffcf93fd8e755deb06 "githalytics.com")](http://githalytics.com/Scalr/installer)


  [0]: https://github.com/Scalr/scalr
