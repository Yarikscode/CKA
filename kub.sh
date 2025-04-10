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

# Добавление рабочего репозитория Kubernetes (v1.31)
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
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

