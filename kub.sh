#!/bin/bash

# Проверка: уже запускался?
if [ -f /tmp/k8s_installed ]; then
    echo "⚠️ Kubernetes уже установлен (файл k8s_installed найден)"
    exit 0
fi

echo "🚀 НАСТРОЙКА KUBERNETES НА CENTOS STREAM 10"

# Отключаем swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# Загружаем модуль ядра
modprobe br_netfilter

# Настройка sysctl
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1
EOF

sysctl --system

# Установка зависимостей
dnf install -y curl wget jq yum-utils device-mapper-persistent-data lvm2

# Добавление рабочего репозитория Kubernetes (v1.30)
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools
EOF

# Установка компонентов Kubernetes
dnf install -y kubelet kubeadm kubectl cri-tools --disableexcludes=kubernetes

#Указываем enpoint для CRI
cat <<EOF > /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF


# Включаем и запускаем kubelet
systemctl daemon-reexec
systemctl enable --now kubelet

# Пометка завершения
touch /tmp/k8s_installed

echo "✅ Kubernetes установлен (v1.30)"
echo
echo "➡️ На управляющем узле запусти:"
echo "   sudo kubeadm init --pod-network-cidr=192.168.0.0/16"
echo
echo "➡️ После инициализации установи Calico:"
echo "   kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
echo
echo "➡️ На воркерах:"
echo "   sudo kubeadm join ..."

