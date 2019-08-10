#!/bin/bash

RED='\e[1;37;41m'
GREEN='\e[1;37;42m'
YELLOW='\e[1;33m'
NC='\e[0m'

WORKING_DIR=`pwd`

config_read_file() {
    (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=__UNDEFINED__") | head -n 1 | cut -d '=' -f 2-;
}

config_get() {
    val="$(config_read_file ${WORKING_DIR}/config.cfg "${1}")";
    if [ "${val}" = "__UNDEFINED__" ]; then
        val="$(config_read_file ${WORKING_DIR}/config.cfg.defaults "${1}")";
    fi
    printf -- "%s" "${val}";
}

if ! [ -f "./config.cfg" ]
then
    echo "Configuration file \"config.cfg\" not found!" >&2
    if [ -f "./config.cfg.defaults" ]
    then
        echo "Use default config file"
    else
        echo "Configuration file \"config.cfg.defaults\" not found!" >&2
        exit 1
    fi
fi

IMX_USB_LOADER_NAME=imx_usb
UTP_COM_NAME=utp_com

# Search for the paths where imx USB loader and UTP com apps are located
IMX_USB_PATH="$( config_get imx_usb_path )"

if [ ! -x $IMX_USB_PATH/$IMX_USB_LOADER_NAME ]
then
     echo -e "${RED}-imx_usb_loader- application not found!${NC}"
     echo -e "${YELLOW}Make sure that the <imx_usb_loader/imx_usb> app exists in the specified path${NC}"
     exit 1  # fail
fi

UTP_COM_PATH="$( config_get utp_com_path )"

if [ ! -x $UTP_COM_PATH/$UTP_COM_NAME ]
then
     echo -e "${RED}-utp_com- application not found!${NC}"
     echo -e "${YELLOW}Make sure that the <utp_com/utp_com> app exists in the specified path${NC}"
     exit 1  # fail
fi

# Establish the location of the files that will be flashed to the board

APP_FLASHING_SCRIPT_NAME="$( config_get app_flashing_script_name )"
if [ ! -x $WORKING_DIR/$APP_FLASHING_SCRIPT_NAME ]
then
     echo -e "${RED}Invalid flashing script file name${NC}"
     echo -e "${YELLOW}It should be the name of the flashing script to execute${NC}"
     echo -e "${YELLOW}Check that the 'app_flashing_script_name' parameter in config file is a excutable file${NC}"
     exit 1  # fail
fi

# Go to the imx_usb_loader folder
cd $IMX_USB_PATH

# Create the folder to transfer the Mfg files from their original location
mkdir firmware

# Here we get a copy of the /dev folder looking for "sg" devices (SCSI devices)
ls /dev/sg* | grep "sg" > firmware/dev-temp1.txt

# Copy the mfg files from the 'images' folder to the imx_usb_loader folder.
FREESCALE_FIRMWARE_PATH="$( config_get freescale_firmware_path )"
FIRMWARE_UBOOT_NAME="$( config_get firmware_uboot_name )"
FIRMWARE_KERNEL_NAME="$( config_get firmware_kernel_name )"
FIRMWARE_DTB_NAME="$( config_get firmware_dtb_name )"
FIRMWARE_INITRAMFS_NAME="$( config_get firmware_initramfs_name )"

if [ ! -f "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_UBOOT_NAME" ]
then
    echo -e "${RED}${FIRMWARE_UBOOT_NAME} not found in ${FREESCALE_FIRMWARE_PATH}${NC}"
    exit 1 # fail
fi

if [ ! -f "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_KERNEL_NAME" ]
then
    echo -e "${RED}${FIRMWARE_KERNEL_NAME} not found in ${FREESCALE_FIRMWARE_PATH}${NC}"
    exit 1 # fail
fi

if [ ! -f "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_DTB_NAME" ]
then
    echo -e "${RED}${FIRMWARE_DTB_NAME} not found in ${FREESCALE_FIRMWARE_PATH}${NC}"
    exit 1 # fail
fi

if [ ! -f "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_INITRAMFS_NAME" ]
then
    echo -e "${RED}${FIRMWARE_INITRAMFS_NAME} not found in ${FREESCALE_FIRMWARE_PATH}${NC}"
    exit 1 # fail
fi

cp "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_UBOOT_NAME"    firmware/
cp "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_KERNEL_NAME"    firmware/
cp "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_DTB_NAME"       firmware/
cp "$FREESCALE_FIRMWARE_PATH/$FIRMWARE_INITRAMFS_NAME" firmware/

IMX_USB_PRINT=`./imx_usb 2>&1`

if `echo "$IMX_USB_PRINT" | grep -q "Could not open device"`; then
     echo -e "${RED}imx_usb returned error: Could not open device${NC}"
     echo -e "${YELLOW}Try disconnecting and reconnecting the device and run this script again${NC}"
     exit 1
fi

if `echo "$IMX_USB_PRINT" | grep -q "no matching USB device found"`; then
     echo -e "${RED}imx_usb returned error: No matching USB device found${NC}"
     echo -e "${YELLOW}Please make sure the board is connected to the USB port and the jumper is set to 'serial downloader mode'${NC}"
     exit 1
fi

if `echo "$IMX_USB_PRINT" | grep -q "err=-"`; then
     echo -e "${RED}imx_usb returned error:${NC}"
     echo $IMX_USB_PRINT
     exit 1
fi

# Execute imx_usb_loader to load into the board RAM the flashing OS
./imx_usb

echo "Getting the SG devices to obtain the SG device name of the board in UTP mode"
sleep 6
ls /dev/sg* | grep "sg" > firmware/dev-temp2.txt

# Get the SG device corresponding to the board by comparing the contents of /dev before
# and after our board is enumerated as a SCSI device.
DEVICE=`diff firmware/dev-temp1.txt firmware/dev-temp2.txt | grep '/dev/sg' | cut -c 3-`

# Delete the temporary files used
rm -rf firmware/

# Return to the project folder and call the script with the UTP commands
KERNEL_VERSION="$( config_get kernel_version )"
FLASH_SPL_FILE="$( config_get flash_spl_file )"
FLASH_UBOOT_FILE="$( config_get flash_uboot_file )"
FLASH_ROOTFS_FILE="$( config_get flash_rootfs_file )"
FLASH_KERNEL_FILE="$( config_get flash_kernel_file )"
FLASH_DTB_FILE="$( config_get flash_dtb_file )"
FLASH_MODULE_FILE="$( config_get flash_module_file )"
PARTITION_SCRIPT_FILE="$( config_get partition_script_file )"

if [ ! -f $FLASH_SPL_FILE ]
then
    echo -e "${RED}File \"$FLASH_SPL_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_SPL_FILE\"${NC}"
fi

if [ ! -f $FLASH_UBOOT_FILE ]
then
    echo -e "${RED}File \"$FLASH_UBOOT_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_UBOOT_FILE\"${NC}"
fi

if [ ! -f $FLASH_ROOTFS_FILE ]
then
    echo -e "${RED}File \"$FLASH_ROOTFS_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_ROOTFS_FILE\"${NC}"
fi

if [ ! -f $FLASH_KERNEL_FILE ]
then
    echo -e "${RED}File \"$FLASH_KERNEL_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_KERNEL_FILE\"${NC}"
fi

if [ ! -f $FLASH_DTB_FILE ]
then
    echo -e "${RED}File \"$FLASH_DTB_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_DTB_FILE\"${NC}"
fi

if [ ! -f $FLASH_MODULE_FILE ]
then
    echo -e "${RED}File \"$FLASH_MODULE_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$FLASH_MODULE_FILE\"${NC}"
fi

if [ ! -f $PARTITION_SCRIPT_FILE ]
then
    echo -e "${RED}File \"$PARTITION_SCRIPT_FILE\" not found!${NC}"
    exit 1
else
    echo -e "${GREEN}Found \"$PARTITION_SCRIPT_FILE\"${NC}"
fi

$WORKING_DIR/$APP_FLASHING_SCRIPT_NAME \
    $UTP_COM_PATH \
    $DEVICE \
    $KERNEL_VERSION \
    $FLASH_SPL_FILE \
    $FLASH_UBOOT_FILE \
    $FLASH_ROOTFS_FILE \
    $FLASH_KERNEL_FILE \
    $FLASH_DTB_FILE \
    $FLASH_MODULE_FILE \
    $PARTITION_SCRIPT_FILE
