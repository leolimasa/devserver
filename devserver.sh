#!/bin/bash

replace_in_file() {
	# $1 = username
	# $2 = sed line
	# $3 = filepath
	sudo sh -c "sed '$2' < $3 > /tmp/replace.txt"
	chmod o+rw /tmp/replace.txt
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
	yum install epel-release sudo systemctl -y

	# devtools
	yum install -y git
	
	# disable apache
}

install_haskell() {
    #wget https://haskell.org/platform/download/7.10.2/haskell-platform-7.10.2-a-unknown-linux-deb7.tar.gz
    #tar xf haskell-platform-7.10.2-a-unknown-linux-deb7.tar.gz
    #./install-haskell-platform.sh
    #yum install -y haskell-platform
    #cabal install cabal-install
    yum install -y openssl
    eval "$( curl -sL https://github.com/mietek/halcyon/raw/master/setup.sh )"
    halcyon install --ghc-version=7.10.1 --cabal-version=1.22.6.0
    cabal update
}

install_gitlab() {
	# dependencies
	sudo yum -y install crontab curl openssh-server policycoreutils
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
	configure_gitlab_ci
	sudo gitlab-ctl reconfigure
}

configure_gitlab_ci() {
	echo "ci_external_url 'http://ci.leo-sa.com'" >> /etc/gitlab/gitlab.rb
}

install_gitlab_ci_runner() {
	curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-ci-multi-runner/script.rpm.sh | sudo bash
	yum install gitlab-ci-multi-runner -y
	sudo gitlab-ci-multi-runner register
}

install_gdrive() {
	wget https://drive.google.com/uc?id=0B3X9GlR6Embnb095MGxEYmJhY2c -O drive
	sudo install drive /usr/sbin/drive
	sudo drive
}

setup_gdrive_cron() { 
	touch /etc/cron.daily/gitlab.cron
	chmod ug+rwx /etc/cron.daily/gitlab.cron
	echo "#!/bin/bash" >> /etc/cron.daily/gitlab.cron
	echo "gitlab-rake gitlab:backup:create" >> /etc/cron.daily/gitlab.cron
	echo "drive upload --file /var/opt/gitlab/backups" >> /etc/cron.daily/gitlab.cron
	systemctl start crond
}

system_setup
install_gitlab
install_haskell
install_gdrive
setup_gdrive_cron
install_gitlab_ci_runner

echo "Dev server installation done."
echo ""
echo "Gitlab"
echo "  Login/Password: root/5iveL!fe"
echo "Gitlab CI"
echo "  ci.leo-sa.com"

