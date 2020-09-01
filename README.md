Requires an ubuntu system to build the raw disk image.

Available options:

`Example: BOOTSTRAP_VMTYPE=vdi ./usbstrap.sh 
	IPADDR=10.10.10.1 NETMASK=255.255.0.0 LANIPADDR=192.168.100.1 ./usbstrap.sh`

	`BOOTSTRAP_VMTYPE` - One of `none`, `vdi`, `qcow2`, `vmdk`. Creates an extra image file using the VM type of your choice
