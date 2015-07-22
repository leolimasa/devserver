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

# AJENTI
install_ajenti() {
	wget https://raw.github.com/Eugeny/ajenti/master/scripts/install-ubuntu.sh
	sudo sh install-ubuntu.sh
}

# ------------------------
# DEPENDENCIES
# ------------------------
install_dependencies() {
	sudo yum -y install epel-release
	sudo yum -y update
	sudo yum -y install wget
	sudo yum -y install vim
	sudo yum -y install git
	sudo yum -y install postfix
	sudo yum -y install policycoreutils-python
	sudo yum -y groupinstall "Development Tools"
	sudo yum -y install kernel-devel kernel-headers
	sudo yum -y install python
	yum -y install nginx zlib-devel openssl-devel git redis perl-CPAN ncurses-devel gdbm-devel glibc-devel tcl-devel curl-devel byacc db4-devel sqlite-devel libxml2 libxml2-devel libffi libffi-devel libxslt libxslt-devel libyaml libyaml-devel libicu libicu-devel system-config-firewall-tui sudo wget crontabs gettext perl-Time-HiRes cmake gettext-devel readline readline-devel libcom_err-devel.i686 libcom_err-devel.x86_64 expat-devel logwatch logrotate patch
	yum install -y gcc-c++ patch readline readline-devel zlib zlib-devel libyaml-devel libffi-devel openssl-devel
	yum install -y make bzip2
	yum install -y iconv-devel

	# default git user
	sudo adduser git
	
	# fix the usr/local/bin
	cp /etc/sudoers /etc/sudoers.bkup
	#replace_in_file root 's/secure_path = \/sbin:\/bin:\/usr\/sbin:\/usr\/bin/secure_path = \/sbin:\/bin:\/usr\/sbin:\/usr\/bin:\/usr\/local\/bin/g' /etc/sudoers
}

install_postgresql() {
	sudo yum -y install postgresql postgresql-devel postgresql-server
	sudo rm /tmp/pgsql.conf
	sudo touch /tmp/pgsql.conf
	sudo echo "CREATE USER git CREATEDB;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE DATABASE gitlabhq_production OWNER git;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE USER gitlab_ci;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE DATABASE gitlab_ci_production OWNER gitlab_ci;" | sudo tee -a /tmp/pgsql.conf

	service postgresql initdb
	service postgresql start
	chkconfig postgresql on
	sudo -u postgres psql -d template1 --file /tmp/pgsql.conf	
}

install_ruby() {
	mkdir /tmp/ruby && cd /tmp/ruby
	curl -L --progress ftp://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.1.5.tar.gz | tar xz
	cd ruby-2.1.5
	./configure --disable-install-rdoc
	make
	sudo make install
	
	# ruby gems
	wget http://production.cf.rubygems.org/rubygems/rubygems-2.4.8.tgz
	tar -zxvf rubygems-2.4.8.tgz
	cd rubygems-2.4.8
	ruby setup.rb
	gem install bundler --no-rdoc
}


install_redis() {
	wget -r --no-parent -A 'epel-release-*.rpm' http://dl.fedoraproject.org/pub/epel/7/x86_64/e/
	rpm -Uvhy dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-*.rpm
	sudo yum install -y redis
	sudo usermod -aG redis git
	sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.orig
	sed 's/^port .*/port 0/' /etc/redis.conf | sudo tee /etc/redis/redis.conf
	echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis.conf
	echo -e 'unixsocketperm 0770' | sudo tee -a /etc/redis.conf
	mkdir /var/run/redis
	chown redis:redis /var/run/redis
	chmod 755 /var/run/redis
	sudo service redis start
}
	

