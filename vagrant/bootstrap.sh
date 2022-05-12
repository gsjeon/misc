#!/usr/bin/env bash

set -x

whoami
echo "$1 $2 $3 $4 $5 $6 $7"
# $1 = Control
# $2 = Compute
# $3 = Ceph
# $4 = Zone
# $5 = NetPrefixService
# $6 = NetPrefixMGMT
# $7 = NetSuffix

# Selinux Disable
setenforce 0
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config

# vim configuration
echo "sudo su - clex" >> .bashrc

# swapoff -a to disable swapping
swapoff -a
# sed to comment the swap partition in /etc/fstab
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab

## config sshd
# Disable Message when using ssh 'Are you sure you want to continue connecting'
sed -i '/StrictHostKeyChecking/a StrictHostKeyChecking no' /etc/ssh/ssh_config

# Enable root password login
sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
sed -i "s/^#PermitRootLogin yes/PermitRootLogin yes/g" /etc/ssh/sshd_config

# SSH UseDNS disable, disable root login, login grace 5m
sed -i '/UseDNS no/d' /etc/ssh/sshd_config
sed -i '/#UseDNS/a UseDNS no' /etc/ssh/sshd_config

# SSH UseDNS disable, disable root login, login grace 5m
sed -i '/UseDNS no/d' /etc/ssh/sshd_config
sed -i '/#UseDNS/a UseDNS no' /etc/ssh/sshd_config

# Clex User Create
adduser clex -u 1100 -G wheel -p $(echo 'cloud!234' | openssl passwd -1 -stdin)

# RHEL/CentOS 7 have reported traffic issues being routed incorrectly due to iptables bypassed
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
modprobe br_netfilter
sysctl --system

# local small dns & vagrant cannot parse and delivery shell code.
for (( i=1; i<=$1; i++  )); do echo "$6.$7$i $4-control-$i" >> /etc/hosts; done
for (( i=1; i<=$2; i++  )); do echo "$6.$(($7+1))$i $4-compute-$i" >> /etc/hosts; done
for (( i=1; i<=$3; i++  )); do echo "$6.$(($7+2))$i $4-ceph-$i" >> /etc/hosts; done

# delete 127.0.0.1 $hostname line
sed -i '3 d' /etc/hosts

# add pcadmin to sudoers
sed -i '110 a %wheel        ALL=(ALL)       NOPASSWD: ALL\n' /etc/sudoers

# ulimit openfiles set all users to 1024000
echo "###### ulimit openfiles set all users to 1024000"
echo -e "\n*\tsoft\tnofile\t1024000\n*\thard\tnofile\t1024000" | tee -a /etc/security/limits.conf

# config DNS
cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1 #cloudflare DNS
nameserver 8.8.8.8 #Google DNS
EOF

# Separate kubelet logs
echo "###### Separate kubelet logs"
echo -e "if \$programname == 'kubelet' then /var/log/kubelet.log\n& stop" | tee /etc/rsyslog.d/kubelet.conf

# Separate kernel logs
echo "###### Separate kernel logs"
sed -i '/kern.log/d' /etc/rsyslog.conf && sed -i '/#kern.*/a kern.*                                                 -/var/log/kern.log' /etc/rsyslog.conf

