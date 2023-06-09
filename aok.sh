#!/bin/bash -e

## Created And Licenced By cubetronic , Modified By The Ali Dev
## This script depends on files in $HOME/tmp/aok
## Developer Note: curl is built without metalink support in Chrome OS

## Check for root privilege
if [ "$EUID" != 0 ]; then
  echo "Root privilege not found, quitting."
  exit 1
fi

## Show system info
crossystem hwid && echo || echo "crossystem not found. OK."
## crossystem fwid should show Veyron if it's a veyron board
crossystem fwid && echo || echo -n

## Check for necessary tools
curl -V > /dev/null
md5sum --version > /dev/null
umount -V > /dev/null
fdisk -V > /dev/null
cgpt add -h > /dev/null
mkfs -V > /dev/null
dd --version > /dev/null
lsblk -V > /dev/null

ping -c 1 archlinuxarm.org > /dev/null \
  || echo "archlinuxarm.org not found. May use local data."

CYAN='\033[1;36m' # Light Cyan
GREEN='\033[1;32m' # Light Green
YELLOW='\033[1;33m' # Light Yellow
RED='\033[1;31m' # Light Red
NC='\033[0m' # No Color
echo
printf "Welcome to the ${CYAN}AOK Linux${NC} Installer\n"

## Show some possibilities
echo
echo "Possible Devices to Install Arch Linux:"
echo
lsblk | grep '^[Aa-Zz]' | grep -v -E -- 'loop|boot|ram|rpmb'

## Show USB compatibility if possible
{
USB_DEVICE_COUNT=$(lsblk | grep '^sd' | wc -l)
if [ "$USB_DEVICE_COUNT" -gt 0 ]; then
echo
echo "Not all USB drives are compatible."
fi
while [ "$USB_DEVICE_COUNT" -gt 0 ]; do
  THIS_DEVICE=$(lsblk | grep '^sd' | head -c 3)
  ## grep the tail to make sure it's the most current info
  USB_MODE=$(dmesg | grep "$THIS_DEVICE" | grep 'Mode Sense' | tail -n 1 | \
      sed 's/.*Mode\ Sense:\ //')
  case "$USB_MODE" in
    "23 00 00 00")
      COMPATIBILITY="${GREEN}known to be compatible${NC}"
      ;;
    "43 00 00 00")
      COMPATIBILITY="${YELLOW}known to be either compatible or incompatible${NC}"
      ;;
    "45 00 00 00")
      COMPATIBILITY="${RED}known to be incompatible${NC}"
      ;;
    *)
      COMPATIBILITY="unknown"
      ;;
  esac
  echo "The USB drive at /dev/${THIS_DEVICE} has a Mode Sense of ${USB_MODE},"
  printf "    which is ${COMPATIBILITY}.\n"
  USB_DEVICE_COUNT=$[$USB_DEVICE_COUNT-1]
done

## Unnecessary feedback
#echo
#OTHER_DEVICE_COUNT=$(lsblk | grep '^mmcblk' | grep -v -E -- 'loop|boot|ram|rpmb' | wc -l)
#while [ "$OTHER_DEVICE_COUNT" -gt 0 ]; do
#  THIS_DEVICE=$(lsblk | grep '^mmcblk' | head -c 7)
#  echo "The drive at /dev/$THIS_DEVICE is compatible, as all block devices are."
#  OTHER_DEVICE_COUNT=$[$OTHER_DEVICE_COUNT-1]
#done

} || echo -n


if [ "$(uname -p | grep ARMv7)" ]; then
  echo
  echo "Select what to ERASE and install Arch Linux on:"
  echo 
  echo "0) /dev/mmcblk0  eMMC, erase ChromeOS   Must be running from SD/USB already"
  echo "1) /dev/mmcblk1  SD Card                4GB+ needed"
  echo "a) /dev/sda      USB Drive              4GB+ needed. For compatible USB's."
  echo "b) /dev/sdb      Second USB Drive       4GB+ needed. For compatible USB's."
  echo
  echo "q) Quit"
  echo
else
  echo
  echo "Select what to ERASE and install Arch Linux on:"
  echo 
  echo "0) /dev/mmcblk0"
  echo "1) /dev/mmcblk1"
  echo "a) /dev/sda"
  echo "b) /dev/sdb"
  echo "c) /dev/sdc"
  echo
  echo "q) Quit"
  echo
