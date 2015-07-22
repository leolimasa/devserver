
#!/bin/bash

# CentOS 7.0 minimal. Networking pre configured from install.
# Ensure to CREATE FORMATTED SDA4 FOR GLUSTER BUT DO NOT ASSIGN IT TO LVM OR MOUNT POINTS

export HOSTNAME=ovirt.home.leois.cool

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


echo "172.16.16.3 ovirt-engine.home.leois.cool" >> /etc/hosts
hostnamectl set-hostname $HOSTNAME
yum localinstall -y http://resources.ovirt.org/pub/yum-repo/ovirt-release35.rpm
yum update
yum install -y wget vim ovirt-hosted-engine-setup screen glusterfs-server nfs-utils vdsm-gluster system-storage-manager

# -------------
# Gluster setup
# -------------

# partitioning
pvcreate /dev/sda4 # add sda4 to the logical volume manager
ssm add -p gluster /dev/sda4
ssm create -p gluster --fstype xfs -n gluster
mkdir /gluster 
blkid /dev/gluster/gluster
export GLUSTER_UUID=`blkid /dev/gluster/gluster | cut -d" " -f2 | sed 's/\"//g'`
echo "$GLUSTER_UUID /gluster xfs defaults 0 0" >> /etc/fstab
mount -a

# gluster volumes
mkdir /gluster/{engine,data}
mkdir /gluster/{engine,data}/brick
systemctl start glusterd && systemctl enable glusterd

gluster volume create engine $HOSTNAME:/gluster/engine/brick
gluster volume set engine group virt 
gluster volume set engine storage.owner-uid 36 && gluster volume set engine storage.owner-gid 36 
gluster volume start engine 

gluster volume create data $HOSTNAME:/gluster/data/brick
gluster volume set data group virt
gluster volume set data storage.owner-uid 36 && gluster volume set data storage.owner-gid 36
gluster volume start data

mkdir /gluster/iso
mkdir /gluster/iso/brick
gluster volume create iso ovirt.home.leois.cool:/gluster/iso/brick
gluster volume set iso group virt
gluster volume set iso storage.owner-uid 36 && gluster volume set iso storage.owner-gid 36
gluster volume start iso

echo "Lock=False" >> /etc/nfsmount.conf

# -------------
# Ovirt Setup
# -------------

# download CentOS 7 image so we can install it into the engine vm
mkdir /home/tmp && cd /home/tmp 
wget http://mirrors.kernel.org/centos/7/isos/x86_64/CentOS-7.0-1406-x86_64-Minimal.iso 
chown -R 36:36 /home/tmp

# start deploying the hosted engine
# FILL IN $HOSTNAME:/engine for the hosted path
# If you will be accessing VNC through OSX, make sure to use the Screen Sharing app for the VNC client
# On the engine host, run:
#  yum localinstall -y http://resources.ovirt.org/pub/yum-repo/ovirt-release35.rpm
#  yum install -y ovirt-engine
#  engine-setup
screen
hosted-engine --deploy
