# ---------------------
# INSTALL
# ---------------------

# AJENTI
wget https://raw.github.com/Eugeny/ajenti/master/scripts/install-ubuntu.sh
sudo sh install-ubuntu.sh

# ------------------------
# DEPENDENCIES
# ------------------------
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

# ------------------------
# GITLAB
# ------------------------
cd /home/git
sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 7-4-stable gitlab

# Go to GitLab installation folder
cd /home/git/gitlab

# Copy the example GitLab config
sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

# Update GitLab config file, follow the directions at top of file
sudo -u git -H editor config/gitlab.yml

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

# ------------------------
# Gitlab CI
# ------------------------
sudo adduser --disabled-login --gecos 'GitLab CI' gitlab_ci
cd /home/gitlab_ci/
sudo -u gitlab_ci -H git clone https://gitlab.com/gitlab-org/gitlab-ci.git
cd gitlab-ci
sudo -u gitlab_ci -H git checkout 5-0-stable
sudo -u gitlab_ci -H cp config/application.yml.example config/application.yml
sudo -u gitlab_ci -H editor config/application.yml

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
sudo -u gitlab_ci -H editor config/unicorn.rb
# TODO change unicorn port to 9090

# Setup schedules
sudo -u gitlab_ci -H bundle exec whenever -w RAILS_ENV=production

# init scripts
sudo cp /home/gitlab_ci/gitlab-ci/lib/support/init.d/gitlab_ci /etc/init.d/gitlab_ci
sudo update-rc.d gitlab_ci defaults 21
sudo service gitlab_ci start

# ------------------------
# NGINX
# ------------------------
sudo apt-get install -y nginx
sudo cp /home/git/gitlab/lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo rm /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sudo editor /etc/nginx/sites-available/gitlab
# TODO change default gitlab host
sudo cp /home/gitlab_ci/gitlab-ci/lib/support/nginx/gitlab_ci /etc/nginx/sites-available/gitlab_ci
sudo ln -s /etc/nginx/sites-available/gitlab_ci /etc/nginx/sites-enabled/gitlab_ci
# TODO change default gitlab host
# TODO change default gitlab port

sudo service nginx restart

# check if everything was installed correctly
sudo -u git -H bundle exec rake gitlab:check RAILS_ENV=production

# ------------------------
# DEFAULT LINUX RUNNER
# ------------------------


# sudo -e /etc/gitlab/gitlab.rb
# sudo gitlab-ctl reconfigure

# GITLAB-CI
# sudo adduser --disabled-login --gecos 'GitLab CI' gitlab_ci
# sudo apt-get install postgresql

# NODEJS
# sudo apt-get install build-essential
# curl -sL https://deb.nodesource.com/setup | sudo bash -
#sudo apt-get install nodejs

# STRIDER
# sudo apt-get install mongodb
# sudo npm install -g strider
# echo "Now we will be setting up a user for strider."
# strider addUser -l root@localhost -p "admin" -a
# sudo touch /etc/init/strider.conf
# echo "start on runlevel [2345]" | sudo tee -a /etc/init/strider.conf
# echo "stop on runlevel [016]" | sudo tee -a /etc/init/strider.conf
# echo "respawn" | sudo tee -a /etc/init/strider.conf
# echo "exec strider" | sudo tee -a /etc/init/strider.conf
# sudo npm install -g nodefourtytwo/strider-gitlab
# sudo start strider

# Insert the private token from gitlab into strider
# curl http://fruitpunch.leo-sa.com:1234/api/v3/session --data 'login=root&password=5iveL!fe'
# TODO


echo "Dev server installation done."
echo ""
echo "Ajenti"
echo "  URL: https://localhost:8000"
echo "  Login/Password: root/admin"
echo ""
echo "Gitlab"
echo "  URL: http://localhost"
echo "  Login/Password: root/5iveL!fe"
echo ""
echo "Gitlab CI"
echo "  URL: http://localhost:3000"
echo "  Login/Password: root@localhost/admin"


# --------------------
# CONFIG
# --------------------
#HOSTNAME='myhost.com'
#sudo -e /etc/gitlab/gitlab.rb
#sudo gitlab-ctl reconfigure
