#!/bin/bash

# Проверка: уже запускался?
if [ -f /tmp/container.txt ]; then
    echo "containerd уже установлен (файл container.txt найден)"
    exit 0
fi

# Определение архитектуры
[ "$(arch)" = aarch64 ] && PLATFORM=arm64
[ "$(arch)" = x86_64 ] && PLATFORM=amd64

# Установка зависимостей
dnf install -y curl wget tar jq

# Настройка модулей ядра
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Настройка sysctl
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.forwarding = 1
EOF

sysctl --system

# Скачивание containerd
CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name')
CONTAINERD_VERSION=${CONTAINERD_VERSION#v}

wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
tar xvf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz -C /usr/local

# Создание конфига containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Включение systemd cgroup в config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Установка runc
RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')
wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
install -m 755 runc.${PLATFORM} /usr/local/sbin/runc

# Установка systemd unit для containerd
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mv containerd.service /usr/lib/systemd/system/

systemctl daemon-reload
systemctl enable --now containerd

# Завершение
touch /tmp/container.txt

echo "containerd установлен и запущен"
exit 0
