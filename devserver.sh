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

# ---------------------
# INSTALL
# ---------------------

prompts() {
	echo "Let me ask you some questions first."
	echo -n "Server host name (like myserver.com):"
	read SERVER_HOST
	echo -n "Amazon S3 bucket name, for backup:"
	read S3BUCKETNAME
	echo -n "Amazon S3 access key:"
	read S3ACCESSKEY
	echo -n "Amazon S3 secret key:"
	read S3SECRETKEY
	
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
	sudo apt-get update
	sudo apt-get install -y git
	sudo apt-get install -y postfix
	sudo apt-get install -y build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate python-docutils pkg-config cmake
	sudo apt-get install -y openssh-server

	# ruby
	mkdir /tmp/ruby && cd /tmp/ruby
	curl -L --progress ftp://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.1.2.tar.gz | tar xz
	cd ruby-2.1.2
	./configure --disable-install-rdoc
	make
	sudo make install
	sudo gem install bundler --no-ri --no-rdoc

	# default git user
	sudo adduser --disabled-login --gecos 'GitLab' git

	# postgresql
	sudo apt-get install -y postgresql postgresql-client libpq-dev
	sudo rm /tmp/pgsql.conf
	sudo touch /tmp/pgsql.conf
	sudo echo "CREATE USER git CREATEDB;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE DATABASE gitlabhq_production OWNER git;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE USER gitlab_ci;" | sudo tee -a /tmp/pgsql.conf
	sudo echo "CREATE DATABASE gitlab_ci_production OWNER gitlab_ci;" | sudo tee -a /tmp/pgsql.conf

	sudo -u postgres psql -d template1 --file /tmp/pgsql.conf

	# redis
	sudo apt-get install -y redis-server
	sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.orig
	sed 's/^port .*/port 0/' /etc/redis/redis.conf.orig | sudo tee /etc/redis/redis.conf
	echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis/redis.conf
	sudo service redis-server restart
	sudo usermod -aG redis git
}

# ------------------------
# GITLAB
# ------------------------
install_gitlab() {
	cd /home/git
	sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 7-4-stable gitlab

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
	sudo -u git cp config/database.yml.postgresql config/database.yml

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
	sudo update-rc.d gitlab defaults 21
	sudo cp lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

	# Check if everything is OK
	sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production

	# Compile assets
	sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production

	sudo service gitlab start
}

# ------------------------
# Gitlab CI
# ------------------------
install_gitlab_ci() {
	sudo adduser --disabled-login --gecos 'GitLab CI' gitlab_ci
	cd /home/gitlab_ci/
	sudo -u gitlab_ci -H git clone https://gitlab.com/gitlab-org/gitlab-ci.git
	cd gitlab-ci
	sudo -u gitlab_ci -H git checkout 5-0-stable
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
	sudo update-rc.d gitlab_ci defaults 21
	sudo service gitlab_ci start
}


# ------------------------
# NGINX
# ------------------------
install_nginx() {
	sudo apt-get install -y nginx
	sudo cp /home/git/gitlab/lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
	sudo rm /etc/nginx/sites-enabled/default
	sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
	#sudo editor /etc/nginx/sites-available/gitlab
	
	# update hostname
	replace_in_file root 's/YOUR_SERVER_FQDN/$SERVER_HOST/g' /etc/nginx/sites-available/gitlab
	
	# copies nginx gitlab-ci site
	sudo cp /home/gitlab_ci/gitlab-ci/lib/support/nginx/gitlab_ci /etc/nginx/sites-available/gitlab_ci
	sudo ln -s /etc/nginx/sites-available/gitlab_ci /etc/nginx/sites-enabled/gitlab_ci
	
	# update gitlab_ci hostname and port
	replace_in_file root 's/listen 80/listen 1234/g' /etc/nginx/sites-available/gitlab_ci
	replace_in_file root 's/ci.gitlab.org/$SERVER_HOST/g' /etc/nginx/sites-available/gitlab_ci
	
	sudo service nginx restart
	
	# check if everything was installed correctly
	sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production
}