fi

read -rp "> " CHOICE
case "$CHOICE" in
  0)
    DEVICE='/dev/mmcblk0'
    PARTITION_1='p1'
    PARTITION_2='p2'
    ;;
  1)
    DEVICE='/dev/mmcblk1'
    PARTITION_1='p1'
    PARTITION_2='p2'
    ;;
  a)
    DEVICE='/dev/sda'
    PARTITION_1='1'
    PARTITION_2='2'
    ;;
  b)
    DEVICE='/dev/sdb'
    PARTITION_1='1'
    PARTITION_2='2'
    ;;
  c)
    DEVICE='/dev/sdc'
    PARTITION_1='1'
    PARTITION_2='2'
    ;;
  *)
    echo "No changes made."
    exit 1
    ;;
esac


## Safety checks

## Avoid over-writing system in use
if [ "$DEVICE" = '/dev/mmcblk0' ]; then
  if [ "$(grep -i 'chrome' /etc/os-release)" ]; then
    echo "ChromeOS detected. Your selection is not supported."
    echo
    echo "You have selected to install to /dev/mmcblk0"
    echo "but it appears you may currently be using /dev/mmcblk0"
    echo
    echo "To install Arch Linux on the eMMC Internal Memory"
    echo "(replacing ChromeOS),"
    echo "first install Arch Linux to SD or USB,"
    echo "and then boot from that installation."
    exit 67
  fi
fi

## Set default of whether to get a new distro release
NEW_RELEASE=false

## Check target capacity
SIZER=$(lsblk -o SIZE -bnd $DEVICE)
if [ "$SIZER" -lt 3000000000 ]; then
  echo "3 GB capacity is required on target device for installation"
  echo "$(expr $SIZER / 1000000000) GB capacity on $DEVICE - too small, exiting."
  exit 78
else
  echo "$(expr $SIZER / 1000000000) GB capacity on ${DEVICE}. OK."
fi

