#!/bin/bash

RED='\e[1;37;41m'
GREEN='\e[1;37;42m'
YELLOW='\e[1;33m'
NC='\e[0m'

KERNEL_VERSION=$3
FLASH_SPL_FILE=$4
FLASH_UBOOT_FILE=$5
FLASH_ROOTFS_FILE=$6
FLASH_KERNEL_FILE=$7
FLASH_DTB_FILE=$8
FLASH_MODULE_FILE=$9
PARTITION_SCRIPT_FILE=${10}

# Use the UTP_COM utility to flash the application images
cd $1

# Create Partition
echo -e "${YELLOW}-> Sending partitioning shell script${NC}"
./utp_com -d $2 -c "send" -f $PARTITION_SCRIPT_FILE
echo -e "${YELLOW}-> Decompresing script...${NC}"
./utp_com -d $2 -c "$ tar xf \$FILE"
echo -e "${YELLOW}-> Partitioning eMMC${NC}"
./utp_com -d $2 -c "$ sh mksdcard.sh /dev/mmcblk3"

# Setup u-boot partition
echo -e "${YELLOW}-> Access boot partition${NC}"
./utp_com -d $2 -c "$ echo 0 > /sys/block/mmcblk3boot0/force_ro"
echo -e "${YELLOW}-> Sending SPL${NC}"
./utp_com -d $2 -c "send" -f $FLASH_SPL_FILE
echo -e "${YELLOW}-> Write SPL into eMMC${NC}"
./utp_com -d $2 -c "$ dd if=\$FILE of=/dev/mmcblk3boot0 bs=1024 seek=1"
echo -e "${YELLOW}-> Sending u-boot.bin${NC}"
./utp_com -d $2 -c "send" -f $FLASH_UBOOT_FILE
echo -e "${YELLOW}-> Write u-boot into eMMC${NC}"
./utp_com -d $2 -c "$ dd if=\$FILE of=/dev/mmcblk3boot0 bs=1024 seek=69"
echo -e "${YELLOW}-> Re-enable read-only${NC}"
./utp_com -d $2 -c "$ sync; echo 1 > /sys/block/mmcblk3boot0/force_ro"
echo -e "${YELLOW}-> Enable boot partion 1 to boot${NC}"
./utp_com -d $2 -c "$ mmc bootpart enable 1 1 /dev/mmcblk3"

# Create EXT4 partition
echo -e "${YELLOW}-> Waiting for the partition ready${NC}"
./utp_com -d $2 -c "$ while [ ! -e /dev/mmcblk3p1 ]; do sleep 1; echo \"waiting...\"; done "
echo -e "${YELLOW}-> Formatting rootfs partition p1${NC}"
./utp_com -d $2 -c "$ mkfs.ext4 -L rootfs /dev/mmcblk3p1"
./utp_com -d $2 -c "$ mkdir -p /mnt/rootfs"
./utp_com -d $2 -c "$ mount /dev/mmcblk3p1 /mnt/rootfs"

# Populate default rootfs on p1
echo -e "${YELLOW}-> Sending and Flashing rootfs partition to eMMC @ p1${NC}"
./utp_com -d $2 -c "pipe tar -x -C /mnt/rootfs" -f $FLASH_ROOTFS_FILE
echo -e "${YELLOW}-> Finishing rootfs image write on p1${NC}"
./utp_com -d $2 -c "frf"
echo -e "${YELLOW}-> Change rootfs ownership${NC}"
./utp_com -d $2 -c "$ sync"
./utp_com -d $2 -c "$ chown root:root /mnt/rootfs"
./utp_com -d $2 -c "$ chmod 755 /mnt/rootfs"

# Set uname_r in /boot/uEnv.txt
echo -e "${YELLOW}-> Set uname_r in /boot/uEnv.txt${NC}"
./utp_com -d $2 -c "$ echo 'uname_r=${KERNEL_VERSION}' >> /mnt/rootfs/boot/uEnv.txt"

# Burn zImage (Kernel) on p1
echo -e "${YELLOW}-> Sending kernel zImage${NC}"
./utp_com -d $2 -c "send" -f $FLASH_KERNEL_FILE
echo -e "${YELLOW}-> Write kernel image to eMMC @ p1${NC}"
./utp_com -d $2 -c "$ cp \$FILE /mnt/rootfs/boot/vmlinuz-${KERNEL_VERSION}"

# Burn dtb on p1
echo -e "${YELLOW}-> Sending Device Tree file${NC}"
./utp_com -d $2 -c "send" -f $FLASH_DTB_FILE
echo -e "${YELLOW}-> Create DIR /mnt/rootfs/boot/dtbs/${KERNEL_VERSION} @ p1${NC}"
./utp_com -d $2 -c "$ mkdir -p /mnt/rootfs/boot/dtbs/${KERNEL_VERSION}/"
echo -e "${YELLOW}-> Writing device tree file to eMMC @ p1${NC}"
./utp_com -d $2 -c "$ tar xf \$FILE -C /mnt/rootfs/boot/dtbs/${KERNEL_VERSION}/"

# Burn modules on p1
echo -e "${YELLOW}-> Sending module file${NC}"
./utp_com -d $2 -c "send" -f $FLASH_MODULE_FILE
echo -e "${YELLOW}-> Writing module file to eMMC @ p1${NC}"
./utp_com -d $2 -c "$ tar xf \$FILE -C /mnt/rootfs/"

# File system table
echo -e "${YELLOW}-> Write fstab (/etc/fstab)${NC}"
./utp_com -d $2 -c "$ echo '/dev/mmcblk2p1  /  auto  errors=remount-ro  0  1' >> /mnt/rootfs/etc/fstab"

# Unmounting
echo -e "${YELLOW}-> Unmounting rootfs partition${NC}"
./utp_com -d $2 -c "$ sync"
./utp_com -d $2 -c "$ umount /mnt/rootfs"

# Done
echo "   "
echo -e "${GREEN}                            ${NC}"
echo -e "${GREEN} -> Board Setup Complete <- ${NC}"
echo -e "${GREEN}                            ${NC}"
echo "   "
./utp_com -d $2 -c "$ echo Update Ready"
