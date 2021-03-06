#!/bin/bash -e
#
# Copyright (c) 2011 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

#Debug Tips
#oem-config username/password
#add: "debug-oem-config" to bootargs

unset MMC
unset DEFAULT_USER
unset DEBUG
unset BETA
unset FDISK_DEBUG
unset BTRFS_FSTAB
unset HASMLO
unset ABI_VER
unset HAS_INITRD
unset SECONDARY_KERNEL
unset USE_UENV

unset SVIDEO_NTSC
unset SVIDEO_PAL

#Defaults
RFS=ext4
BOOT_LABEL=boot
RFS_LABEL=rootfs
PARTITION_PREFIX=""

DIR=$PWD
TEMPDIR=$(mktemp -d)

function check_root {

if [[ $UID -ne 0 ]]; then
 echo "$0 must be run as sudo user or root"
 exit
fi

}

function find_issue {

check_root

#Software Qwerks
#fdisk 2.18.x/2.19.x, dos no longer default
unset FDISK_DOS

if [ "$FDISK_DEBUG" ];then
 echo "Debug: fdisk version:"
 fdisk -v
fi

if test $(sudo fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
 FDISK_DOS="-c=dos -u=cylinders"
fi

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

unset PARTED_ALIGN
if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
 PARTED_ALIGN="--align cylinder"
fi

}

function detect_software {

unset NEEDS_PACKAGE

if [ ! $(which mkimage) ];then
 echo "Missing uboot-mkimage"
 NEEDS_PACKAGE=1
fi

if [ ! $(which wget) ];then
 echo "Missing wget"
 NEEDS_PACKAGE=1
fi

if [ ! $(which pv) ];then
 echo "Missing pv"
 NEEDS_PACKAGE=1
fi

if [ ! $(which mkfs.vfat) ];then
 echo "Missing mkfs.vfat"
 NEEDS_PACKAGE=1
fi

if [ ! $(which mkfs.btrfs) ];then
 echo "Missing btrfs tools"
 NEEDS_PACKAGE=1
fi

if [ ! $(which partprobe) ];then
 echo "Missing partprobe"
 NEEDS_PACKAGE=1
fi

if [ "${NEEDS_PACKAGE}" ];then
 echo ""
 echo "Your System is Missing some dependencies"
 echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget pv dosfstools btrfs-tools parted"
 echo "Fedora: as root: yum install uboot-tools wget pv dosfstools btrfs-progs parted"
 echo "Gentoo: emerge u-boot-tools wget pv dosfstools btrfs-progs parted"
 echo ""
 exit
fi

}

function boot_files_template {

cat > ${TEMPDIR}/boot.cmd <<boot_cmd
setenv dvimode VIDEO_TIMING
setenv vram 12MB
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; fatload mmc 0:1 UINITRD_ADDR uInitrd; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=SERIAL_CONSOLE VIDEO_CONSOLE root=/dev/mmcblk0p2 rootwait ro VIDEO_RAM VIDEO_DEVICE:VIDEO_MODE fixrtc buddy=\${buddy} buddy2=\${buddy2} mpurate=\${mpurate}
boot
boot_cmd

}

function boot_scr_to_uenv_txt {

cat > ${TEMPDIR}/uEnv.cmd <<uenv_boot_cmd
bootenv=boot.scr
loaduimage=fatload mmc \${mmcdev} \${loadaddr} \${bootenv}
mmcboot=echo Running boot.scr script from mmc ...; source \${loadaddr}
uenv_boot_cmd

}

function boot_uenv_txt_template {
#(rcn-ee)in a way these are better then boot.scr, but each target is going to have a slightly different entry point..

case "$SYSTEM" in
    beagle_bx)

cat > ${TEMPDIR}/uEnv.cmd <<uenv_boot_cmd
bootfile=uImage
address_uimage=UIMAGE_ADDR
address_uinitrd=UINITRD_ADDR

console=SERIAL_CONSOLE
optargs=VIDEO_CONSOLE

defaultdisplay=VIDEO_OMAPFB_MODE
dvimode=VIDEO_TIMING

mmcroot=/dev/mmcblk0p2 ro
mmcrootfstype=FSTYPE rootwait fixrtc

mmc_load_uimage=fatload mmc 0:1 \${address_uimage} uImage
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} uInitrd

#dvi->defaultdisplay
mmcargs=setenv bootargs console=\${console} \${optargs} mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay} root=\${mmcroot} rootfstype=\${mmcrootfstype}

loaduimage=run mmc_load_uimage; run mmc_load_uinitrd; echo Booting from mmc ...; run mmcargs; bootm \${address_uimage} \${address_uinitrd}
uenv_boot_cmd

        ;;
    beagle)

