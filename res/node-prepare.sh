# Configuring network
if [ -e "/etc/netplan/50-cloud-init.yaml" ]
then
	sed -i 's/mtu: 1500/mtu: 9000/' /etc/netplan/50-cloud-init.yaml
	netplan apply
else
	sed -i 's/mtu 1500/mtu 9000/'  /etc/network/interfaces.d/50-cloud-init.cfg
	systemctl restart networking
fi

sed -i 's/nameserver .*/nameserver 8.8.8.8/' /etc/resolv.conf
echo "10.1.1.2 s02" >> /etc/hosts
echo "10.1.1.3 s03" >> /etc/hosts
echo "10.1.1.4 s04" >> /etc/hosts

# Preparing apt
apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update

# Setup kube* cli
apt-get install -y kubelet kubeadm kubectl docker.io sysstat
swapoff -a
sed -i '/\sswap\s/d' /etc/fstab

# Loading docker images from cache
wget http://10.1.1.101/res/docker-images-v1.12.1.tar.gz
gunzip docker-images-v1.12.1.tar.gz
docker load --input docker-images-v1.12.1.tar

# Monitoring scripts

cat > stats.sh <<'EOF'
#!/bin/bash
COUNT=$1
tail -n$COUNT /home/ubuntu/metrics.log | \
	awk '{M+=$1;U+=$2;N+=$3;S+=$4;I+=$5;T+=$6} END {printf "%d\t=%.2f+%.2f+%.2f+%.2f+%.2f\n",M/NR,U/NR,N/NR,S/NR,I/NR,T/NR}'
EOF

cat > monit.sh <<'EOF'
#!/bin/bash

while true
do
	echo "$(sleep 1;free -m|grep Mem:|awk '{print $3}') $(sar 1 1 | grep Average|awk '{print $3" "$4" "$5" "$6" "$7}') $(date "+%H:%M:%S")" >> /home/ubuntu/metrics.log
done
EOF

chmod +x *.sh

at "now + 1 minute" <<< "/home/ubuntu/monit.sh"
