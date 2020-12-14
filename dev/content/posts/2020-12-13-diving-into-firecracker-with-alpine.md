---
title: Diving into Firecracker with Alpine
date: 2020-12-13T23:02:21+01:00
draft: false
description: Firecracker is an open source virtualisation technology for creating and managing secure, multi-tenant container services.
tags:
  - containerisation
  - virtualisation
  - linux
  - cgroups
  - cloud
---

## Article series

- 1st part :: https://dev.l1x.be/posts/2020/11/22/getting-started-with-firecracker-on-raspberry-pi/
- 2nd part :: this

## Intro

Last time in the 1st article I briefly introduced Firecracker as a lightweight virtualization/containerization solution for extreme-scale (like AWS Lambda functions). This time around I am going to dig a bit deeper into the API and the management of microVMs. I am going to install Alpine on RPI, install Rust and Python, Docker, get the Linux kernel source and compile a new kernel with minimal config, compile our own Firecracker and then create a new rootfs to be able to boot up a guest. Most of these steps are optional, you can use the stock kernel the Firecracker team provides or download Firecracker release from Github.

## Setup Alpine

If you do not care about Alpine on RPI you can jump to the Firecracker section.

I would like to keep going with [Raspberry Pi 4B 8GB](https://amzn.to/2Klb9fx) or [Raspberry Pi 4B 4GB](https://amzn.to/2KeohTO) for many reasons. It is a small system that you can easily hack on without any change on your desktop. It is also an ARM64 (ARM Cortex-A72) system that has great performance even without active cooling. I usually use it with a [alu case](https://amzn.to/3naOS2L) that provides the best heat dispersion and a cool CPU. It has enough CPU power and memory to compile any software including Firecracker, the Linux kernel, and more. Since this project is a side project I don't care how long it takes to finish a new kernel, usually finishes within 2 hours (I might get exact timing later).

Another item on my to-do list is to get Alpine Linux as both the host and the guest system. For those who do not know Alpine is a small Linux distribution designed for security, simplicity, and resource efficiency. It comes with sane defaults and Musl as its C standard library. Alpine uses its own package management system, apk-tools, providing super-fast package installation. Alpine allows a very small system with minimal installation being around 130 MB. The init system is the lightweight OpenRC, Alpine does not use systemd. This was the primary reason I wanted to get into Alpine.

### Installing Alpine on RPI 4

This is the most complicated part of the setup because RPI has a special boot procedure that uses a FAT partition and the GPU. When installing Alpine first you need to create a FAT partition at the beginning of the SD card with MBR. I am using MacOS this time. I am pretty sure it is easy to translate this to Linux (not sure about Windows.)

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

This part is optional, you can disable audio, wifi, Bluetooth, etc and enable UART, configure GPU mem. The full documentation is here:

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

Alpine has a neat tool to configure a new system. It asks a few questions about keyboard layout and timezone, also makes you create a root password.

```bash
setup-alpine
```

Once setup-alpine is done you need to change a few things around because up to this moment you operated on the FAT partition. After updating the system and adding cfdisk you can create a new partition and use the remaining space on the SD card to have a proper system. In cfdisk, select “Free space” and the option “New”. It suggests using the entire available space, just press enter, then select the option “primary”, followed by “Write”. Type “yes” to write the partition table to disk, then select “Quit”.

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
UUID=your-uui-id  /                 ext4  rw,relatime  0 0
/dev/mmcblk0p1    /media/mmcblk0p1  vfat  rw           0 0
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

Hopefully, by now you have a working environment. I use a bigger drive for /data where I store all the development folders.

```bash
l1x@alpine ~> mount | column -t | egrep '^/dev'
/dev/mmcblk0p2  on  /                 type  ext4        (rw,relatime)
/dev/mmcblk0p1  on  /media/mmcblk0p1  type  vfat        (rw,relatime,fmask=0022,dmask=0022,codepage=437,...)
/dev/sda1       on  /data             type  xfs         (rw,relatime,attr2,inode64,logbufs=8,logbsize=32k,...)
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

If you want to compile Firecracker yourself you also need Docker. Docker for this version of Alpine lives in the community repo. Simply append the community line to your repositories:

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

Now you can compile the Firecracker binaries:

```bash
./tools/devtool build --release --libc musl
[Firecracker devtool] About to pull docker image fcuvm/dev:v24
[Firecracker devtool] Continue? (y/n) y
Digest: sha256:12b8efe9a91d31349a6241b7d81c26d50bf913e369b5845a921be720e5de5796
Status: Downloaded newer image for fcuvm/dev:v24
docker.io/fcuvm/dev:v24
[Firecracker devtool] Starting build (release, musl) ...


```

There are few binaries generated:

```bash
ls build/cargo_target/aarch64-unknown-linux-musl/release/{firecracker,jailer}
 build/cargo_target/aarch64-unknown-linux-musl/release/firecracker*
 build/cargo_target/aarch64-unknown-linux-musl/release/jailer*
file build/cargo_target/aarch64-unknown-linux-musl/release/{firecracker,jailer}
build/cargo_target/aarch64-unknown-linux-musl/release/firecracker:
ELF 64-bit LSB executable, ARM aarch64, version 1 (GNU/Linux),
statically linked, BuildID[sha1]=4da58d970ac0c51aad276309866f2b701cc397cd, with debug_info, not stripped
build/cargo_target/aarch64-unknown-linux-musl/release/jailer:
ELF 64-bit LSB executable, ARM aarch64, version 1 (GNU/Linux),
statically linked, BuildID[sha1]=3e3c780b4e0fbd74b661c54f11192f9a15b89cba, with debug_info, not stripped
```

Using these binaries we can create the VMs.

## Creating a microVM

Before getting started, there are multiple ways to start a microVM with Firecracker. Here are a few:

- starting up the Firecracker binary and through the Unix socket configure it and then start a VM
- starting Firecracker with a complete VM config without the Unix socket API
- starting Firecracker with Jailer so it uses cgroups to containerize the VM

We are going to check out the first way.

When I started to fiddle with FC I was trying to use the official CLI (Firectl) and because it is written in Go you need to have a Go compiler if you would like to build it yourself. I did not like this option too much so I have created a new CLI called [Pattacu](https://github.com/l1x/pattacu) written in Python.

### Compiling a new kernel

This is optional. You can download the official kernel from Firecracker:

https://github.com/firecracker-microvm/firecracker/blob/master/docs/rootfs-and-kernel-setup.md

If you decided to compile a new Linux kernel there are few things you need to have.

- kernel-source
- tools to compile

I usually use one of the long term releases:

- https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.212.tar.xz
- https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.163.tar.xz
- https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.83.tar.xz

After extracting the kernel source to a folder you can grab the config I have prepared with some help from an OpenWrt developer:

```bash
wget https://raw.githubusercontent.com/l1x/pattacu/main/kernel-config/microvm-kernel-arm64.4.19.config -O .config
```

There are more tools required for building a new kernel:

```bash
sudo apk add bison clang make flex linux-headers openssl-dev perl
```

With these the kernel can be compiled:

```bash
make olddefconfig
time make Image.gz
```

This is going to take a while. After that, the kernel file we need for the microVM will be arch/arm64/boot/Image.

### Creating a new rootfs

This is optional. You can download the official rootfs from Firecracker:

https://github.com/firecracker-microvm/firecracker/blob/master/docs/rootfs-and-kernel-setup.md

There is a project that can be used to create an Alpine rootfs. With a bit of additional shell scripting, we can create a customized rootfs that can boot up in Firecracker.

```bash
wget https://raw.githubusercontent.com/alpinelinux/alpine-make-rootfs/v0.5.1/alpine-make-rootfs -O alpine-make-rootfs \
  && echo 'a7159f17b01ad5a06419b83ea3ca9bbe7d3f8c03 alpine-make-rootfs' | sha1sum -c \
  || exit 1
chmod +x alpine-make-rootfs
sudo ./alpine-make-rootfs \
  --branch v3.12 \
  --packages 'openrc util-linux' \
  --timezone 'Europe/Budapest' \
  --script-chroot \
    rootfs-$(date +%Y%m%d).tar.gz - <<'SHELL'
    ln -s agetty /etc/init.d/agetty.ttyS0
    echo ttyS0 > /etc/securetty
    echo 'nameserver 1.1.1.1' > /etc/resolv.conf
    rc-update add agetty.ttyS0 default
    rc-update add devfs boot
    rc-update add procfs boot
    rc-update add sysfs boot
SHELL

dd if=/dev/zero of=alpine.ext4 bs=1 count=1 seek=256M
mkfs.ext4 alpine.ext4
sudo mkdir /tmp/alpine-rootfs
sudo mount alpine.ext4 /tmp/alpine-rootfs
sudo tar xzvf rootfs-$(date +%Y%m%d).tar.gz -C /tmp/alpine-rootfs
sudo umount /tmp/alpine-rootfs
```

### Configuring host networking

If you would like to use networking with Firecracker the host network has to be configured to support this.

First loading the kernel driver, installing iproute2 (the ip command):

```bash
modprobe tun
sudo apk add iproute2 acl
sudo ip tuntap add tap0 mode tap
```

Second, configuring networking and forwarding:

```bash
sudo ip addr add 172.16.0.1/24 dev tap0
sudo ip link set tap0 up
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i tap0 -o eth0 -j ACCEPT
```

### Enablig non-root access

I like to run Firecracker as a non-root user and it is easy to achieve:

```bash
sudo setfacl -m u:$USER:rw /dev/kvm
sudo setcap cap_net_bind_service=+ep /usr/bin/socat
```

This gives your user access to /dev/kvm and enabled socat bind to port 80 without root, using the new Linux kernel capabilities.

### Booting up the microVM using Pattacu

For running Pattacu the only dependency is Python3 (I have not tested it with Python2).

```bash
sudo apk add python3
cd
python3 -m venv venv
# Depending on your shell
. ~/venv/bin/activate.fish
cd /where/you/store/repos
git clone git@github.com:l1x/pattacu.git
cd pattacu
pip install -r requirements.txt
./bin/pattacu -h
./bin/pattacu -h
usage: pattacu [-h] {describe-instance,put-boot-source,put-drives,put-machine-config,put-network-interfaces,put-actions} ...

positional arguments:
  {describe-instance,put-boot-source,put-drives,put-machine-config,put-network-interfaces,put-actions}

optional arguments:
  -h, --help            show this help message and exit
2020-12-13 20:35:01 INFO Quitting...
```

For starting up a microVM there are few things to be configured:

- starting Firecracker
- starting socat
- configuring which kernel to boot up as the guest
- configuring which rootfs to be used by the guest
- configuring guest machine config
- configuring guest networking

In this order:

#### Starting Firecracker

```bash
export socket_path=/data/fc/firecracker.socket
rm -f "$socket_path"
./firecracker --api-sock "$socket_path" --level Debug --log-path firecracker.log --show-log-origin --id fc-test
```

#### Starting socat

```bash
socat -v -v TCP-LISTEN:80,reuseaddr,fork UNIX-CLIENT:"$socket_path"
```

#### Configuring which kernel to boot up as the guest

```bash
./bin/pattacu put-boot-source \
	--boot-args "keep_bootcon console=ttyS0 reboot=k panic=1 pci=off ip=172.16.0.42::172.16.0.1:255.255.255.0::eth0:off" \
	--kernel-image-path /linux/arm64/kernel/4.14.210.image

2020-12-13 20:44:12 INFO ARGS: Namespace(boot_args='keep_bootcon console=ttyS0
reboot=k panic=1 pci=off ip=172.16.0.42::172.16.0.1:255.255.255.0::eth0:off', func='put-boot-source',
initrd_path=None, kernel_image_path='/linux/arm64/kernel/4.14.210.image')
2020-12-13 20:44:12 INFO {"boot_args": "keep_bootcon console=ttyS0 reboot=k
panic=1 pci=off ip=172.16.0.42::172.16.0.1:255.255.255.0::eth0:off",
"kernel_image_path": "/linux/arm64/kernel/4.14.210.image"}
2020-12-13 20:44:12 INFO HTTP Status: 204 HTTP Reason:  HTTP body: ""
2020-12-13 20:44:12 INFO Quitting...
```

#### Configuring which rootfs to be used by the guest

```bash
./bin/pattacu put-drives \
  --drive-id rootfs \
  --path /data/pattacu/rootfs/example-20201213.tar.gz \
  --read-only false \
  --root-device true
2020-12-13 20:46:30 INFO ARGS: Namespace(drive_id='rootfs',
func='put-drives', path='/data/pattacu/rootfs/example-20201213.tar.gz', read_only=False, root_device=True)
2020-12-13 20:46:30 INFO {"drive_id": "rootfs", "path_on_host":
"/data/pattacu/rootfs/example-20201213.tar.gz", "is_root_device": true, "is_read_only": false}
2020-12-13 20:46:30 INFO HTTP Status: 204 HTTP Reason:  HTTP body: ""
2020-12-13 20:46:30 INFO Quitting...
```

#### Configuring guest machine config

```bash
./bin/pattacu put-machine-config --mem-size-mib 128 --vcpu-count 2 --ht-enabled false

2020-12-13 20:47:58 INFO ARGS: Namespace(cpu_template=None, func='put-machine-config',
ht_enabled=False, mem_size_mib=128, track_dirty_pages=None, vcpu_count=2)
2020-12-13 20:47:58 INFO {"vcpu_count": 2, "mem_size_mib": 128, "ht_enabled": false}
2020-12-13 20:47:58 INFO HTTP Status: 204 HTTP Reason:  HTTP body: ""
2020-12-13 20:47:58 INFO Quitting...
```

#### Configuring guest networking

```bash
./bin/pattacu put-network-interfaces --iface-id eth0 --guest-mac "AA:FC:00:00:00:01" --host-dev-name tap0
2020-12-13 20:48:57 INFO ARGS: Namespace(func='put-network-interfaces',
guest_mac='AA:FC:00:00:00:01', host_dev_name='tap0', iface_id='eth0')
2020-12-13 20:48:57 INFO {"iface_id": "eth0",
"guest_mac": "AA:FC:00:00:00:01", "host_dev_name": "tap0"}
2020-12-13 20:48:58 INFO HTTP Status: 204 HTTP Reason:  HTTP body: ""
2020-12-13 20:48:58 INFO Quitting...
```

#### Starting up the instance

```bash
./bin/pattacu put-actions --action-type InstanceStart
2020-12-13 20:49:19 INFO ARGS: Namespace(action_type='InstanceStart', func='put-actions')
2020-12-13 20:49:19 INFO {"action_type": "InstanceStart"}
2020-12-13 20:49:20 INFO HTTP Status: 204 HTTP Reason:  HTTP body: ""
2020-12-13 20:49:20 INFO Quitting...
```

You can switch to the other tmux window and see the system booting up.

```bash
[    1.739745] random: fast init done [27/1844] [ ok ]
 * Mounting /sys ... [ ok ]
 * Mounting security filesystem ... [ ok ]
 * Mounting debug filesystem ... [ ok ]
 * Mounting SELinux filesystem ... [ ok ]
 * Mounting persistent storage (pstore) filesystem ... [ ok ]

Welcome to Alpine Linux 3.12
Kernel 4.20.0 on an aarch64 (ttyS0)

172 login: root
Welcome to Alpine!

The Alpine Wiki contains a large number of how-to guides and general
information about administrating Alpine systems.
See <http://wiki.alpinelinux.org/>.

You can set up the system with the command: setup-alpine

You may change this message by editing /etc/motd.

login[840]: root login on 'ttyS0'
172:~# ping hackernews.org
PING hackernews.org (162.255.119.249): 56 data bytes
64 bytes from 162.255.119.249: seq=0 ttl=42 time=180.868 ms
```

## Closing

I think Firecracker has a great potential to be the next platform for containerization especially because of its lean nature. If we could create a reasonable service that hosts FC images that are easy to deploy it could replace Docker easily. I hope it takes off.

```bash
172:~# poweroff
The system is going down NOW!
Sent SIGTERM to all processes
Sent SIGKILL to all processes
Requesting system poweroff
[  202.707132] reboot: Power down
[  202.707132] reboot: Power down
```
