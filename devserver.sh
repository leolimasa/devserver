# ---------------------
# INSTALL
# ---------------------

# AJENTI
wget https://raw.github.com/Eugeny/ajenti/master/scripts/install-ubuntu.sh
sudo sh install-ubuntu.sh

# GITLAB
sudo apt-get install git
wget https://downloads-packages.s3.amazonaws.com/ubuntu-14.04/gitlab_7.3.1-omnibus-1_amd64.deb
sudo apt-get install openssh-server
sudo dpkg -i gitlab_7.3.1-omnibus-1_amd64.deb
sudo -e /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure

# NODEJS
sudo apt-get install build-essential
curl -sL https://deb.nodesource.com/setup | sudo bash -
sudo apt-get install nodejs

# STRIDER
sudo apt-get install mongodb
sudo npm install -g strider
echo "Now we will be setting up a user for strider."
strider addUser
sudo touch /etc/init/strider.conf
echo "start on runlevel [2345]" | sudo tee -a /etc/init/strider.conf 
echo "stop on runlevel [016]" | sudo tee -a /etc/init/strider.conf
echo "respawn" | sudo tee -a /etc/init/strider.conf
echo "exec strider" | sudo tee -a /etc/init/strider.conf
sudo start strider

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
echo "Strider"
echo "  URL: http://localhost:3000"


# --------------------
# CONFIG
# --------------------
#HOSTNAME='myhost.com'
#sudo -e /etc/gitlab/gitlab.rb
#sudo gitlab-ctl reconfigure