cat > ${TEMPDIR}/uEnv.cmd <<uenv_boot_cmd
bootfile=uImage
address_uimage=UIMAGE_ADDR
address_uinitrd=UINITRD_ADDR

console=SERIAL_CONSOLE
optargs=VIDEO_CONSOLE

defaultdisplay=VIDEO_OMAPFB_MODE
dvimode=VIDEO_TIMING

mmcroot=/dev/mmcblk0p2 ro
mmcrootfstype=FSTYPE rootwait fixrtc

mmc_load_uimage=fatload mmc 0:1 \${address_uimage} uImage
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} uInitrd

#dvi->defaultdisplay
mmcargs=setenv bootargs console=\${console} \${optargs} mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay} root=\${mmcroot} rootfstype=\${mmcrootfstype}

loaduimage=run mmc_load_uimage; run mmc_load_uinitrd; echo Booting from mmc ...; run mmcargs; bootm \${address_uimage} \${address_uinitrd}
uenv_boot_cmd

        ;;
    bone)

cat > ${TEMPDIR}/uEnv.cmd <<uenv_boot_cmd
bootfile=uImage
address_uimage=UIMAGE_ADDR
address_uinitrd=UINITRD_ADDR

console=SERIAL_CONSOLE

defaultdisplay=VIDEO_OMAPFB_MODE
dvimode=VIDEO_TIMING

mmcroot=/dev/mmcblk0p2 ro
mmcrootfstype=FSTYPE rootwait fixrtc

rcn_mmcloaduimage=fatload mmc 0:1 \${address_uimage} uImage
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} uInitrd

mmc_args=run bootargs_defaults;setenv bootargs \${bootargs} root=\${mmcroot} rootfstype=\${mmcrootfstype} ip=\${ip_method}

mmc_load_uimage=run rcn_mmcloaduimage; run mmc_load_uinitrd; echo Booting from mmc ...; run mmc_args; bootm \${address_uimage} \${address_uinitrd}
uenv_boot_cmd

        ;;
esac

}

function dl_xload_uboot {
 mkdir -p ${TEMPDIR}/dl/${DIST}
 mkdir -p ${DIR}/dl/${DIST}

 MIRROR="http://rcn-ee.net/deb/"

 echo ""
 echo "1 / 9: Downloading X-loader and Uboot"

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}tools/latest/bootloader

 if [ "$BETA" ];then
  ABI="ABX"
 else
  ABI="ABI"
 fi

 if [ "$USE_UENV" ];then
  boot_uenv_txt_template
 else
  boot_files_template
  boot_scr_to_uenv_txt
 fi

if test "-$ADDON-" = "-pico-"
then
 VIDEO_TIMING="640x480MR-16@60"
fi

 if test "-$ADDON-" = "-ulcd-"
 then
 VIDEO_TIMING="800x480MR-16@60"
 fi

 if [ "$SVIDEO_NTSC" ];then
  VIDEO_DRV="omapfb.mode=tv"
  VIDEO_TIMING="ntsc"
  VIDEO_OMAPFB_MODE=tv
 fi

 if [ "$SVIDEO_PAL" ];then
  VIDEO_DRV="omapfb.mode=tv"
  VIDEO_TIMING="pal"
  VIDEO_OMAPFB_MODE=tv
 fi

 #Set uImage boot address
 sed -i -e 's:UIMAGE_ADDR:'$UIMAGE_ADDR':g' ${TEMPDIR}/*.cmd

 #Set uInitrd boot address
 sed -i -e 's:UINITRD_ADDR:'$UINITRD_ADDR':g' ${TEMPDIR}/*.cmd

 #Set the Serial Console
 sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/*.cmd

 #Set filesystem type
 sed -i -e 's:FSTYPE:'$RFS':g' ${TEMPDIR}/*.cmd

if [ "$SERIAL_MODE" ];then
 sed -i -e 's:VIDEO_CONSOLE::g' ${TEMPDIR}/*.cmd
 sed -i -e 's:VIDEO_RAM ::g' ${TEMPDIR}/*.cmd
 sed -i -e "s/VIDEO_DEVICE:VIDEO_MODE //g" ${TEMPDIR}/*.cmd
else
 #Enable Video Console

 #set console video: console=tty0
 sed -i -e 's:VIDEO_CONSOLE:'$VIDEO_CONSOLE':g' ${TEMPDIR}/*.cmd

 sed -i -e 's:VIDEO_RAM:'vram=\${vram}':g' ${TEMPDIR}/*.cmd
 sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/*.cmd
 sed -i -e 's:VIDEO_DEVICE:'$VIDEO_DRV':g' ${TEMPDIR}/*.cmd

 #set OMAP video: omapfb.mode=VIDEO_OMAPFB_MODE
 sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/*.cmd

 if [ "$SVIDEO_NTSC" ] || [ "$SVIDEO_PAL" ];then
  sed -i -e 's:VIDEO_MODE:'\${dvimode}' omapdss.def_disp=tv:g' ${TEMPDIR}/*.cmd
 else
  sed -i -e 's:VIDEO_MODE:'\${dvimode}':g' ${TEMPDIR}/*.cmd
 fi

fi

 if [ "$PRINTK" ];then
  sed -i 's/bootargs/bootargs earlyprintk/g' ${TEMPDIR}/*.cmd
 fi

echo ""
echo "Debug: U-Boot boot script"
echo ""
echo "-----------------------------"
cat ${TEMPDIR}/*.cmd
echo "-----------------------------"
echo ""

if [ "${HASMLO}" ] ; then
 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:MLO" | awk '{print $2}')
 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
 MLO=${MLO##*/}
