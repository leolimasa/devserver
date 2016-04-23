#!/bin/bash
# TODO configure email server

replace_in_file() {
	# $1 = username
	# $2 = sed line
	# $3 = filepath
	sudo sh -c "sed '$2' < $3 > /tmp/replace.txt"
	sudo chmod o+rw /tmp/replace.txt
	sudo -u $1 cp /tmp/replace.txt $3
}

append_to_file() {
	sudo echo $1 | sudo tee -a $2
}

# ---------------------
# INSTALL
# ---------------------

prompts() {
	echo "Let me ask you some questions first."
	echo -n "Server host name (like myserver.com): "
	read SERVER_HOST
	echo -n "An SMTP server to relay your mail (like smtp.gmail.com): "
	read RELAYHOST
	
}

system_setup() {
	yum install epel-release -y
	
	# disable apache
}

install_gitlab() {
	# dependencies
	sudo yum -y install curl openssh-server
	sudo systemctl enable sshd
	sudo systemctl start sshd
	sudo yum -y install postfix
	sudo systemctl enable postfix
	sudo systemctl start postfix
	sudo firewall-cmd --permanent --add-service=http
	sudo systemctl reload firewalld
	
	# install the package
	curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | sudo bash
	sudo yum -y install gitlab-ce
	
	# start the server
	sudo gitlab-ctl reconfigure
}

system_setup
install_gitlab

echo "Dev server installation done."
echo ""
echo "Ajenti"
echo "  URL: https://$SERVER_HOST:8000"
echo "  Login/Password: root/admin"
echo ""
echo "Gitlab"
echo "  URL: http://$SERVER_HOST"
echo "  Login/Password: root/5iveL!fe"
echo ""
echo "Gitlab CI"
echo "  URL: http://$SERVER_HOST:2222"
echo "  Use the same password as gitlab"