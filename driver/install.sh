#! /bin/bash

ROOT_DIR=`pwd`
RED='\033[0;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
ERROR="0"

BUILD_DIR="build"


[ $(id -u) = 0 ] && printf "${RED}Please do not run this script as root${NC}\n" && exit 100

## FUNCTIONS
install() {
    printf "${GREEN}Installation started...${NC}\n"
    printf "\n[  1  ] ${GREEN}Updating kernel headers and needed software${NC}\n"
    sudo apt-get update
    sudo apt-get -y install raspberrypi-kernel-headers module-assistant pkg-config libncurses5-dev cmake git
    
    printf "\n[  2  ] ${GREEN}Compiling module${NC}\n"
    if [ -d "$BUILD_DIR" ]; then
        echo "Subdirectory '$BUILD_DIR' exists. Deleting its contents..."
        rm -rf "$BUILD_DIR"/*
    else
        echo "Subdirectory '$BUILD_DIR' does not exist. Creating it..."
        mkdir "$BUILD_DIR"
    fi
    
    # enter build dir and build the ko file
    cd "$BUILD_DIR"
    cmake ../
    make
    
    # find the location to install
    output_dir=$(find "/lib/modules" -type f -name "bcm2835_smi_dev*" -exec dirname {} \;)
    
    # Check if the output is empty
    if [ -z "$output_dir" ]; then
        printf "${RED}Error: module 'bcm2835_smi_dev' couldn't be found.${NC}\n"

        # suspicious - why doen't it exist? check of the base module bcm2835_smi exists
        exit 100
    fi
    
    printf "\n[  3  ] ${GREEN}Installing into '${output_dir}'${NC}\n"
    xz -z smi_stream_dev.ko -c > smi_stream_dev.ko.xz
    sudo cp smi_stream_dev.ko.xz ${output_dir}/
    
    printf "\n[  4  ] ${GREEN}Updating 'depmod'${NC}\n"
    sudo depmod -a
    
    printf "\n[  5  ] ${GREEN}Blacklisting original bcm2835_smi_dev module${NC}\n"
    echo "# blacklist the broadcom default smi module to replace with smi_stream_dev" | sudo tee "/etc/modprobe.d/blacklist-bcm_smi.conf" > /dev/null
    echo "blacklist bcm2835_smi_dev" | sudo tee -a "/etc/modprobe.d/blacklist-bcm_smi.conf" > /dev/null
    
    printf "\n[  6  ] ${GREEN}Adding systemd configuration${NC}\n"
    echo "# load SMI stream driver on startup" | sudo tee "/etc/modules-load.d/smi_stream_mod.conf" > /dev/null
    echo "smi_stream_dev" | sudo tee -a "/etc/modules-load.d/smi_stream_mod.conf" > /dev/null
    
    printf "${GREEN}Installation completed.${NC}\n"
}

uninstall() {
    printf "${GREEN}Uninstalling started...${NC}\n"
    
    # find the location of the older installed module
    output_dir=$(find "/lib/modules" -type f -name "smi_stream_dev*" -exec dirname {} \;)
    
    if [ -z "$output_dir" ]; then
        printf "${CYAN}Warning: module 'smi_stream_dev' is not installed in the system${NC}\n"
        sudo depmod -a
        exit 0
    fi
    
    printf "\n[  1  ] ${GREEN}Uninstalling from '${output_dir}'${NC}\n"
    sudo rm ${output_dir}/smi_stream_dev.ko.xz
    
    printf "\n[  2  ] ${GREEN}Updating 'depmod'${NC}\n"
    sudo depmod -a
    
    printf "\n[  3  ] ${GREEN}Removing the blacklist on the legacy smi device${NC}\n"
    if [ -f "/etc/modprobe.d/blacklist-bcm_smi.conf" ]; then
        sudo rm "/etc/modprobe.d/blacklist-bcm_smi.conf"
    fi
    
    printf "\n[  4  ] ${GREEN}Removing device driver loading on start${NC}\n"
    if [ -f "/etc/modules-load.d/smi_stream_mod.conf" ]; then
        sudo rm "/etc/modules-load.d/smi_stream_mod.conf"
    fi
    
    printf "${GREEN}Uninstallation completed.${NC}\n"
}

## FLOW
printf "${GREEN}CaribouLite Device Driver Install / Uninstall${NC}\n"
printf "${GREEN}=============================================${NC}\n\n"

if [ "$1" == "install" ]; then
    install
    
    exit 0
elif [ "$1" == "uninstall" ]; then
    uninstall
    
    exit 0
else
    printf "${CYAN}Usage: $0 [install|uninstall]${NC}\n"
    exit 1
fi

## Say that restart is needed!
print "${GREEN}Now the RPI needs to be restarted...${NC}\n"