fi

 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:UBOOT" | awk '{print $2}')
 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
 UBOOT=${UBOOT##*/}

}

function cleanup_sd {

 echo ""
 echo "2 / 9: Unmountting Partitions"

 NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

 for (( c=1; c<=$NUM_MOUNTS; c++ ))
 do
  DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
  umount ${DRIVE} &> /dev/null || true
 done

parted --script ${MMC} mklabel msdos
}

function create_partitions {

echo ""
echo "3 / 9: Creating Boot Partition"
fdisk ${FDISK_DOS} ${MMC} << END
n
p
1
1
+64M
t
e
p
w
END

sync

parted --script ${MMC} set 1 boot on

if [ "$FDISK_DEBUG" ];then
 echo "Debug: Partition 1 layout:"
 fdisk -l ${MMC}
fi

echo ""
echo "5 / 9: Formatting Boot Partition"
mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}

}

function populate_boot {
 echo ""
 echo "7 / 9: Populating Boot Partition"
 partprobe ${MMC}
 mkdir -p ${TEMPDIR}/disk

 if mount -t vfat ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

 if [ "$DO_UBOOT" ];then
  if [ "${HASMLO}" ] ; then
   if ls ${TEMPDIR}/dl/${MLO} >/dev/null 2>&1;then
    cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
   fi
  fi

  if ls ${TEMPDIR}/dl/${UBOOT} >/dev/null 2>&1;then
   if echo ${UBOOT} | grep img > /dev/null 2>&1;then
    cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
   else
    cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin
   fi
  fi
 fi

if [ "$SECONDARY_KERNEL" ];then
 if ls ${DIR}/vmlinuz-*d* >/dev/null 2>&1;then
  VER="d"
 elif ls ${DIR}/vmlinuz-*psp* >/dev/null 2>&1;then
  VER="psp"
 else
  VER="x"
 fi
else
 VER="x"
fi

 if ls ${DIR}/vmlinuz-*${VER}* >/dev/null 2>&1;then
  LINUX_VER=$(ls ${DIR}/vmlinuz-*${VER}* | awk -F'vmlinuz-' '{print $2}')
  echo "uImage"
  mkimage -A arm -O linux -T kernel -C none -a 0x80008000 -e 0x80008000 -n ${LINUX_VER} -d ${DIR}/vmlinuz-*${VER}* ${TEMPDIR}/disk/uImage
 fi

 if ls ${DIR}/initrd.img-*${VER}* >/dev/null 2>&1;then
  echo "uInitrd"
  mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/initrd.img-*${VER}* ${TEMPDIR}/disk/uInitrd
 fi

if [ "$DO_UBOOT" ];then

 if ls ${TEMPDIR}/boot.cmd >/dev/null 2>&1;then
 mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d ${TEMPDIR}/boot.cmd ${TEMPDIR}/disk/boot.scr
 cp ${TEMPDIR}/boot.cmd ${TEMPDIR}/disk/boot.cmd
 rm -f ${TEMPDIR}/boot.cmd || true
 fi

 if ls ${TEMPDIR}/user.cmd >/dev/null 2>&1;then
 mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d ${TEMPDIR}/user.cmd ${TEMPDIR}/disk/user.scr
 cp ${TEMPDIR}/user.cmd ${TEMPDIR}/disk/user.cmd
 rm -f ${TEMPDIR}/user.cmd || true
 fi

 if ls ${TEMPDIR}/uEnv.cmd >/dev/null 2>&1;then
 cp ${TEMPDIR}/uEnv.cmd ${TEMPDIR}/disk/uEnv.txt
 rm -f ${TEMPDIR}/uEnv.cmd || true
 fi

fi

cd ${TEMPDIR}/disk
sync
cd ${DIR}/
umount ${TEMPDIR}/disk || true

	echo ""
	echo "Finished populating Boot Partition"
else
	echo ""
	echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
	echo "Please retry running the script, sometimes rebooting your system helps."
	echo ""
	exit
fi

}

