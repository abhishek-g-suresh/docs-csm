# Manage Multiple Inventories in a Single Location

Many configuration layers may be present in a single configuration for larger systems that configure multiple Cray products. When
values for each of these layers need to be customized, it can be tedious to override values in each of the respective repositories.
The CFS `additionalInventoryUrl` option allows for static inventory files to be automatically added to the hosts directory of each
configuration layer before it is applied by Ansible. It is then possible to add this additional Ansible inventory information to all
configuration sessions so it can be used simultaneously with other inventory types, including the CFS dynamic inventory type, across
all configuration layers in a session.

The `additionalInventoryUrl` option is optional and is set on a global CFS level. If provided, it must be set to the URL of a Git
repository containing inventory files in the base directory of the repository. For ordering purposes, any inventory generated by CFS
will also be placed in this directory with the name `01-cfs-generated.yaml`. For more information, see the
[Dynamic Inventory and Host Groups](Ansible_Inventory.md#dynamic-inventory-and-host-groups)
section in [Ansible Inventory](Ansible_Inventory.md).

The following is an example of an inventory repository:

```text
02-static-inventory.ini
03-my-dynamic-inventory.py
group_vars/...
host_vars/...
```

CFS will provide the following inventory to Ansible when running a configuration session:

```text
hosts/01-cfs-generated.yaml
hosts/02-static-inventory.ini
hosts/03-my-dynamic-inventory.py
hosts/group_vars/...
hosts/host_vars/...
```

CFS will clone the additional inventory Git repository and use the default branch \(usually master\) to populate the hosts directory.
Only one inventory repository can be specified, and it will apply to all CFS sessions.

(`ncn-mw#`) Use the following command to set the `additionalInventoryUrl` value:

```bash
cray cfs options update --additional-inventory-url https://api-gw-service-nmn.local/vcs/cray/inventory.git
```

(`ncn-mw#`) Use the following command to unset the `additionalInventoryUrl` value:

```bash
cray cfs options update --additional-inventory-url ""
```
