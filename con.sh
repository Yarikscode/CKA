#!/bin/bash

# Проверка: уже запускался?
if [ -f /tmp/container.txt ]; then
    echo "⚠️ containerd уже установлен (файл container.txt найден)"
    exit 0
fi

# Установка зависимостей
dnf install -y curl wget tar jq yum-utils device-mapper-persistent-data lvm2

# Добавление Docker репозитория (для containerd)
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Заменяем $releasever на 9, так как 10 не поддерживается напрямую
sed -i 's/\$releasever/9/' /etc/yum.repos.d/docker-ce.repo

# Установка containerd
dnf install -y containerd.io

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

# Генерация и правка конфига containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Включаем поддержку systemd cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Запуск и автозапуск containerd
systemctl daemon-reload
systemctl enable --now containerd

# Завершение
touch /tmp/container.txt
echo "✅ containerd установлен и запущен"
exit 0

