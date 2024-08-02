#!/bin/bash
## Title:           almaprep-elevate.sh
## Version:         0.4.1
## Description:     Prep servers for CentOS 7 to Almalinux 8 upgrade by removing most / all of the blockers programatically.
## Author(s):       Marius de Beer
## Output:          stdout
## Input:           none
## Usage:           none
## Options:         none
##
##
## Notes & Todo:
##      
##      
##      
##      
##-----------------------------------------------------------------------------


# Make sure all mounts are correct

mount -a
# Create our backup dir's
mkdir -p /root/ELEVATE/repos
mkdir -p /root/ELEVATE/snmp

# Back up snmp
cp /etc/snmp/snmp* /root/ELEVATE/snmp

# Backup and remove remi-safe repository
cp /etc/yum.repos.d/remi-safe.repo /root/ELEVATE/repos/
rm -f /etc/yum.repos.d/remi-safe.repo
#rm -f /etc/yum.repos.d/remi-safe.repo

# Remove R1Soft repo
rm -f /etc/yum.repos.d/r1soft.repo
# Remove Acronis Repo
cp  /etc/yum.repos.d/acronis-cpanel-stable.repo /root/ELEVATE/repos/
rm -f /etc/yum.repos.d/acronis-cpanel-stable.repo

# Remove Blockers : Bitninja 
if rpm -q bitninja > /dev/null; then
    sudo yum remove bitninja -y
    echo "BitNinja has been removed."
else
    echo "BitNinja is not installed."
fi
# Remove BitNinja repo
cp /etc/yum.repos.d/BitNinja* /root/ELEVATE/repos/
rm -f /etc/yum.repos.d/BitNinja*

# Remove Acronis Backup for cPanel software
yum -y remove acronis-backup-cpanel-* -y

# Remove Acronis directories
rm -rvf /usr/lib/Acronis/ /var/lib/Acronis/ /etc/Acronis

# Remove specific Acronis packages without checking dependencies
rpm -qa | grep snapapi26_modules | xargs rpm -e --nodeps
rpm -qa | grep file_protector | xargs rpm -e --nodeps
rpm -qa | grep BackupAndRecoveryBootableComponents | xargs rpm -e --nodeps
rpm -qa | grep BackupAndRecoveryAgent | xargs rpm -e --nodeps

# Remove Blockers : old PHP versions
rpm -qa | grep ea-php56 | xargs sudo yum remove -y
rpm -qa | grep ea-php70 | xargs sudo yum remove -y
rpm -qa | grep ea-php71 | xargs sudo yum remove -y
rpm -qa | grep ea-php72 | xargs sudo yum remove -y
rpm -qa | grep ea-php73 | xargs sudo yum remove -y    

# Remove Blockers : clean yum
yum clean all
rm -rf /var/cache/yum

# Remove Blockers : create locale file
export LC_ALL=en_US.UTF-8
echo 'LANGUAGE=en_US.UTF-8' | sudo tee -a /etc/locale.conf
echo 'LC_ALL=en_US.UTF-8' | sudo tee -a /etc/locale.conf
echo 'LC_CTYPE=UTF-8' | sudo tee -a /etc/locale.conf
echo 'LANG=en_US.UTF-8' | sudo tee -a /etc/locale.conf
#sudo localectl set-locale LANG=en_IN.UTF-8
#source /etc/profile.d/lang.sh

#############  NETWORK PART 
# Fix Grub
check_mount=$(df | grep "/boot/efi" | awk '{print $6}')
if [ -z "$check_mount" ]
then
  echo "ERROR! /boot/efi mount missing.
 
fi

sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
# Remove Blockers : fix network scripts
mv /etc/sysconfig/network-scripts/*.bak /root/ELEVATE
cp /etc/sysconfig/network-scripts/ifcfg-eth0 /root/ELEVATE/ifcfg-eth0_bk
cp /etc/sysconfig/network-scripts/ifcfg-eth1 /root/ELEVATE/ifcfg-eth1_bk
cp /etc/sysconfig/network-scripts/ifup-eth /etc/sysconfig/network-scripts/ifup-eno
cp /etc/sysconfig/network-scripts/ifdown-eth /etc/sysconfig/network-scripts/ifdown-eno
mv /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eno1
mv /etc/sysconfig/network-scripts/ifcfg-eth1 /etc/sysconfig/network-scripts/ifcfg-eno2
# Fix Hardware Address in the interface configuration file
sudo sh -c 'echo "HWADDR=$(ip link show eno1 | awk '\''/link\/ether/ {print $2}'\'')" >> /etc/sysconfig/network-scripts/ifcfg-eno1'
sudo sh -c 'echo "HWADDR=$(ip link show eno2 | awk '\''/link\/ether/ {print $2}'\'')" >> /etc/sysconfig/network-scripts/ifcfg-eno2'
sudo sed -i 's/DEVICE=eth0/DEVICE=eno1/' /etc/sysconfig/network-scripts/ifcfg-eno1
sudo sed -i 's/NAME=eth0/NAME=eno1/' /etc/sysconfig/network-scripts/ifcfg-eno1
sudo sed -i 's/DEVICE=eth1/DEVICE=eno2/' /etc/sysconfig/network-scripts/ifcfg-eno2
sudo sed -i 's/NAME=eth2/NAME=eno2/' /etc/sysconfig/network-scripts/ifcfg-eno2
# 
#/etc/sysconfig/netowrk-scripts/ifdown eth 
#/etc/sysconfig/netowrk-scripts/ifup eno

# Extract hardware address for eno1
hardware_address=$(ifconfig -a | grep -Po 'ether \K([0-9a-f]{2}[:-]){5}([0-9a-f]{2})')


# Remove /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
touch /etc/udev/rules.d/70-persistent-net.rules
if [ -n "$hardware_address" ]; then
    # Add HWADDR to ifcfg-eno1 file
    echo "HWADDR=$hardware_address" | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-eno1
    echo "Hardware address added to ifcfg-eno1 file."

    # Add rule to 70-persistent-net.rules file
    echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="'$hardware_address'", ATTR{type}=="1", KERNEL=="eno*", NAME="eno1"' >> /etc/udev/rules.d/70-persistent-net.rules
    echo "Rule added to 70-persistent-net.rules file."
else
    echo "Hardware address for eno1 not found in ifconfig output."
fi

# Extract hardware address for eno2
eno2_hw_address=$(ifconfig -a | grep -Po 'ether \K([0-9a-f]{2}[:-]){5}([0-9a-f]{2})')

# Check if the hardware address for eno2 is not empty
if [ -n "$hardware_address" ]; then
    # Add HWADDR to ifcfg-eno1 file
    echo "HWADDR=$hardware_address" | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-eno1
    echo "Hardware address added to ifcfg-eno1 file."

    # Add rule to 70-persistent-net.rules file
    echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="'$hardware_address'", ATTR{type}=="1", KERNEL=="eno*", NAME="eno1"'  >> /etc/udev/rules.d/70-persistent-net.rules
    echo "Rule added to 70-persistent-net.rules file."
else
    echo "Hardware address for eno2 not found in ifconfig output."
fi

# Fix SSH Root Login for Elevate
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config


yum -y update && yum -y upgrade
yum -y install yum-utils
/scripts/upcp

yum -y autoremove
package-cleanup --oldkernels --count=1

## Prep for Elevate
sudo yum install -y http://repo.almalinux.org/elevate/elevate-release-latest-el7.noarch.rpm
sudo yum install -y leapp-upgrade leapp-data
wget -O /scripts/elevate-cpanel https://raw.githubusercontent.com/cpanel/elevate/release/elevate-cpanel; chmod 700 /scripts/elevate-cpanel
yum -y install NetworkManager
systemctl enable NetworkManager

clear

echo "You should reboot the server now."
echo "Do you wish to proceed? y/n"
read user_input

if [[ $user_input == "y" ]]; then
  echo "Rebooting server..."
  shutdown -r now
else
  echo "Aborting reboot.  Script execution complete."
fi


# Remove Blockers : clean yum
yum clean all
rm -rf /var/cache/yum
#
# From the trenches,
# MDB
