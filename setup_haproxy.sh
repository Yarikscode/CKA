#!/bin/bash

# Check for kubectl
if which kubectl; then
  echo all good moving on
else
  echo please run setup-container.sh and setup-kubetools.sh first and then run this again
  exit 6
fi

# Node IP collection
if grep master /etc/hosts | grep -v 127; then
  export master_IP=$(awk '/master/ { print $1 }' /etc/hosts | grep -v 127)
else
  echo enter IP address for master
  read master_IP
  sudo sh -c "echo $master_IP master >> /etc/hosts"
fi

if grep master2 /etc/hosts | grep -v 127; then
  export master2_IP=$(awk '/master2/ { print $1 }' /etc/hosts | grep -v 127)
else
  echo enter IP address for master2
  read master2_IP
  sudo sh -c "echo $master2_IP master2 >> /etc/hosts"
fi

if grep master3 /etc/hosts | grep -v 127; then
  export master3_IP=$(awk '/master3/ { print $1 }' /etc/hosts | grep -v 127)
else
  echo enter IP address for master3
  read master3_IP
  sudo sh -c "echo $master3_IP master3 >> /etc/hosts"
fi

# Warnings
cat <<EOF
##### READ ALL OF THIS BEFORE CONTINUING #####
- This script requires you to run setup-container.sh and setup-kubetools.sh first
- It's based on NIC name ens33 — change it in keepalived.conf if needed
- It creates a keepalived apiserver at 192.168.31.100 — adjust config files if your network differs
Press Enter to continue or Ctrl-C to abort
EOF
read

# Critical file check
for i in keepalived.conf check_apiserver.sh haproxy.cfg; do
  [ ! -f $i ] && echo "$i should exist in the current directory" && exit 2
done

# Generate SSH key if not exists
[ ! -f ~/.ssh/id_rsa.pub ] && ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# Copy SSH key to nodes
for host in master master2 master3; do
  ssh-copy-id -i ~/.ssh/id_rsa.pub $USER@$host
done

# Ensure required directories and packages on remote nodes
for host in master2 master3; do
  ssh -i ~/.ssh/id_rsa $USER@$host 'sudo mkdir -p /etc/keepalived /etc/haproxy'
  ssh -i ~/.ssh/id_rsa $USER@$host 'sudo dnf install -y haproxy keepalived'
done

# Local package installation
sudo dnf install -y haproxy keepalived
sudo mkdir -p /etc/keepalived /etc/haproxy

# Distribute /etc/hosts
for host in master2 master3; do
  scp -i ~/.ssh/id_rsa /etc/hosts $USER@$host:/tmp/
  ssh -i ~/.ssh/id_rsa $USER@$host 'sudo cp /tmp/hosts /etc/'
done

# Copy and configure keepalived script
sudo chmod +x check_apiserver.sh
sudo cp check_apiserver.sh /etc/keepalived/
for host in master2 master3; do
  scp -i ~/.ssh/id_rsa check_apiserver.sh $USER@$host:/tmp/
  ssh -i ~/.ssh/id_rsa $USER@$host 'sudo cp /tmp/check_apiserver.sh /etc/keepalived/'
done

# Adjust keepalived confs
sudo cp keepalived.conf keepalived-master2.conf
sudo cp keepalived.conf keepalived-master3.conf
sudo sed -i 's/state MASTER/state SLAVE/' keepalived-master2.conf
sudo sed -i 's/state MASTER/state SLAVE/' keepalived-master3.conf
sudo sed -i 's/priority 255/priority 254/' keepalived-master2.conf
sudo sed -i 's/priority 255/priority 253/' keepalived-master3.conf
sudo cp keepalived.conf /etc/keepalived/
scp -i ~/.ssh/id_rsa keepalived-master2.conf $USER@master2:/tmp/
scp -i ~/.ssh/id_rsa keepalived-master3.conf $USER@master3:/tmp/
ssh -i ~/.ssh/id_rsa $USER@master2 'sudo cp /tmp/keepalived-master2.conf /etc/keepalived/keepalived.conf'
ssh -i ~/.ssh/id_rsa $USER@master3 'sudo cp /tmp/keepalived-master3.conf /etc/keepalived/keepalived.conf'

# Проверка, что master_IP содержит только первый IP
readarray -t ip_lines <<< "$master_IP"
master_IP="${ip_lines[0]}"
master2_IP="${ip_lines[1]}"
master3_IP="${ip_lines[2]}"

# Проверка IP
[ -z "$master_IP" ] && echo "master_IP is empty" && exit 1
[ -z "$master2_IP" ] && echo "master2_IP is empty" && exit 1
[ -z "$master3_IP" ] && echo "master3_IP is empty" && exit 1

# Экранирование для sed
escape_ip() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

escaped_master_IP=$(escape_ip "$master_IP")
escaped_master2_IP=$(escape_ip "$master2_IP")
escaped_master3_IP=$(escape_ip "$master3_IP")

# Замена IP в конфиге
sudo sed -i "s/server master 1.1.1.1:6443 check/server master $escaped_master_IP:6443 check/" haproxy.cfg
sudo sed -i "s/server master2 1.1.1.2:6443 check/server master2 $escaped_master2_IP:6443 check/" haproxy.cfg
sudo sed -i "s/server master3 1.1.1.3:6443 check/server master3 $escaped_master3_IP:6443 check/" haproxy.cfg

# Distribute haproxy.cfg
sudo cp haproxy.cfg /etc/haproxy/
scp -i ~/.ssh/id_rsa haproxy.cfg $USER@master2:/tmp/
scp -i ~/.ssh/id_rsa haproxy.cfg $USER@master3:/tmp/
ssh -i ~/.ssh/id_rsa $USER@master2 'sudo cp /tmp/haproxy.cfg /etc/haproxy/'
ssh -i ~/.ssh/id_rsa $USER@master3 'sudo cp /tmp/haproxy.cfg /etc/haproxy/'

# Start services
sudo systemctl enable keepalived --now
sudo systemctl enable haproxy --now
for host in master2 master3; do
  ssh -i ~/.ssh/id_rsa $USER@$host 'sudo systemctl enable keepalived --now && sudo systemctl enable haproxy --now'
done

echo setup is now done, please verify
echo the first node that started the services - normally master -  should run the virtual IP address 192.168.31.100
