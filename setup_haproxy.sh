#!/bin/bash
#
# source https://github.com/sandervanvugt/cka/setup-lb.sh

# script to set up load balancing on cluster nodes
# for use in CKA courses by Sander van Vugt
# version 0.7
# currently only tested on Ubuntu 22.04 LTS Server
# run this AFTER running setup-container.sh and setup-kubetools.sh
#
# TODO: remove the many password prompts

if which kubectl
then
	echo all good moving on
else
	echo please run setup-container.sh and setup-kubetools.sh first and then run this again
	exit 6
fi

## establish key based SSH with remote hosts
# obtain node information
if grep master /etc/hosts | grep -v 127
then
	export master_IP=$(awk '/master/ { print $1 }' /etc/hosts | grep -v 127)
else
	echo enter IP address for master
	read master_IP
	export master_IP=$master_IP
	sudo sh -c "echo $master_IP master >> /etc/hosts"
fi


if grep master2 /etc/hosts | grep -v 127
then
        export master2_IP=$(awk '/master2/ { print $1 }' /etc/hosts | grep -v 127)
else
        echo enter IP address for master2
        read master2_IP
        export master2_IP=$master2_IP
        sudo sh -c "echo $master2_IP master2 >> /etc/hosts"
fi


if grep master3 /etc/hosts | grep -v 127
then
        export master3_IP=$(awk '/master3/ { print $1 }' /etc/hosts | grep -v 127)
else
        echo enter IP address for master3
        read master3_IP
        export master3_IP=$master3_IP
        sudo sh -c "echo $master3_IP master3 >> /etc/hosts"
fi


echo ##### READ ALL OF THIS BEFORE CONTINUING ######
echo this script requires you to run setup-container.sh and setup-kubetools.sh first
echo this script is based on the NIC name ens33
echo if your networkcard has a different name, edit keepalived.conf
echo before continuing and change "interface ens33" to match your config
echo .
echo this script will create a keepalived apiserver at 192.168.29.100
echo if this IP address does not match your network configuration,
echo manually change the check_apiserver.sh file before continuing
echo also change the IP address in keepalived.conf
echo .
echo press enter to continue or Ctrl-c to interrupt and apply modifications
read

# performing check on critical files
for i in keepalived.conf check_apiserver.sh haproxy.cfg
do
	if [ ! -f $i ]
	then
		echo $i should exist in the current directory && exit 2
	fi
done

# generating and distributing SSH keys
ssh-keygen
ssh-copy-id master
ssh-copy-id master2
ssh-copy-id master3

# configuring sudo for easier access
sudo sh -c "echo 'Defaults timestamp_type=global,timestamp_timeout=60' >> /etc/sudoers"
sudo scp -p /etc/sudoers $USER@master2:/tmp/ && ssh -t master2 'sudo -S chown root:root /tmp/sudoers' && ssh -t master2 'sudo -S cp -p /tmp/sudoers /etc/'
sudo scp -p /etc/sudoers $USER@master3:/tmp/ && ssh -t master3 'sudo -S chown root:root /tmp/sudoers' && ssh -t master3 'sudo -S cp -p /tmp/sudoers /etc/'
#ssh master2 sudo -S sh -c "echo 'Defaults timestamp_type=global,timestamp_timeout=60' >> /etc/sudoers"
#ssh master3 sudo -S sh -c "echo 'Defaults timestamp_type=global,timestamp_timeout=60' >> /etc/sudoers"

# install required software
sudo dnf remove -y haproxy keepalived
ssh master2 "sudo -S dnf remove -y haproxy keepalivedy"
ssh master3 "sudo -S dnf remove -y haproxy keepalivedy"

scp /etc/hosts master2:/tmp && ssh -t master2 'sudo -S cp /tmp/hosts /etc/'
scp /etc/hosts master3:/tmp && ssh -t master3 'sudo -S cp /tmp/hosts /etc/'

# create keepalived config
# change IP address to anything that works in your environment!
sudo chmod +x check_apiserver.sh
sudo cp check_apiserver.sh /etc/keepalived/


scp check_apiserver.sh master2:/tmp && ssh -t master2 'sudo -S cp /tmp/check_apiserver.sh /etc/keepalived'
scp check_apiserver.sh master3:/tmp && ssh -t master3 'sudo -S cp /tmp/check_apiserver.sh /etc/keepalived'

#### creating site specific keepalived.conf file
sudo cp keepalived.conf keepalived-master2.conf
sudo cp keepalived.conf keepalived-master3.conf

sudo sed -i 's/state MASTER/state SLAVE/' keepalived-master2.conf
sudo sed -i 's/state MASTER/state SLAVE/' keepalived-master3.conf
sudo sed -i 's/priority 255/priority 254/' keepalived-master2.conf
sudo sed -i 's/priority 255/priority 253/' keepalived-master3.conf

sudo cp keepalived.conf /etc/keepalived/
scp keepalived-master2.conf master2:/tmp && ssh -t master2 'sudo -S cp /tmp/keepalived-master2.conf /etc/keepalived/keepalived.conf'
scp keepalived-master3.conf master3:/tmp && ssh -t master3 'sudo -S cp /tmp/keepalived-master3.conf /etc/keepalived/keepalived.conf'

### rewriting haproxy.cfg with site specific IP addresses
sudo sed -i s/server\ master\ 1.1.1.1\:6443\ check/server\ master\ $master_IP\:6443\ check/ haproxy.cfg
sudo sed -i s/server\ master2\ 1.1.1.2\:6443\ check/server\ master2\ $master2_IP\:6443\ check/ haproxy.cfg
sudo sed -i s/server\ master3\ 1.1.1.3\:6443\ check/server\ master3\ $master3_IP\:6443\ check/ haproxy.cfg

# copy haproxy.cfg to destinations
sudo cp haproxy.cfg /etc/haproxy/
scp haproxy.cfg master2:/tmp && ssh -t master2 'sudo -S cp /tmp/haproxy.cfg /etc/haproxy/'
scp haproxy.cfg master3:/tmp && ssh -t master3 'sudo -S cp /tmp/haproxy.cfg /etc/haproxy/'

# start and enable services
sudo systemctl enable keepalived --now
sudo systemctl enable haproxy --now
ssh master2 sudo -S systemctl enable keepalived --now
ssh master2 sudo -S systemctl enable haproxy --now
ssh master3 sudo -S systemctl enable keepalived --now
ssh master3 sudo -S systemctl enable haproxy --now

echo setup is now done, please verify
echo the first node that started the services - normally master -  should run the virtual IP address 192.168.31.100