## Confirm
echo
read -rp "Any data on ${DEVICE} will be erased. Are you sure? [y/N] " CONFIRM
if [[ ! $CONFIRM =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo "No changes made."
  exit 1
fi

## Installation process.

## Go to $HOME/tmp/aok, and make sure
mkdir $HOME/tmp/aok
cd $HOME/tmp/aok

echo "Preparing distribution files..."
cd distro
## Save the included md5 file in case of a dropbox download
cp ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.bak
MIRROR_SUCCESS=false

## Offline function, try using local md5 or quit
use_local_md5 () {
  if [ -f 'ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5' ]; then
    echo "Using existing local md5 file."
  else
    echo "Cannot find md5 file. Quitting."
    exit 75
  fi
}

## Check if Internet and DNS are working before testing any mirror
if [ "$(ping -c 1 archlinuxarm.org)" ]; then

  ## Allow 10 seconds to download the md5 from main mirror
  curl --max-time 10 -LO \
      mirror.archlinuxarm.org/os/ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 && {
    cp -u ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 \
        ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.tmp
    MIRROR_SUCCESS=true
  } || echo -n

  ## Now test local mirrors
  ## Test mirrors and hopefully create bestmirrors.txt
  echo "Testing mirrors..."

  ## Create or reset the working mirrors list file, and set local mirror status
  echo -n > workingmirrors.txt.tmp
  LOCAL_MIRROR_SUCCESS=false

  ## All local Arch Linux ARM mirrors, not the main load-balancing mirror:
  ## https://archlinuxarm.org/about/mirrors
  ## /etc/pacman.d/mirrorlist
  all_Mirrors=(au br2 dk de3 de de4 de5 de6 eu gr hu nl ru sg za tw ca.us nj.us fl.us il.us vn)

  ## Try to download md5 file for each mirror, recording speeds
  for SUBDOMAIN in ${all_Mirrors[@]}; do

    ## Download md5, and save Current Speed from curl progress meter
    ## A higher number is better. Domains that fail will have a null value.
    CURRENT_SPEED=$(curl --max-time 5 -LO \
    ${SUBDOMAIN}.mirror.archlinuxarm.org/os/ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 \
    2>&1 | grep $'\r100' | grep -o '[^ ]*$' || echo -n)

    ## What if it's a bad md5 file, like a 404?
    ## It should contain the filename, and be only 1 line
    if [ $(grep ArchLinuxARM-armv7-chromebook-latest.tar.gz \
        ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 | wc -l) -eq 1 ]; then

      ## Save the working mirror to a text file, Format: Speed (tab) Mirror
      if [ -n "$CURRENT_SPEED" ]; then
        echo -e "${CURRENT_SPEED}\t${SUBDOMAIN}.mirror.archlinuxarm.org" \
          | tee -a workingmirrors.txt.tmp
        ## Save the best md5, and record success
        cp -u ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 \
            ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.tmp
        MIRROR_SUCCESS=true
        LOCAL_MIRROR_SUCCESS=true

      ## If the md5 download failed, just report that.
      else
        echo -e "\t${SUBDOMAIN}.mirror.archlinuxarm.org failed completely"
      fi

    ## The md5 file appears to be invalid, so restore the good one if possible. 
    else
      echo -e "\t${SUBDOMAIN}.mirror.archlinuxarm.org did not provide the correct file (Likely 404)"
      ## Restore the real (and best) md5 if one exists
      cp ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.tmp \
          ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 || echo -n
    fi
  done

  ## Create bestmirrors.txt if possible
  if [ "$LOCAL_MIRROR_SUCCESS" = true ]; then
    echo
    echo "These are your current best mirrors:"
    echo -e "SPEED\tMIRROR"
    ## Sort human readable reverse (highest first) to a sorted file
    cat workingmirrors.txt.tmp | sort -hr | tee bestmirrors.txt
  else
    echo
    echo "No working local mirrors found."
  fi

  ## Cleanup
  rm -f ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.tmp
  rm -f workingmirrors.txt.tmp
  echo "Mirrors testing complete."

  ## If there's a new release, ask what to use

  ## Compare md5 of new md5 to md5 of old md5 - no "diff" utility on Chrome OS
  OLD_DISTRO_MD5=$(md5sum ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 | cut -c1-32)
  NEW_DISTRO_MD5=$(md5sum ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.bak | cut -c1-32)
  if [ "$OLD_DISTRO_MD5" = "$NEW_DISTRO_MD5" ]; then
    echo "No new distro release is available. Using current distro release."
  else
    read -rp "A new disto has been released. Use it? [Y/n] " USE_NEW_DISTRO
    if [[ ! $USE_NEW_DISTRO =~ ^([nN]|[nN][oO])$ ]]; then
      NEW_RELEASE=true
    fi
  fi
  if [ "$MIRROR_SUCCESS" = false ]; then
    echo "Cannot download latest md5: all mirrors failed."
    use_local_md5
  fi
else
    echo "Cannot download latest md5: archlinuxarm.org not found."
    use_local_md5
fi



## Get the distro if md5 doesn't match

## Test space (safe but isn't necessary if overwriting a previous release!)
test_local_space () {
  LOCAL_FREE=$(df --output=avail / | tail -n 1)
  if [ "$LOCAL_FREE" -lt 100000 ]; then
    echo "100 MB are required on local system to download files."
    echo "$(expr $LOCAL_FREE / 1000) MB available."
    echo "Not enough storage space on this system to download distro, exiting."
    exit 79
  else
    echo "$(expr $LOCAL_FREE / 1000) MB available on local filesystem. ~500 MB will be used. OK."
  fi
}

check_md5 () {
  md5sum -c ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 --status
}

get_from_dropbox () {
  echo "Attempting download of AOK Verified Backup Release from dropbox..."
  test_local_space
  curl -LO \
      https://dl.dropboxusercontent.com/s/gca6lst2llqoqg2/ArchLinuxARM-armv7-chromebook-latest.tar.gz \
      && md5sum -c ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5.bak || {
        echo "Couldn't download Arch Linux. Perhaps the Internet connection is not reliable."
        exit 76
      }
}

try_downloading_file () {
  echo "Attempting distribution download..."
  ## Get ready to try downloading from every working local mirror
  DOWNLOADED=false
  DL=1
  MAX_MIRRORS=$(cat bestmirrors.txt | wc -l)
  ## Here's where to use the fastest mirror from testing
  while [ "$DL" -le "$MAX_MIRRORS" ]; do
    TRY_MIRROR=$(sed -n "${DL}p" bestmirrors.txt | sed $'s/.*\t//')
    ## Try to download the root filesystem with 3 packages for wifi-menu
    test_local_space
    curl -LO ${TRY_MIRROR}${FILE_NEEDED} \
        && {
          check_md5 && DOWNLOADED=true && break
        } ||
        DL=$[$DL+1]
  done
  ## Try the main load-balanced mirror as a last resort
  if [ "$DOWNLOADED" = false ]; then
    echo "Couldn't reach any mirrors, trying main archlinuxarm.org site..."
    test_local_space
    curl -LO mirror.archlinuxarm.org${FILE_NEEDED} \
        && check_md5 \
        || {
          echo "Couldn't download from archlinuxarm.org."
          get_from_dropbox
        }
  fi
  ## Must have a good file at this point
  echo "Distribution download complete."
}

## Check md5 against file even if it doesn't exist, or try downloading
md5sum -c ArchLinuxARM-armv7-chromebook-latest.tar.gz.md5 --status || {
  if [ "$NEW_RELEASE" = true ]; then
    FILE_NEEDED='/os/ArchLinuxARM-armv7-chromebook-latest.tar.gz'
    try_downloading_file
  else
    get_from_dropbox
  fi
}

## Add warning
printf "${RED}Do NOT click on pop-up messages!${NC}\n"

## Return to aok from aok/distro, silently
cd - > /dev/null
echo "Distribution files ready."




echo "Starting Arch Linux Installation..."

umount ${DEVICE}* 2> /dev/null || echo -n

## Automate fdisk.
## This automatically sizes the root partition.
## Do not change the whitespace here, it is very important.
## Each blank line represents accepting the default by just pressing enter.

## g: new gpt partition table
## n: new gpt partition
## (blank line): accept the default, i.e., start at 2048 for partition 1
## +16M: 16 MiB partition
## w: write and exit

## You may also want to add a swap drive (and enable swap)
{ fdisk --wipe always ${DEVICE} << "END"
g
n


+16M
n



w
END
} &> /dev/null || {
  echo "fdisk was unable to re-read partition table. Using partx to solve..."
}

umount ${DEVICE}* 2> /dev/null || echo -n

## Updating partition info, regardless of whether it's necessary or not
partx -u ${DEVICE}

## Set partition type here with -t, instead of in fdisk
## Set special flags needed by U-Boot, and add labels to be user friendly.
## Ignore cgpt errors
cgpt add -i 1 -t kernel -S 1 -T 5 -P 10 -l KERN-A ${DEVICE} || echo -n
cgpt add -i 2 -t data -l Root ${DEVICE} || echo -n

## Extra umounting, just in case
umount ${DEVICE}* 2> /dev/null || echo -n
umount rootfs 2> /dev/null || echo -n

## Make filesystem
## Ignore complaints that it's "apparently in use by the system" but isn't (-F -F)
## Disable journaling
## Suppress technical jargon and kernel upgrade recommendation
mkfs.ext4 -F -F -O ^has_journal ${DEVICE}${PARTITION_2} &> /dev/null

## Updating partition info, regardless of whether it's necessary or not
partx -u ${DEVICE}

## Copy files
mkdir -p rootfs
mount ${DEVICE}${PARTITION_2} rootfs

echo "Copying Filesystem..."

## Ignore harmless SCHILY.fflags warnings
tar --warning=no-unknown-keyword -xf \
distro/ArchLinuxARM-armv7-chromebook-latest.tar.gz -C rootfs --checkpoint=.500
sync
dd if=rootfs/boot/vmlinux.kpart of=${DEVICE}${PARTITION_1} status=progress
sync

## Enable external boot
crossystem dev_boot_usb=1 dev_boot_signed_only=0 || echo -n

## Don't let kernel messages garble the console. Hide them.
mkdir -p rootfs/etc/sysctl.d
echo "kernel.printk = 3 3 3 3" >> rootfs/etc/sysctl.d/20-quiet-printk.conf

## Add best mirrors to pacman mirrorlist
if [ -f 'distro/bestmirrors.txt' ]; then
  ADD=1
  MAX_MIRRORS=$(cat distro/bestmirrors.txt | wc -l)
  echo > usemirrors.txt
  echo "## Automatically added mirrors from AOK mirror testing" \
      >> usemirrors.txt

  ## Reformat and add each working mirror to use list
  while [ "$ADD" -le "$MAX_MIRRORS" ]; do
    APPEND=$(sed -n "${ADD}p" distro/bestmirrors.txt | sed $'s/.*\t//')
    echo 'Server = http://'${APPEND}'/$arch/$repo' \
        >> usemirrors.txt
    ADD=$[$ADD+1]
  done

  ## Append 3 use mirror list to the TOP of the mirrorlist
  cp rootfs/etc/pacman.d/mirrorlist rootfs/etc/pacman.d/mirrorlist.bak
  head -n 5 usemirrors.txt > topmirrors.tmp
  cat topmirrors.tmp rootfs/etc/pacman.d/mirrorlist > newmirrorlist.tmp \
      && mv newmirrorlist.tmp rootfs/etc/pacman.d/mirrorlist
  rm topmirrors.tmp

fi


## Bulk copy of custom content (will ALSO install in specific places)

## Install aok, setup, dim, and anything else
mkdir -p rootfs/usr/local/bin
install aok rootfs/usr/local/bin
install setup rootfs/usr/local/bin
install extra/dim rootfs/usr/local/bin
install extra/tpad rootfs/usr/local/bin
install extra/spoof rootfs/usr/local/bin

## Copy everything except distro to aok folder
mkdir -p rootfs/usr/local/aok
install aokx rootfs/usr/local/aok
cp aok rootfs/usr/local/aok
cp setup rootfs/usr/local/aok
cp -r files rootfs/usr/local/aok
cp -r extra rootfs/usr/local/aok
cp README.md rootfs/usr/local/aok

## ALSO, copy global configuration files to specific locations

## Copy Arch Linux icon for Xfce menu
mkdir -p rootfs/usr/share/icons
cp files/arch_linux_gnome_menu_icon_by_byamato.png rootfs/usr/share/icons

## ALSO, copy Xfce skeleton files

mkdir -p rootfs/etc/skel/.config/xfce4/panel
cp files/whiskermenu-10.rc rootfs/etc/skel/.config/xfce4/panel

## Copy desktop, panel, power settings
mkdir -p rootfs/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
cp files/*.xml \
   rootfs/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml

## Copy firefox launcher
mkdir -p rootfs/etc/skel/.config/xfce4/panel/launcher-7
cp files/15761344891.desktop \
    rootfs/etc/skel/.config/xfce4/panel/launcher-7

## Provide gentoo style bashrc, enabling color in all shells (changes filename)
cp rootfs/etc/skel/.bashrc rootfs/etc/skel/.bashrc.backup || echo -n
cp files/dot-bashrc rootfs/etc/skel/.bashrc
cp files/dot-bashrc rootfs/root/.bashrc
cp files/dot-dmrc rootfs/etc/skel/.dmrc

## Copy firefox pre-config (ublock, user-agent switcher, kill sticky, settings)
tar -xf files/dot-mozilla-preconfig.tar.gz -C rootfs/etc/skel/

## Configure being able to run "startx" to load Xfce
echo "exec startxfce4" > rootfs/etc/skel/.xinitrc

## Create a welcome message with instructions
cat << "EOF" >> rootfs/etc/issue
Welcome. To finish installing \e[1;36mAOK Linux\e[0m, do the following:
1. Login. The username is "root", and the default password is "root".
2. After logging in, type "setup" and press enter.

EOF

## Enable color in pacman
sed -i 's/^#Color/Color/' rootfs/etc/pacman.conf

## Finish up
echo
echo "Syncing..."
umount rootfs
sync
rmdir rootfs

## Post-installation menus
echo
echo "Arch Linux Installation is complete."
echo
read -rp "Copy distro file to new drive for future installs? [y/N] " FUTURE
if [[ $FUTURE =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo "Copying distro..."
  mkdir rootfs
  mount ${DEVICE}${PARTITION_2} rootfs
  cp -r distro rootfs/usr/local/aok/
  umount rootfs
  sync
  rmdir rootfs
  echo "Distro copied."
fi

echo "Done."
echo
printf "To boot from USB on a Samsung XE303C12, use the ${YELLOW}USB 2.0${NC} Port\n"
echo
printf "Upon boot press ${YELLOW}ctrl${NC}+${YELLOW}u${NC} to boot USB/SD, or ctrl+d to boot Internal Storage.\n"
echo
read -rp "Reboot now? [Y/n] " REBOOTER
if [[ ! $REBOOTER =~ ^([nN]|[nN][oO])$ ]]; then
  reboot
fi
