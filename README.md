1. Takes existing kickstart file
2. Installs some local prerequisites packages
3. Downloads the CentOS 8-Stream ISO
4. Creates a bootable disk image
5. Installs syslinux, create boot partition, populates disk image
6. Copies kickstart config into image
7. Generate bootloader menu
8. Burn bootstrap.img to media of choice (USB, HDD, etc)

Requires an ubuntu system to build the raw disk image. Tested on Ubuntu 20.04

Available options:

	`BOOTSTRAP_VMTYPE` - One of `none`, `vdi`, `qcow2`, `vmdk`. Creates an extra image file using the VM type of your choice
	`KICKSTART_FILE` - Kickstart file to add to image 
	`OUTPUT_FILE` - Path and filename of image to create

`Example: KICKSTART_FILE=00-00-00-00-00.ks ./usbstrap.sh`

It is highly recommended to use a tool, such as `ksgen`, to generate the necessary kickstart file for you 

