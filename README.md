Scalr Installer
===============

An Experimental installer for [Scalr Open Source][0].


Usage
=====

### Download ###

Log in to the server you'd like to install Scalr on, and run the following
commands, preferably as root.

    curl https://raw.github.com/Scalr/installer/master/install.sh > install.sh
    curl https://raw.github.com/Scalr/installer/master/libtrap.sh > libtrap.sh


### Install ###

Run the following, as root.

    bash install.sh

Note: we recommend that you run this command using GNU screen, so that the
installation process isn't interrupted if your SSH connection drops.


### Use ###

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
