#!/bin/bash

#global vars should be defined ASAP, otherwise they should be exported from the function they run in
export PATH=/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export HOME=/root
export LOGNAME=root
export USER=root
export NODEID=`hostid | tr '[:lower:]' '[:upper:]'`

. /root/.global.vars

#we should
# update_system
# update_getty "configuring system"
# configure_nameserver
# configure_hosts
# configure_sshd
# configure_ssh_known_hosts
# packstack_build
# mainevent_apply
# branding
# configure_final

function update_system() {
	update_getty "updating system"
	dnf update -y
}

function configure_nameserver() {
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
        	echo "Adding nameserver" 
        	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	fi
}

function configure_hosts() {
	cat /etc/hosts | grep -q "$HOST\$"
	if [ $? -ne 0 ]; then
		echo "/ETC/HOSTS: $IPADDR $HOST"
		echo "$IPADDR $HOST" >> /etc/hosts
	fi
}

function configure_sshd() {
	echo "#add sshd ports"
	echo "Port 22" >> /etc/ssh/sshd_config
	echo "Port 220" >> /etc/ssh/sshd_config
	echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
	service sshd restart
}

function configure_ssh_known_hosts() {
	echo "#local host is known host"
	cat /root/.ssh/known_hosts | grep -q "$HOST\$"
	if [ $? -ne 0 ]; then
	        mkdir -p /root/.ssh
	        echo "$HOST $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> /root/.ssh/known_hosts
	        echo "$(cat /etc/hosts | grep $HOST | awk '{print $1}') $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> /root/.ssh/known_hosts
	        chmod 600 /root/.ssh/known_hosts
	        chmod 700 /root/.ssh
	fi
}


function update_getty() {
	USRMSG="$*"
	cat << EOI > /etc/issue
NodeLogic 8
Current Task: $USRMSG

EOI
	systemctl restart getty@tty1
}

function branding() {
	echo "#branding"
	if [ -f /root/.nodelogic-openstack-controller ]; then
		text="controller"
	else
		text="instance"
	fi
	cat << EOI > /etc/issue
    oooo==+===oooo=+==ooooooooooooooooooooo=+=+=====oooooo===+==+=+==+==ooo
    oo=o:  .+o===o:  ~ooooooooo==ooooooo=o+         .~+ooo=.           =ooo
    oooo:    :===o:  ~o=oooooooo=ooooooooo+  .+++:~~   ~oo=   :++++++++oooo
    oo=o+     ~=oo:  ~o=oooooo=++=oooooo=o+  .=o==o=+.  :o=.  oo======ooooo
    oo=o:  ~:  .+o:  ~o=ooo=o+    :ooooooo+  .====o=o:  .==.  ~~~.~~~~+oooo
    oo==+  ~o+   +:  ~o=ooooo~    .=oooo=o+  .=oo=o=o+  .==   ..~.~..~+oooo
    oo=o:  ~oo+.  .  ~o=oooooo+~~+=ooooo=o+  .ooooo=o~  ~o=   =ooo=oooooooo
    oo=o+  ~o=o=~    ~oooooooooooooooooooo+  .=====+~  .=o=.  +o========ooo
    oo=o:  ~o=ooo:   ~o=oooooo====oooooo=o+          .~ooo=            ~o=o
    oooo+::+o=ooo=+::+ooooo===oooo==oooooo=::::::::++=ooooo::::::::::::+ooo
    ooooooooooooo=ooooooo=oooooo==oooo=ooooooo=ooooo=o=ooooooooooooooo=oooo
    oooo====oooooo===ooooo=+~~.   .~+=oooo============oooooo============ooo
    ooooooooooooooooooo=o:.   ~~~~.   :=ooooooooooooooooooooooooooooooooooo
    ooooooooooooooooooo=~  ~+=oo==o+~  .=oooooooooooooooooooooooooooooooooo
    ooooooooooooooooo=o~  ~o======ooo:  ~=ooooooooooooooooooooooooooooooooo
    ooooooooooooooooo=o~  +o=oooooo===  .=oooooooooo               oooooooo
    ooooooooooooooooo=o~  ~oooo===ooo:  ~ooooooooooo  NODELOGIC 8  oooooooo
    oooooooooooooooooooo~  ~+oooooo+~  .+ooooooooooo               oooooooo
    oooooooooooooooooooo=:.   ~~~~.   ~=ooooooooooooooooooooooooooooooooooo
    oooooooooooooooooooooo=+~..   .~+=ooooooooooooooooooooooooooooooooooooo
    Authorize this $text at https://nodelogic.net/a/$NODEID

EOI
	systemctl restart getty@tty1
}