function check_mmc {

 FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "fdisk -l:"
  LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
  [ "$REPLY" == "y" ] || exit
  echo ""
 else
  echo ""
  echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
  echo ""
  echo "fdisk -l:"
  LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function is_omap {
 HASMLO=1
 UIMAGE_ADDR="0x80200000"
 UINITRD_ADDR="0x80A00000"
 SERIAL_CONSOLE="${SERIAL},115200n8"
 ZRELADD="0x80008000"
 SUBARCH="omap"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_DRV="omapfb.mode=dvi"
 VIDEO_OMAPFB_MODE="dvi"
 VIDEO_TIMING="1280x720MR-16@60"
}

function is_imx53 {
 UIMAGE_ADDR="0x70800000"
 UINITRD_ADDR="0x72100000"
 SERIAL_CONSOLE="${SERIAL},115200"
 ZRELADD="0x70008000"
 SUBARCH="imx"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_DRV="mxcdi1fb"
 VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
 unset DO_UBOOT

case "$UBOOT_TYPE" in
    beagle_bx)

 SYSTEM=beagle_bx
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=1
 SERIAL="ttyO2"
 USE_UENV=1
 is_omap

        ;;
    beagle)

 SYSTEM=beagle
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=7
 SERIAL="ttyO2"
 USE_UENV=1
 is_omap

        ;;
    bone)

 SYSTEM=bone
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=10
 SERIAL="ttyO0"
 USE_UENV=1
 is_omap
 SECONDARY_KERNEL=1
 unset VIDEO_OMAPFB_MODE
 unset VIDEO_TIMING

        ;;
    igepv2)

 SYSTEM=igepv2
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=3
 SERIAL="ttyO2"
 is_omap

        ;;
    panda)

 SYSTEM=panda
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=2
 SERIAL="ttyO2"
 is_omap

        ;;
    touchbook)

 SYSTEM=touchbook
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=5
 SERIAL="ttyO2"
 is_omap
 VIDEO_TIMING="1024x600MR-16@60"

        ;;
    crane)

 SYSTEM=crane
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=6
 SERIAL="ttyO2"
 is_omap

        ;;
esac

 if [ "$IN_VALID_UBOOT" ] ; then
   usage
 fi
}

function check_addon_type {
 IN_VALID_ADDON=1

case "$ADDON_TYPE" in
    pico)

 ADDON=pico
 unset IN_VALID_ADDON

        ;;
    ulcd)

 ADDON=ulcd
 unset IN_VALID_ADDON

        ;;
esac

 if [ "$IN_VALID_ADDON" ] ; then
   usage
 fi
}

function usage {
    echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>
    Unformated MMC Card

Additional/Optional options:
-h --help
    this help

--probe-mmc
    List all partitions

--uboot <dev board>
    beagle_bx - <Ax/Bx Models>
    beagle - <Cx, xM A/B/C>
    bone - <BeagleBone A2>
    panda - <dvi or serial>
    igepv2 - <serial mode only>

--addon <device>
    pico
    ulcd <beagle xm>

--boot_label <boot_label>
    boot partition label

--svideo-ntsc
    force ntsc mode for svideo

--svideo-pal
    force pal mode for svideo

--debug
    enable all debug options for troubleshooting

--fdisk-debug
    debug fdisk/parted/etc..

EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

IN_VALID_UBOOT=1

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --probe-mmc)
            MMC="/dev/idontknow"
            check_root
            check_mmc
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            find_issue
            check_mmc 
            ;;
        --uboot)
            checkparm $2
            UBOOT_TYPE="$2"
            check_uboot_type
            ;;
        --addon)
            checkparm $2
            ADDON_TYPE="$2"
            check_addon_type 
            ;;
        --svideo-ntsc)
            SVIDEO_NTSC=1
            ;;
        --svideo-pal)
            SVIDEO_PAL=1
            ;;
        --boot_label)
            checkparm $2
            BOOT_LABEL="$2"
            ;;
        --earlyprintk)
            PRINTK=1
            ;;
        --beta)
            BETA=1
            ;;
        --secondary-kernel)
            SECONDARY_KERNEL=1
            ;;
        --debug)
            DEBUG=1
            ;;
        --fdisk-debug)
            FDISK_DEBUG=1
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    echo "ERROR: --mmc undefined"
    usage
fi

if [ "$IN_VALID_UBOOT" ] ; then
    echo "ERROR: --uboot undefined"
    usage
fi

 find_issue
 detect_software

if [ "$DO_UBOOT" ];then
 dl_xload_uboot
fi
 cleanup_sd
 create_partitions
 populate_boot