# ------------------------
# GITLAB
# ------------------------
install_gitlab() {
	yum -y groupinstall 'Development Tools'
	yum -y install readline readline-devel ncurses-devel gdbm-devel glibc-devel tcl-devel openssl-devel curl-devel expat-devel db4-devel byacc sqlite-devel libyaml libyaml-devel libffi libffi-devel libxml2 libxml2-devel libxslt libxslt-devel libicu libicu-devel system-config-firewall-tui redis sudo wget crontabs logwatch logrotate perl-Time-HiRes git cmake libcom_err-devel.i686 libcom_err-devel.x86_64
	
	cd /home/git
	sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 7-13-stable gitlab

	# Go to GitLab installation folder
	cd /home/git/gitlab

	# Copy the example GitLab config
	sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

	# Update GitLab config file with our hosts
	replace_in_file git "s/host: localhost/host: $SERVER_HOST/g" /home/git/gitlab/config/gitlab.yml

	# Make sure GitLab can write to the log/ and tmp/ directories
	sudo chown -R git log/
	sudo chown -R git tmp/
	sudo chmod -R u+rwX log/
	sudo chmod -R u+rwX tmp/
	
	# Create directory for satellites
	sudo -u git -H mkdir /home/git/gitlab-satellites
	sudo chmod u+rwx,g=rx,o-rwx /home/git/gitlab-satellites

	# Make sure GitLab can write to the tmp/pids/ and tmp/sockets/ directories
	sudo chmod -R u+rwX tmp/pids/
	sudo chmod -R u+rwX tmp/sockets/

	# Make sure GitLab can write to the public/uploads/ directory
	sudo chmod -R u+rwX  public/uploads

	# Copy the example Unicorn config
	sudo -u git -H cp config/unicorn.rb.example config/unicorn.rb

	# Copy the example Rack attack config
	sudo -u git -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

	# Configure Git global settings for git user, useful when editing via web
	# Edit user.email according to what is set in gitlab.yml
	sudo -u git -H git config --global user.name "GitLab"
	sudo -u git -H git config --global user.email "example@example.com"
	sudo -u git -H git config --global core.autocrlf input

	# Configure Redis connection settings
	sudo -u git -H cp config/resque.yml.example config/resque.yml

	# PostgreSQL only:
	sudo -u git -H cp config/database.yml.postgresql config/database.yml

	# Make config/database.yml readable to git only
	sudo -u git -H chmod o-rwx config/database.yml

	# Install ruby bundle
	sudo -u git -H bundle install --deployment --without development test mysql aws

	# Run the installation task for gitlab-shell (replace `REDIS_URL` if needed):
	sudo -u git -H bundle exec rake gitlab:shell:install[v2.0.1] REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production

	# Initialize database
	sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production

	# Init and logging
	sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab
	#sudo update-rc.d gitlab defaults 21
	sudo cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

	# Check if everything is OK
	sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production

	# Compile assets
	sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production
	
	# Add init script
	wget -O /etc/init.d/gitlab https://gitlab.com/gitlab-org/gitlab-recipes/raw/master/init/sysvinit/centos/gitlab-unicorn
	chmod +x /etc/init.d/gitlab
	chkconfig --add gitlab

	# Fire it up
	sudo service gitlab start
}

# ------------------------
# Gitlab CI
# ------------------------
install_gitlab_ci() {
	sudo adduser gitlab_ci
	cd /home/gitlab_ci/
	sudo -u gitlab_ci -H git clone https://gitlab.com/gitlab-org/gitlab-ci.git
	cd gitlab-ci
	sudo -u gitlab_ci -H git checkout 7-13-stable
	sudo -u gitlab_ci -H cp config/application.yml.example config/application.yml

	# edit configuration file
	replace_in_file gitlab_ci "s/host: localhost/host: $SERVER_HOST/g" /home/gitlab_ci/gitlab-ci/config/application.yml
	replace_in_file gitlab_ci "s/port: 80/port: 1234/g" /home/gitlab_ci/gitlab-ci/config/application.yml
	replace_in_file gitlab_ci "s/https:\/\/gitlab.example.com\//http:\/\/$SERVER_HOST/g" /home/gitlab_ci/gitlab-ci/config/application.yml

	# Create socket and pid directories
	sudo -u gitlab_ci -H mkdir -p tmp/sockets/
	sudo chmod -R u+rwX  tmp/sockets/
	sudo -u gitlab_ci -H mkdir -p tmp/pids/
	sudo chmod -R u+rwX  tmp/pids/

	sudo -u gitlab_ci -H bundle install --without development test mysql --deployment

	# setup db
	sudo -u gitlab_ci -H cp config/database.yml.postgresql config/database.yml

	# Setup tables
	sudo -u gitlab_ci -H bundle exec rake setup RAILS_ENV=production

	# Edit web server settings
	sudo -u gitlab_ci -H cp config/unicorn.rb.example config/unicorn.rb
	#sudo -u gitlab_ci -H editor config/unicorn.rb
	
	# change unicorn port to 9090 so it doesn't conflict with gitlab's
	replace_in_file gitlab_ci 's/127.0.0.1:8080/127.0.0.1:9090/g' /home/gitlab_ci/gitlab-ci/config/unicorn.rb
	
	# Setup schedules
	sudo -u gitlab_ci -H bundle exec whenever -w RAILS_ENV=production

	# init scripts
	sudo cp /home/gitlab_ci/gitlab-ci/lib/support/init.d/gitlab_ci /etc/init.d/gitlab_ci
	chkconfig --add gitlab_ci
	sudo service gitlab_ci start
	
	# setup nginx
	
}


