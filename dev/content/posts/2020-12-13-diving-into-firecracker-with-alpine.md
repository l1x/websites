---
title: Diving into Firecracker with Alpine
date: 2020-12-13T20:13:21+01:00
draft: true
description: Firecracker is an open source virtualisation technology for creating and managing secure, multi-tenant container services.
tags:
  - containerisation
  - virtualisation
  - linux
  - cgroups
  - cloud
---

## Article series

1st part :: https://dev.l1x.be/posts/2020/11/22/getting-started-with-firecracker-on-raspberry-pi/
2nd part :: this

## Intro

Last time in the 1st article I briefly introduced Firecracker as a lightweight virtualization / continerization solution for extreme scale (like AWS Lambda functions). This time around I am going to dig a bit deeper into the API and the management of microVMs. I am going to install Alpine on RPI, install Rust and Python, Docker, get the Linux kernel source and compile a new kernel with minimal config, compile our own Firecracker and then create a new rootfs to be able to boot up a guest. Most of these steps are optional, you can use the stock kernel the Firecracker team provides or download Firecracker release from Github.

## Setup Alpine

If you do not care about Alpine on RPI you can jump to the Firecracker section.

I would like to keep going with [Raspberry Pi 4B 8GB](https://amzn.to/2Klb9fx) or [Raspberry Pi 4B 4GB](https://amzn.to/2KeohTO) for many reasons. It is a small system that you can easily hack on without any change on your desktop. It is also an ARM64 (ARM Cortex-A72) system that has great performance even without active cooling. I usually use it with a [alu case](https://amzn.to/3naOS2L) that provides the best heat dispersion and a cool cpu. It has enough CPU power and memory to compile any software including Firecracker, the Linux kernel and more. Since this project is a side project I don't care how long it takes to finish a new kernel, usually finishes within 2 hours (I might get exact timing later).

Another item on my todo list is to get Alpine Linux as both the host and the guest system. For those who do not know Alpine is a small Linux distribution designed for security, simplicity, and resource efficiency. It comes with sane defaults and Musl as its C standard library. Alpine uses its own package-management system, apk-tools, providing super fast package installation. Alpine allows very small system with the minimal installation being be around 130 MB. The init system is the lightweight OpenRC, Alpine does not use systemd. This was the primary reason I wanted to get into Alpine.

### Installing Alpine on RPI 4

This is the most complicated part of the setup because RPI has a special boot procedure that uses a FAT partition and the GPU. When installing Alpine first you need to create a FAT partition on the beginning of the SD card with MBR. I am using MacOS this time. I am pretty sure it is easy to translate this to Linux (not sure about Windows.)

#### Creating the partition

My microSD card is /dev/disk6. I create a partition with the name ALP (1024MB), then activate it with fdisk.

```bash
diskutil list
diskutil partitionDisk /dev/disk6 MBR "FAT32" ALP 1024MB "Free Space" SYS R
sudo fdisk -e /dev/disk6
> f 1
> w
> exit
```

After this command runs successfully MacOS mounts the newly created partition in /Volumes/ALP.

#### Downloading Alpine and writing it to the SD card

You can initiate the download anywhere, make sure the previously created partition is mounted.

```bash
wget http://dl-cdn.alpinelinux.org/alpine/v3.12/releases/aarch64/alpine-rpi-3.12.1-aarch64.tar.gz
tar xzvf alpine-rpi-3.12.1-aarch64.tar.gz -C /Volumes/ALP/
```

#### Configuring RPI boot

This part is optional, you can disable audio, wifi, bluetooth, etc and enable UART, configure GPU mem. The full documentation is here:

https://www.raspberrypi.org/documentation/configuration/config-txt/

```bash
cd /Volumes/ALP/
echo 'dtparam=audio=off'          >> usercfg.txt
echo 'dtoverlay=pi3-disable-wifi' >> usercfg.txt
echo 'enable_uart=1'              >> usercfg.txt
echo 'gpu_mem=64'                 >> usercfg.txt
echo 'disable_overscan=1'         >> usercfg.txt
```

You are ready to remove the SD card.

```bash
cd
diskutil eject /dev/disk6
```

#### Booting and configuring Alpine

After inserting the SD card into the RPI you can boot it up. I am using a special converter that converts the mini HDMI to a normal HDMI [converter](https://amzn.to/3452Ziz) that makes it easy to connect a TV or a monitor to the PI. I usually connect the device to the network with an ethernet cable and plug in a wired USB keyboard.

Once the device is booting up you can login with root (no password).

Alpine has a neat tool to configure a new system. It asks few questions about keyboard layout and timezone, also makes you create a root password.

```bash
setup-alpine
```

Once setup-alpine is done you need to change few things around because up to this moment you operated on the FAT partition. After updating the system and adding cfdisk you can create a new partition and use the remaning space on the SD card to have a proper system. In cfdisk, select “Free space” and the option “New”. It suggests using the entire available space, just press enter, then select the option “primary”, followed by “Write”. Type “yes” to write the partition table to disk, then select “Quit”.

```bash
apk update
apk upgrade
apk add cfdisk e2fsprogs
cfdisk /dev/mmcblk0
```

Once our new partition is ready you need to create a filesystem on it and install a basic Alpine system with setup-disk. In "sys" mode, it's an installer, it permanently installs Alpine on the disk. Ignore the errors, there might be some while executing setup-disk.

```bash
mkfs.ext4 /dev/mmcblk0p2
mount /dev/mmcblk0p2 /mnt
setup-disk -m sys /mnt
mount -o remount,rw /media/mmcblk0p1
```

This section is what I found on the Alpine wiki and it works. There might be an easier way.

```bash
rm -f /media/mmcblk0p1/boot/*
cd /mnt
rm boot/boot
mv boot/* /media/mmcblk0p1/boot/
rm -Rf boot
mkdir media/mmcblk0p1
ln -s media/mmcblk0p1/boot boot
```

There are only two steps left, adjusting fstab and cmdline.txt.

Fstab:

```bash
UUID=your-uui-id                                /                       ext4    rw,relatime     0 0
/dev/mmcblk0p1                                  /media/mmcblk0p1        vfat    rw              0 0
```

Add the following content to etc/fstab (please note no starting /).

```bash
vi etc/fstab
```

Appending the following to the cmdline.txt:

```bash
root=/dev/mmcblk0p2
```

```bash
vi /media/mmcblk0p1/cmdline.txt
```

It looks like this for me:

```bash
cat /media/mmcblk0p1/cmdline.txt
modules=loop,squashfs,sd-mod,usb-storage quiet console=tty1 root=/dev/mmcblk0p2
```

I am not sure if lbu commit is necessary here. When Alpine Linux boots in diskless mode, initially it only loads a few required packages from the boot device by default. But local adjustments in RAM are possible, e.g. by installing a package or adjusting some configuration.

```bash
lbu commit -d
```

You can reboot and log in with root and verify everything is working. Going forward it is best to have a user other than root.

```bash
adduser l1x
addgroup l1x wheel
```

I usually add the following packages and start to use sudo going forward:

```bash
sudo apk add tmux fish ninja clang g++ sudo git python3 socat curl vim procps
```

Make sure that wheel group can use sudo:

```bash
%wheel ALL=(ALL) NOPASSWD: ALL
```

Changing my shell to fish:

```bash
l1x:x:1000:1000:Linux User,,,:/home/l1x:/usr/bin/fish
```

Hopefully by now you have a working envirment. I use a bigger drive for /data where I store all the development folders.

```bash
l1x@alpine ~> mount | column -t | egrep '^/dev'
/dev/mmcblk0p2  on  /                          type  ext4        (rw,relatime)
/dev/mmcblk0p1  on  /media/mmcblk0p1           type  vfat        (rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,errors=remount-ro)
/dev/sda1       on  /data                      type  xfs         (rw,relatime,attr2,inode64,logbufs=8,logbsize=32k,noquota)
```

## Setting up Firecracker dev environment

Once you logged in via SSH to your Alpine system make sure you have the dev tools you are going to need. I usually use the following tools, and some more:

```bash
sudo apk add tmux git python3 curl vim
```

I was trying to figure out how to install Rust on ARM64 linux and the most straightforward way looks like:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

If you want to compile Firecracker yourself you also need Docker. Docker for this version of Alpine lives in the community repo. Simple append the community line to your repositories:

```bash
cat /etc/apk/repositories
#/media/mmcblk0p1/apks
http://your.nearest.mirror/mirrors/pub/alpine/v3.12/main
http://your.nearest.mirror/mirrors/pub/alpine/v3.12/community
```

Installing Docker:

```bash
sudo apk add docker
sudo addgroup $USER docker
sudo rc-update add docker boot
sudo service docker start
```

After Docker is running you can clone the Firecracker repo:

```bash
git clone git@github.com:firecracker-microvm/firecracker.git
```

Before you can compile a release you need to install two more packages:

```bash
sudo apk add bash ncurses
```

Now

## Create a microVM

## Closing
