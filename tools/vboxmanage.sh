#!/bin/bash


vm=$1

#remove bootstrap vdi
SATAPORT=$(vboxmanage showvminfo $vm | grep SATA | grep bootstrap|cut -d'(' -f2|cut -d',' -f1)
#FILEPATH=$(vboxmanage showvminfo $vm | grep SATA | grep bootstrap|cut -d':' -f2)
vboxmanage storageattach $vm --storagectl "SATA" --port $SATAPORT --medium none

vboxmanage closemedium bootstrap.vdi

BOOTSTRAP_VMTYPE=vdi ./usbstrap.sh

vboxmanage storageattach $vm --storagectl "SATA" --port $SATAPORT --type hdd --medium  bootstrap.vdi