# ------------------------
# NGINX
# ------------------------
install_nginx() {
	sudo yum install -y nginx nodejs
	chkconfig nginx on
	wget -O /etc/nginx/conf.d/gitlab.conf https://gitlab.com/gitlab-org/gitlab-ce/raw/master/lib/support/nginx/gitlab
	usermod -a -G git nginx
	usermod -a -G gitlab_ci nginx
	chmod -R g+rx /home/gitlab_ci
	
	# poke a hole through se linux
	semanage port -a -t http_port_t -p tcp 2222
	
	# change default port
	cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bkup
	replace_in_file root 's/80 default_server/81 default_server/g' /etc/nginx/nginx.conf
	
	# gitlab
	chmod -R g+rx /home/git/
	replace_in_file root 's/YOUR_SERVER_FQDN/$SERVER_HOST/g' /etc/nginx/conf.d/gitlab.conf
	
	# gitlab ci
	sudo cp /home/gitlab_ci/gitlab-ci/lib/support/nginx/gitlab_ci /etc/nginx/conf.d/gitlab_ci.conf
	replace_in_file root 's/listen 80/listen 2222/g' /etc/nginx/conf.d/gitlab_ci.conf
	replace_in_file root 's/ci.gitlab.org/$SERVER_HOST/g' /etc/nginx/conf.d/gitlab_ci.conf
	
	systemctl start nginx
	lokkit -s http 
	
	# this ain't good. Fix later
	setenforce 0
	
	service iptables restart
	
	#sudo cp /home/git/gitlab/lib/support/nginx/gitlab-ssl /etc/nginx/sites-available/gitla
	#sudo rm /etc/nginx/sites-enabled/default
	#sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
	#sudo editor /etc/nginx/sites-available/gitlab
	
	# update hostname
	# replace_in_file root 's/YOUR_SERVER_FQDN/$SERVER_HOST/g' /etc/nginx/sites-available/gitlab
	
	# copies nginx gitlab-ci site
	# sudo cp /home/gitlab_ci/gitlab-ci/lib/support/nginx/gitlab_ci /etc/nginx/sites-available/gitlab_ci
	# sudo ln -s /etc/nginx/sites-available/gitlab_ci /etc/nginx/sites-enabled/gitlab_ci
	
	# update gitlab_ci hostname and port
	# replace_in_file root 's/listen 80/listen 1234/g' /etc/nginx/sites-available/gitlab_ci
	# replace_in_file root 's/ci.gitlab.org/$SERVER_HOST/g' /etc/nginx/sites-available/gitlab_ci
}

# ------------------------
# DEFAULT LINUX RUNNER
# ------------------------
install_gitlab_ci_runner() {
	sudo adduser --shell /usr/sbin/nologin gitlab_ci_runner
	cd /home/gitlab_ci_runner
	sudo -u gitlab_ci_runner -H git clone https://gitlab.com/gitlab-org/gitlab-ci-runner.git
	cd gitlab-ci-runner
	
	sudo bundle install --deployment
	sudo bundle exec /home/gitlab_ci_runner/gitlab-ci-runner/bin/setup
	sudo cp ./lib/support/init.d/gitlab_ci_runner /etc/init.d/gitlab-ci-runner
	sudo chmod +x /etc/init.d/gitlab-ci-runner
	chkconfig --add gitlab-ci-runner
	sudo systemctl start gitlab-ci-runner
}

