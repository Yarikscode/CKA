#!/bin/bash

# Проверка файла container.txt
if ! [ -f /tmp/container.txt ]; then
    echo "run ./setup-container.sh before running this script"
    exit 4
fi

# Получаем ОС
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')

# Получаем версию Kubernetes
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
KUBEVERSION=${KUBEVERSION#v}  # Убираем v
KUBEVERSION_MAJOR=${KUBEVERSION%.*}

if [[ "$MYOS" == "CentOS" || "$MYOS" == "Rocky" || "$MYOS" == "AlmaLinux" ]]; then
    echo "RUNNING CENTOS-BASED CONFIG"

    # Загружаем модуль ядра
    modprobe br_netfilter

    # Конфигурация модулей
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

    # Конфигурация sysctl
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    sysctl --system

    # Установка зависимостей
    sudo dnf install -y yum-utils curl

    # Добавляем репозиторий Kubernetes
    sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBEVERSION_MAJOR}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBEVERSION_MAJOR}/rpm/repodata/repomd.xml.key
EOF

    # Устанавливаем компоненты
    sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    sudo systemctl enable kubelet

    # Отключаем swap
    swapoff -a
    sudo sed -i 's/^\(.*swap.*\)$/#\1/' /etc/fstab

else
    echo "Unsupported OS: $MYOS"
    exit 1
fi

# Настройка crictl для containerd
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

echo
echo "✅ Установка завершена."
echo "➡️ На управляющем узле запусти:"
echo "   sudo kubeadm init --pod-network-cidr=192.168.0.0/16"
echo
echo "➡️ После инициализации установи Calico:"
echo "   kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
echo
echo "➡️ На воркерах:"
echo "   sudo kubeadm join ..."