# logrotate - syslog
echo "###### logrotate - syslog"
cat <<EOF | tee /etc/logrotate.d/syslog
/var/log/cron
/var/log/kern.log
/var/log/kubelet.log
/var/log/maillog
/var/log/messages
/var/log/secure
/var/log/sulog
/var/log/spooler
{
    missingok
    rotate 24
    weekly
    compress
    sharedscripts
    create 0600 root root
    postrotate
        /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

###### account security settings
# 0. backup
cp /etc/pam.d/system-auth{,.orig}
cp /etc/pam.d/password-auth{,.orig}
authconfig --savebackup=authconfig_backup

# 1. password '2 factor 10 length' or '3 factor 8 length'

# at least one lower case letter
authconfig --enablereqlower --update

# at least one upper case letter
authconfig --enablerequpper --update

# at least one number
authconfig --enablereqdigit --update

# password over 8 length
sed -i 's#PASS_MIN_LEN\t5#PASS_MIN_LEN\t8#g' /etc/login.defs

# 4. remember last 12 passwords
sed -i '/password    sufficient/ !b; s/$/ remember=12/' /etc/pam.d/system-auth

# 5. password-auth
sed -i '5iauth        required      pam_tally2.so file=/var/log/tallylog deny=5 unlock_time=1800' /etc/pam.d/password-auth
sed -i '15iaccount     required      pam_tally2.so' /etc/pam.d/password-auth

# 6. move tallylog
mv /var/log/tallylog{,.bak}

# 7. [U-03] system-auth
sed -i '5iauth        required      pam_tally2.so file=/var/log/tallylog deny=5 unlo ck_time=1800 no_magic_root' /etc/pam.d/system-auth
sed -i '15iaccount        required      pam_tally2.so no_magic_root reset' /etc/pam.d/system-auth

# 8. [U-45] su
sed -i '5iauth           required        pam_wheel.so use_uid' /etc/pam.d/su
chgrp wheel /bin/su
chmod 4750 /bin/su

##### [U-13] suid, guid, sticky bit permission
chmod u-s /usr/bin/newgrp
chmod u-s /sbin/unix_chkpwd

##### [U-69] login warning message banner
cat << EOF |tee /etc/motd
##########################################################
#                                                        #
#                      Warning!!                         #
#        This system is for authrized users only!!       #
#                                                        #
##########################################################
EOF

cat << EOF |tee /etc/issue.net
##########################################################
#                                                        #
#                      Warning!!                         #
#        This system is for authrized users only!!       #
#                                                        #
##########################################################
EOF

cat << EOF |tee /etc/banner
##########################################################
#                                                        #
#                      Warning!!                         #
#        This system is for authrized users only!!       #
#                                                        #
##########################################################
EOF

sed -i '1iBanner /etc/banner' /etc/ssh/sshd_config

###### yum clean all
#yum install -y net-tools telnet dstat sysstat chrony lsof vim
yum clean all

###### cmd logging
cat <<EOF | tee /etc/profile.d/cmdlog.sh
function cmdlog
{
f_ip=\`who am i | awk '{print \$5}'\`
cmd=\`history | tail -1\`
if [ "\$cmd" != "\$cmd_old" ]; then
  logger -p local1.notice "[1] From_IP=\$f_ip, PWD=\$PWD, Command=\$cmd"
fi
  cmd_old=\$cmd
}
trap cmdlog DEBUG
EOF

sed -i '/cmdlog/d' /etc/rsyslog.conf
sed -i '/cron.none/i local1.notice\t\t\t\t\t\t/var/log/cmdlog' /etc/rsyslog.conf
sed -i 's/cron.none/cron.none;local1.none/g' /etc/rsyslog.conf

cat <<EOF | tee /etc/logrotate.d/cmdlog
/var/log/cmdlog {
    missingok
    minsize 30M
    create 0600 root root
}
EOF

systemctl disable NetworkManager
systemctl disable firewalld

# Kernel Parameters for Docker

cat <<EOF | tee -a /etc/sysctl.conf
# enable the setting in order for Docker remove the containers cleanly
fs.may_detach_mounts = 1
# enable forwarding so the Docker networking works as expected
net.ipv4.ip_forward = 1
# Make sure the host doesn't swap too early
vm.swappiness = 1
# Enable Memory Overcommit
vm.overcommit_memory = 1
# kernel not to panic when it runs out of memory
vm.panic_on_oom = 0
# Increasing the amount of inotify watchers
fs.inotify.max_user_watches = 524288
fs.file-max = 2048000
fs.nr_open = 2048000
EOF

# Tune Network Setting

cat << EOF | tee /etc/sysctl.d/70-cloudpcnetwork.conf

net.netfilter.nf_conntrack_max = 1000000

net.core.somaxconn=1000
net.ipv4.netdev_max_backlog=5000
net.core.rmem_max=16777216
net.core.wmem_max=16777216

net.ipv4.tcp_rmem=4096 12582912 16777216
net.ipv4.tcp_wmem=4096 12582912 16777216
net.ipv4.tcp_max_syn_backlog=8096
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10240 65535
net.ipv4.tcp_abort_on_overflow = 1
EOF

# Increase bash history size and time format
cat <<EOF | tee -a /etc/bashrc
export HISTTIMEFORMAT="%h %d %H:%M:%S "
export HISTSIZE=10000
EOF

# disable local-link network
echo "NOZEROCONF=yes"| tee -a /etc/sysconfig/network

# Add provider nic eth3 config"
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth4
TYPE=Ethernet
BOOTPROTO=none
DEVICE=eth4
ONBOOT=yes
ONPARENT=yes
MTU=1500
EOF

# Disk Parttion Resize
#parted /dev/vda resizepart 2 100%
#pvresize /dev/vda2
#lvextend -l +100%FREE /dev/centos_centos7/root
yum install -y cloud-utils-growpart
growpart /dev/vda 1
xfs_growfs /dev/vda1

# delete nameserver in resolv.conf
tee -a /etc/rc.local << EOF
echo > /etc/resolv.conf
EOF

chmod u+x /etc/rc.local

# install nfs-utils for vagrant shared folder.
yum isntall -y nfs-utils
echo "$5.1:/data/kvm/cloudx-pkg /vagrant nfs defaults,_netdev,noauto 0 0" \
>> /etc/fstab

# Change timezone
timedatectl set-timezone Asia/Seoul

# config chrony
if [ $(hostname) = "$4-control-1" ]
then
cat <<EOF | tee /etc/chrony.conf
server $4-control-1 iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow $6.0/24
local stratum 10
logdir /var/log/chrony	
EOF
else
  sed -i 's/^server*/#server/g' /etc/chrony.conf
  echo "server $4-control-1 iburst" |tee -a  /etc/chrony.conf
fi


# reboot after installing
reboot