# ------------------------
# S3 BACKUP
# ------------------------
configure_s3_backup_gitlab() {

	replace_in_file git "s/# keep_time: 604800/keep_time: 604800/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/# upload:/upload:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#   connection:/    connection:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#     provider:/      provider:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#     region:/      region:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#     aws_access_key_id: AKIAKIAKI/      aws_access_key_id: $S3ACCESSKEY/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#     aws_secret_access_key:/      aws_secret_access_key:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/#   remote_directory:/    remote_directory:/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/secret123/$S3SECRETKEY/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/my\.s3\.bucket/$S3BUCKETNAME/g" /home/git/gitlab/config/gitlab.yml
	replace_in_file git "s/eu-west-1/$S3REGION/g" /home/git/gitlab/config/gitlab.yml
	
	
	sudo chown -R git.git /home/git/gitlab/tmp
	sudo -u root -H rm /etc/cron.daily/gitlab_backup.sh
	sudo -u root -H touch /etc/cron.daily/gitlab_backup.sh
	sudo echo "#!/bin/bash" | sudo tee -a /etc/cron.daily/gitlab_backup.sh
	sudo echo "cd /home/git/gitlab" | sudo tee -a /etc/cron.daily/gitlab_backup.sh
	sudo echo "sudo -u git -H bundle exec rake gitlab:backup:create RAILS_ENV=production" | sudo tee -a /etc/cron.daily/gitlab_backup.sh
	sudo chmod +x /etc/cron.daily/gitlab_backup.sh
}

# ------------------------
# EMAIL RELAY
# ------------------------
configure_email_relay() {
	EMAILCFG=/home/git/gitlab/config/initializers/smtp_settings.rb
	replace_in_file git "s/:sendmail/:smtp/g" /home/git/gitlab/config/environments/production.rb
	sudo -u git rm $EMAILCFG
	sudo -u git touch $EMAILCFG
	append_to_file 'if Rails.env.production?' $EMAILCFG
	append_to_file '  Gitlab::Application.config.action_mailer.delivery_method = :smtp' $EMAILCFG
	append_to_file '' $EMAILCFG
	append_to_file '  ActionMailer::Base.smtp_settings = {' $EMAILCFG
    append_to_file '    address: "email.server.com",' $EMAILCFG
    append_to_file '    port: 456,' $EMAILCFG
    append_to_file '    user_name: "smtp",' $EMAILCFG
    append_to_file '    password: "123456",' $EMAILCFG
    append_to_file '    domain: "gitlab.company.com",' $EMAILCFG
    append_to_file '    authentication: :login,' $EMAILCFG
    append_to_file '    enable_starttls_auto: true' $EMAILCFG
	append_to_file '  }' $EMAILCFG
	append_to_file 'end'
}

# ------------------------
# DROPBOX CONFIGURATION
# ------------------------
install_dropbox() {
	cd ~ && wget -O - "https://www.dropbox.com/download?plat=lnx.x86_64" | tar xzf -	
	mkdir -p ~/bin && wget -O ~/bin/dropbox.py "https://www.dropbox.com/download?dl=packages/dropbox.py" && chmod +x ~/bin/dropbox.py
	sudo su -c '~/.dropbox-dist/dropboxd'
	~/bin/dropbox.py start
	~/bin/dropbox.py lansync n
	cd ~/Dropbox && ~/bin/dropbox.py exclude add *
	cd ~/Dropbox && ~/bin/dropbox.py exclude remove 'Server Backups'
}

configure_dropbox_backup() {
	echo 'Nothing to do here'
}

prompts
#install_ajenti
install_dependencies
install_ruby
install_postgresql
install_gitlab
install_gitlab_ci
install_redis
install_nginx
install_gitlab_ci_runner
#install_dropbox


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