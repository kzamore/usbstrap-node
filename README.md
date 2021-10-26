1. Takes some user inputs
2. Installs some local prerequisites packages
3. Downloads the CentOS 8-Stream ISO
4. Creates a bootable disk image
5. Installs syslinux, create boot partition, populates disk image
6. Generate kickstart config
7. Generate bootloader menu
8. Burn bootstrap.img to media of choice (USB, HDD, etc)

Requires an ubuntu system to build the raw disk image. Tested on Ubuntu 20.04

Available options:

	`BOOTSTRAP_VMTYPE` - One of `none`, `vdi`, `qcow2`, `vmdk`. Creates an extra image file using the VM type of your choice
	`IPADDR` - IP address to assign to system
	`NETMASK` - Netmask of deployed system
	`GATEWAY` - Gateway of deployed system
	`DNS` - DNS of deployed system
	`INITHOST` - Hostname to assign to system
	`LANIPADDR` - LAN IP address to assign to system
	`LANNETMASK` - LAN Netmask must be a /24 (255.255.255.0)
	`LANIPNET` - LAN IP Network address
	`ADMINUSER` - Username to provision on system
	`ADMINPW` - Password to assign to user
	`SSHKEY` - SSH Private Key to deploy to server
	`CENTOSURL` - Base URL for CentOS 8 Mirror
	`TIMEZONE` - Timezone to set on system
	`TGTSIZE` - Size of disk image

`Example: BOOTSTRAP_VMTYPE=vdi ./usbstrap.sh 
	IPADDR=10.10.10.1 NETMASK=255.255.0.0 LANIPADDR=192.168.100.1 ./usbstrap.sh`

