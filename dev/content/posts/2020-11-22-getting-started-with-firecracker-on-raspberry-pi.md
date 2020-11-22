---
title: Getting started with Firecracker on Raspberry Pi
date: 2020-11-22T14:25:21+01:00
draft: false
description: Firecracker is an open source virtualisation technology for creating and managing secure, multi-tenant container services.
tags:
  - containerisation
  - virtualisation
  - linux
  - cgroups
  - cloud
---

## Abstract

Traditionally services were deployed on bare metal and in the last decades we have seen the rise of virtualisation (running additional operating systems in a operating system process) and lately containerisation (running an operating system process in a separate security context from the rest of processes on the same host). Virtualisation and containerisation offers different levels of isolation by moving some operating system functionality to the guest systems.

The following chart illustrates that pretty well:

![OS functionality location](https://dev.l1x.be/img/isolation.png)

Source: https://research.cs.wisc.edu/multifacet/papers/vee20_blending.pdf

In this article, I perform a deep dive into Firecracker and how it can be used for deploying services on Raspberry Pi (4B).

## Getting started

There are few paths to take here. First I am going to try the easy one, using Ubuntu. Later on we can investigate the use of Alpine Linux which is much more lightweight than Ubuntu, ideal for devices like RPI.

### Installing the image on a microSD card

We need a 64 bit Ubuntu image and a microsd card. For the imaging I use [Balena Etcher](https://www.balena.io/etcher/) that makes the imaging process super easy.

Getting the pre-installed image:

```bash
wget https://cdimage.ubuntu.com/releases/20.04/release/\
ubuntu-20.04.1-preinstalled-server-arm64+raspi.img.xz
```

Preinstalled means that we get a fully working operating system and there is no need for additional installation steps after booting up. With Balena Etcher it is super easy to write the compressed image file to the sd card and boot the system up once ready. SSHD starts up after the installation and we can log in via ssh if we know the IP address that the DHCP server issues to our device (assuming DHCP server is present in our LAN).

There are few mildly annoying things with Ubuntu (snaps, unattended-upgrades) that I usually remove. I also prefer to use Chrony over the systemd equivalent. Ansible repo for these is available here: https://github.com/l1x/rpi/blob/main/ubuntu.20/ansible/roles/os/tasks/main.yml

### Installing Firecracker, Jailer and Firectl

- Firecracker: The main component, it is a virtual machine monitor (VMM) that uses the Linux Kernel Virtual Machine (KVM) to create and run microVMs.
- Jailer: For starting Firecracker in production mode, applies a cgroup/namespace isolation barrier and then drops privileges. There
- Firectl: A command line utility for convenience

#### Getting Firecracker and Jailer

For the first two it is possible to download the release binaries from Github.

```bash
version='v0.23.0'

wget https://github.com/firecracker-microvm/firecracker/\
releases/download/${version}/firecracker-${version}-aarch64
wget https://github.com/firecracker-microvm/firecracker/\
releases/download/${version}/jailer-${version}-aarch64

mv firecracker-${version}-aarch64 firecracker
mv jailer-${version}-aarch64 jailer

chmod +x firecracker jailer

./firecracker --help
./jailer --help
```

#### Firectl

Firectl is a bit trickier to install because there is no release binary and it requires Golang 1.14 to compile. We can do these in two steps.

```bash
wget https://golang.org/dl/go1.14.12.linux-arm64.tar.gz
tar xzvf go1.14.12.linux-arm64.tar.gz
```

After getting go we can get the source of firectl and compile it:

```bash
git clone https://github.com/firecracker-microvm/firectl.git
cd firectl/
 ~/go/bin/go build -x
```

Testing Firectl:

```bash
./firectl --help
```

We have all the tools we need for running our first microVM the only thing is missing: something to run.

### Downloading our first image

For a microVM there are two things necessary to have:

- an uncompressed linux kernel (vmlinux)
- a filesystem

Later on we are going to investigate how we could create our own version of these, but for now we are going to use images from

```bash
wget https://s3.amazonaws.com/spec.ccfc.min/\
img/aarch64/ubuntu_with_ssh/kernel/vmlinux.bin
wget https://s3.amazonaws.com/spec.ccfc.min/\
img/aarch64/ubuntu_with_ssh/fsfiles/xenial.rootfs.ext4
```

### Configuring network

For the microVM to function properly we need a networking device. For this scenario we are going to use tap and create a device:

```bash
sudo ip tuntap add dev tap0 mode tap
sudo ip addr add 172.16.0.1/24 dev tap0
sudo ip link set tap0 up
ip addr show dev tap0
```

If we want to give access to our VM we have to enable IP forwarding:

```bash
DEVICE_NAME=eth0
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo iptables -t nat -A POSTROUTING -o $DEVICE_NAME -j MASQUERADE
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i tap0 -o $DEVICE_NAME -j ACCEPT
```

### Running our first microVM

This is how we can start up our first microVM. I usually start it in screen so I can open a new session easily because it will use the standard input and output for the newly started of console (unless you redirect it).

This is for debug mode, starting with sudo:

```bash
sudo ./firectl/firectl \
--firecracker-binary=./firecracker \
--kernel=vmlinux.bin \
--tap-device=tap0/aa:fc:00:00:00:01 \
--kernel-opts="console=ttyS0 reboot=k panic=1 pci=off ip=172.16.0.42::172.16.0.1:255.255.255.0::eth0:off" \
--root-drive=./xenial.rootfs.ext4
```

If everything went well you can see something like this:

```
Ubuntu 18.04.2 LTS fadfdd4af58a ttyS0

fadfdd4af58a login:
```

User and password is root:root.

### Testing networking

For this we need to have a bit bigger image.

```bash
dd if=/dev/zero bs=1M count=800 >> xenial.rootfs.ext4
resize2fs -f xenial.rootfs.ext4
```

After starting up the usual way and logging in we need to fix few things:

Adding some working nameserver:

```bash
echo 'nameserver 1.1.1.1' >  /etc/resolv.conf
```

Now trying to update:

```bash
root@fadfdd4af58a:~# apt update
Get:1 http://ports.ubuntu.com/ubuntu-ports bionic InRelease [242 kB]
Get:2 http://ports.ubuntu.com/ubuntu-ports bionic-updates InRelease [88.7 kB]
Hit:3 http://ports.ubuntu.com/ubuntu-ports bionic-backports InRelease
Hit:4 http://ports.ubuntu.com/ubuntu-ports bionic-security InRelease
Get:5 http://ports.ubuntu.com/ubuntu-ports bionic/universe arm64 Packages [11.0 MB]
Get:6 http://ports.ubuntu.com/ubuntu-ports bionic/multiverse arm64 Packages [153 kB]
Get:7 http://ports.ubuntu.com/ubuntu-ports bionic/main arm64 Packages [1285 kB]
Get:8 http://ports.ubuntu.com/ubuntu-ports bionic/restricted arm64 Packages [572 B]
Get:9 http://ports.ubuntu.com/ubuntu-ports bionic-updates/universe arm64 Packages [1865 kB]
Get:10 http://ports.ubuntu.com/ubuntu-ports bionic-updates/restricted arm64 Packages [2262 B]
Get:11 http://ports.ubuntu.com/ubuntu-ports bionic-updates/main arm64 Packages [1431 kB]
Get:12 http://ports.ubuntu.com/ubuntu-ports bionic-updates/multiverse arm64 Packages [5758 B]
Fetched 16.1 MB in 6s (2543 kB/s)
Reading package lists... Error!
E: flAbsPath on /var/lib/dpkg/status failed - realpath (2: No such file or directory)
E: Could not open file  - open (2: No such file or directory)
E: Problem opening
E: The package lists or status file could not be parsed or opened.
```

Fixing the apt issues:

```bash
mkdir -p /var/lib/dpkg/{info,alternatives}
touch /var/lib/dpkg/status
apt install apt-utils -y
```

Enjoy!

Next time we can go through how to compile a new kernel and have a different rootfs (potentially using Alpine).