# ------------------------
# DEFAULT LINUX RUNNER
# ------------------------
install_gitlab_ci_runner() {
	sudo adduser --disabled-login --gecos 'GitLab CI Runner' gitlab_ci_runner
	cd /home/gitlab_ci_runner
	sudo -u gitlab_ci_runner -H git clone https://gitlab.com/gitlab-org/gitlab-ci-runner.git
	cd gitlab-ci-runner
	
	sudo bundle install --deployment
	sudo bundle exec /home/gitlab_ci_runner/gitlab-ci-runner/bin/setup
}

# ------------------------
# S3 BACKUP
# ------------------------
install_s3_backup_gitlab() {

	sudo -u git -H "sed 's/# keep_time: 604800/  keep_time: 604800/g' < /home/git/gitlab/config/gitlab.yml > /tmp/gitlab.yml; mv /tmp/gitlab.yml /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed 's/# upload:/  upload:/g' < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed 's/#   connection:/    connection:/g' < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed 's/#     provider:/      provider:/g' < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed 's/#     region:/      region:/g' < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed 's/#     aws_access_key_id: AKIAKIAKI/      aws_access_key_id: $S3ACCESSKEY/g' < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed \"s/#     aws_secret_access_key: 'secret123'/      aws_secret_access_key: '$S3SECRETKEY'/g\" < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	#sudo -u git -H sh -c "sed \"s/#   remote_directory: 'my.s3.bucket'/    remote_directory: '$S3BUCKETNAME'/g\" < /home/git/gitlab/config/gitlab.yml > /home/git/gitlab/config/gitlab.yml"
	
	#sudo chown -R git.git /home/git/gitlab/tmp
	#sudo -u root -H rm /etc/cron.daily/gitlab_backup.sh
	#sudo -u root -H touch /etc/cron.daily/gitlab_backup.sh
	#sudo echo "#!/bin/bash" | sudo tee -a /etc/cron.daily/gitlab_backup.sh
	#sudo echo "sudo -u git -H bundle exec rake gitlab:backup:create RAILS_ENV=production" | sudo tee -a /etc/cron.daily/gitlab_backup.sh
}


#sudo -u git -H cp /home/git/gitlab/config/gitlab.yml.example /home/git/gitlab/config/gitlab.yml
#install_s3_backup_gitlab

#install_s3_backup() {
#	sudo apt-get install python-dateutil
#	wget http://downloads.sourceforge.net/project/s3tools/s3cmd/1.5.0-rc1/s3cmd-1.5.0-rc1.tar.gz
#	sudo cp s3cmd-1.5.0-rc1.tar.gz /opt/.
#	cd /opt
#	sudo tar xvzf s3cmd-1.5.0-rc1.tar.gz
#	sudo mv s3cmd-1.5.0-rc1 s3cmd
#	sudo ln -s /opt/s3cmd/s3cmd /bin/s3cmd
#	sudo -u root -H s3cmd --configure
#	sudo -u root -H rm /etc/cron.daily/s3backup.sh
#	sudo -u root -H touch /etc/cron.daily/s3backup.sh
#	sudo echo "#!/bin/bash" | sudo tee -a /etc/cron.daily/s3backup.sh
#	sudo echo "S3BUCKETNAME=PUT_YOUR_S3_BUCKET_NAME_HERE!!" | sudo tee -a /etc/cron.daily/s3backup.sh
#	sudo echo "DOW=$(date +%u)" | sudo tee -a /etc/cron.daily/s3backup.sh
#	sudo echo "tar -zcvf /tmp/repositories-$DOW.tar /home/git/repositories/" | sudo tee -a /etc/cron.daily/s3backup.sh
#	sudo echo "s3cmd put /tmp/repositories-$DOW.tar s3://$S3BUCKETNAME/" | sudo tee -a /etc/cron.daily/s3backup.sh	
#}

prompts
#install_dependencies
#install_gitlab
#install_gitlab_ci
#install_nginx
install_gitlab_ci_runner


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
echo "  URL: http://$SERVER_HOST:1234"
echo "  Use the same password as gitlab"