#!/bin/bash

# CentOS 7.0 inside Xen server

append_to_file() {
	sudo echo $1 | sudo tee -a $2
}

replace_in_file() {
	# $2 = sed line
	# $3 = filepath
	sh -c "sed '$2' < $3 > /tmp/replace.txt"
	chmod o+rw /tmp/replace.txt
	cp /tmp/replace.txt $3
}

# Add cd drive mount point
mkdir /mnt/DVD
append_to_file '/dev/cdrom  /mnt/dvd  iso9660 defauts 0 0' /etc/fstab
mount -a

# Install XenTools
cd /mnt/DVD/Linux
./install.sh

# Setup networking
append_to_file 'NETWORKING=yes' /etc/sysconfig/network
replace_in_file 's/ONBOOT=no/ONBOOT=yes/g' /etc/sysconfig/network-scripts/ifcfg-eth0
service network start

# basic packages
yum update
yum install wget
yum install vim

# install webmin
cd ˜
yum groupinstall 'Development Tools'
yum install perl-Time-HiRes
yum install perl-YAML
yum install perl-CPAN
yum install pam-devel
cpan local::lib
cpan Authen::PAM
wget  http://www.webmin.com/download/rpm/webmin-current.rpm
wget http://www.webmin.com/jcameron-key.asc
rpm --import jcameron-key.asc
rpm -Uvh webmin-current.rpm
iptables -I INPUT 4 -m state --state NEW -m tcp -p tcp --dport 10000 -j ACCEPT
service iptables save