---
title: FreeNAS 11.3 upgrade issues
date: 2020-04-29T14:31:21+02:00
draft: false
description: How to roll back to a previous version
tags: 
  - freebsd
  - freenas 
  - rollback 
  - jail
---

I have an interesting experience with the latest upgrade of FreeNAS 11.3-U2.1. Applications that were deployed in the jail were gone. After fiddling with iocage (the tool that FreeNAS provides to manage jails) I could restore a previous state where all seems fine and dandy.

## Steps to restore

- list of snapshots

```bash
iocage snaplist tr -l
+-------------------------------------------------------------------------+-----------------------+-------+-------+
|                                  NAME                                   |        CREATED        | RSIZE | USED  |
+=========================================================================+=======================+=======+=======+
| fux/iocage/jails/tr/root@ioc_plugin_update_2020-04-29                   | Wed Apr 29 14:55 2020 | 799G  | 11.6K |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
| fux/iocage/jails/tr/root@ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-07 | Wed Apr 29 14:55 2020 | 799G  | 575K  |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
| fux/iocage/jails/tr/root@ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-22 | Wed Apr 29 14:55 2020 | 799G  | 11.6K |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
| fux/iocage/jails/tr@ioc_plugin_update_2020-04-29                        | Wed Apr 29 14:55 2020 | 517K  | 81.4K |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
| fux/iocage/jails/tr@ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-07      | Wed Apr 29 14:55 2020 | 517K  | 81.4K |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
| fux/iocage/jails/tr@ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-22      | Wed Apr 29 14:55 2020 | 517K  | 81.4K |
+-------------------------------------------------------------------------+-----------------------+-------+-------+
```

- stop the jail

```bash
root@freenas[~]# iocage stop tr
* Stopping tr
  + Executing prestop OK
  + Stopping services OK
  + Tearing down VNET OK
  + Removing devfs_ruleset: 5 OK
  + Removing jail process OK
  + Executing poststop OK
```

- rollback

```bash
root@freenas[~]# iocage rollback tr -n ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-07

This will destroy ALL data created including ALL snapshots taken after the snapshot ioc_update_11.3-RELEASE-p8_2020-04-29_14-55-07

Are you sure? [y/N]: y
Rolled back to: fux/iocage/jails/tr
```

- start the jail

```bash
root@freenas[~]# iocage start tr
No default gateway found for ipv6.
* Starting tr
  + Started OK
  + Using devfs_ruleset: 5
  + Configuring VNET OK
  + Using IP options: vnet
  + Starting services OK
  + Executing poststart OK
  + DHCP Address: 192.168.1.111/24
```

And we are back. 
