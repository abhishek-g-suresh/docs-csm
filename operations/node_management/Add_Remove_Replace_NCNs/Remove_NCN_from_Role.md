# Remove NCN from Role

## Description

Remove a master, worker, or storage NCN from current roles. Select the procedure below based on the node type, complete the remaining steps to wipe the drives, and then power off the node.

## Procedure

**IMPORTANT:** The following procedures assume that the variables from [the prerequisites section](Add_Remove_Replace_NCNs.md#remove-ncn-prerequisites) have been set.

1. [Remove roles](#1-remove-roles)
    - [Master node](#master-node-remove-roles)
    - [Worker node](#worker-node-remove-roles)
    - [Storage node](#storage-node-remove-roles)
1. [Disable disk boots](#2-disable-disk-boots)
1. [Power off the node](#3-power-off-the-node)
1. [Next step](#next-step)

## 1. Remove roles

### Master node remove roles

#### First master node

Determine if the master node being removed is the first master node.

1. (`ncn-mw#`) Fetch the defined `first-master-hostname`.

    ```bash
    cray bss bootparameters list --hosts Global --format json |jq -r '.[]."cloud-init"."meta-data"."first-master-hostname"'
    ```

    Example output:

    ```text
    ncn-m002
    ```

    - If the node returned is not the one being removed, then skip the substeps here and proceed to
      [Reset Kubernetes on master node being removed](#Reset-Kubernetes-on-master-node-being-removed).
    - ***IMPORTANT:*** The first master node is the node others contact to join the Kubernetes cluster.
      If this is the node being removed, then perform the remaining substeps here in order to promote another
      master node to the initial node, before proceeding with the rest of the overall procedure.

1. (`ncn-mw#`) Reconfigure the Boot Script Service \(BSS\) to point to a new first master node.

    ```bash
    cray bss bootparameters list --name Global --format=json | jq '.[]' > Global.json
    ```

1. Edit the `Global.json` file and edit the indicated line.

    Change the `first-master-hostname` value to another node that will be promoted to the first master node.
    For example, in order to change the first master node to `ncn-m001`, then change the line to the following:

   ```text
   "first-master-hostname": "ncn-m001",
   ```

1. (`ncn-mw#`) Get a token to interact with BSS using the REST API.

   ```bash
   TOKEN=$(curl -s -S -d grant_type=client_credentials -d client_id=admin-client \
            -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
            https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token \
            | jq -r '.access_token')
   ```

1. (`ncn-mw#`) Do a `PUT` action for the new JSON file.

   ```bash
   curl -i -s -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" \
           "https://api-gw-service-nmn.local/apis/bss/boot/v1/bootparameters" -X PUT -d @./Global.json
   ```

    Ensure that a good response, such as HTTP code `200`, is returned in the `curl` output.

1. Configure the newly promoted first master node so it is able to have other nodes join the cluster.

   1. Use SSH to log in to the newly promoted master node chosen in the previous steps.

   1. (`ncn-m#`) Copy/paste the following script to a file, and then execute it.

      ```bash
      #!/bin/bash
      source /srv/cray/scripts/metal/lib.sh
      export KUBERNETES_VERSION="v$(cat /etc/cray/kubernetes/version)"
      echo $(kubeadm init phase upload-certs --upload-certs 2>&1 | tail -1) > /etc/cray/kubernetes/certificate-key
      export CERTIFICATE_KEY=$(cat /etc/cray/kubernetes/certificate-key)
      export MAX_PODS_PER_NODE=$(craysys metadata get kubernetes-max-pods-per-node)
      export PODS_CIDR=$(craysys metadata get kubernetes-pods-cidr)
      export SERVICES_CIDR=$(craysys metadata get kubernetes-services-cidr)
      envsubst < /srv/cray/resources/common/kubeadm.cfg > /etc/cray/kubernetes/kubeadm.yaml
      kubeadm token create --print-join-command > /etc/cray/kubernetes/join-command 2>/dev/null
      echo "$(cat /etc/cray/kubernetes/join-command) --control-plane --certificate-key $(cat /etc/cray/kubernetes/certificate-key)" > /etc/cray/kubernetes/join-command-control-plane
      mkdir -p /srv/cray/scripts/kubernetes
      cat > /srv/cray/scripts/kubernetes/token-certs-refresh.sh <<'EOF'
      #!/bin/bash
      export KUBECONFIG=/etc/kubernetes/admin.conf
      if [[ "$1" != "skip-upload-certs" ]]; then
          kubeadm init phase upload-certs --upload-certs --config /etc/cray/kubernetes/kubeadm.yaml
      fi
      kubeadm token create --print-join-command > /etc/cray/kubernetes/join-command 2>/dev/null
      echo "$(cat /etc/cray/kubernetes/join-command) --control-plane --certificate-key $(cat /etc/cray/kubernetes/certificate-key)" \
          > /etc/cray/kubernetes/join-command-control-plane
      EOF
      chmod +x /srv/cray/scripts/kubernetes/token-certs-refresh.sh
      /srv/cray/scripts/kubernetes/token-certs-refresh.sh skip-upload-certs
      echo "0 */1 * * * root /srv/cray/scripts/kubernetes/token-certs-refresh.sh >> /var/log/cray/cron.log 2>&1" > /etc/cron.d/cray-k8s-token-certs-refresh
      cp /srv/cray/resources/common/cronjob_kicker.py /usr/bin/cronjob_kicker.py
      chmod +x /usr/bin/cronjob_kicker.py
      echo "0 */2 * * * root KUBECONFIG=/etc/kubernetes/admin.conf /usr/bin/cronjob_kicker.py >> /var/log/cray/cron.log 2>&1" > /etc/cron.d/cray-k8s-cronjob-kicker
      ```

#### Reset Kubernetes on master node being removed

(`ncn-m#`) Run the following command **on the node being removed**. The command can be run from a ConMan console window.

```bash
kubeadm reset --force
```

#### Stop running containers on master node being removed

Run the commands in this section **on the node being removed**. The commands can be run from a ConMan console window.

1. (`ncn-m#`) List any containers running in `containerd`.

   ```bash
   crictl ps
   ```

   Example output:

   ```text
   CONTAINER           IMAGE               CREATED              STATE               NAME                                                ATTEMPT             POD ID
   66a78adf6b4c2       18b6035f5a9ce       About a minute ago   Running             spire-bundle                                        1212                6d89f7dee8ab6
   7680e4050386d       c8344c866fa55       24 hours ago         Running             speaker                                             0                   5460d2bffb4d7
   b6467c907f063       8e6730a2b718c       3 days ago           Running             request-ncn-join-token                              0                   a3a9ca9e1ca78
   e8ce2d1a8379f       64d4c06dc3fb4       3 days ago           Running             istio-proxy                                         0                   6d89f7dee8ab6
   c3d4811fc3cd0       0215a709bdd9b       3 days ago           Running             weave-npc                                    0                   f5e25c12e617e
   ```

1. (`ncn-m#`) If there are any running containers from the output of the `crictl ps` command, then stop them.

   ```bash
   crictl stop <container id from the CONTAINER column>
   ```

#### Remove the master node from the Kubernetes cluster

**IMPORTANT:** Run this command from a master or worker node that is ***NOT*** being deleted.

(`ncn-mw#`) Remove the master node from the Kubernetes cluster.

```bash
kubectl delete node "${NODE}"
```

#### Remove the master node from Etcd

1. (`ncn-m#`) Determine the member ID of the master node being removed.

    Run the following command and find the line with the name of the master being removed. Note the member ID and IP address for use in subsequent steps.
      - The **member ID** is the alphanumeric string in the first field of that line.
      - The **IP address** is in the URL in the fourth field in the line.

    On any master node:

    ```bash
    etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt  --cert=/etc/kubernetes/pki/etcd/ca.crt \
            --key=/etc/kubernetes/pki/etcd/ca.key --endpoints=localhost:2379 member list
    ```

1. (`ncn-m#`) Remove the master node from the Etcd cluster backing Kubernetes.

    Replace the `<MEMBER_ID>` value with the value returned in the previous sub-step.

    ```bash
    etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/ca.crt \
            --key=/etc/kubernetes/pki/etcd/ca.key --endpoints=localhost:2379 member remove <MEMBER_ID>
    ```

#### Stop services on master node being removed

(`ncn-m#`) Stop `kubelet`, `containerd`, and Etcd services ***on the master node being removed***.

```bash
systemctl stop kubelet.service
systemctl stop containerd.service
systemctl stop etcd.service
```

#### Add the master node back into the Etcd cluster

(`ncn-m#`) This will allow the node to rejoin the cluster automatically when it gets added back.

- The IP address and hostname of the rebuilt node is needed for the following command.
- Replace the `<IP_ADDRESS>` address value with the IP address noted in an earlier step from the `etcdctl` command.
- Ensure that the `NODE` variable is set.

```bash
etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/ca.crt \
    --key=/etc/kubernetes/pki/etcd/ca.key --endpoints=localhost:2379 member add "${NODE}" \
    --peer-urls=https://<IP_ADDRESS>:2380
```

#### Remove Etcd data directory on master node being removed

(`ncn-m#`) Remove the Etcd data directory ***on the master node being removed***.

```bash
rm -rf /var/lib/etcd/*
```

#### Save `lan0` configuration from `ncn-m001`

**Skip this step if `ncn-m001` is not being removed.**

(`ncn-m001#`) Save a copy of the `lan0` configuration from `ncn-m001` **only if `ncn-m001` is being removed**.

```bash
rsync /etc/sysconfig/network/ifcfg-lan0 ncn-m002:/tmp/ifcfg-lan0-m001
```

#### Master node role removal complete

The master node role removal is complete. Proceed to [Disable disk boots](#2-disable-disk-boots).

### Worker node remove roles

#### Drain the node

(`ncn-mw#`) Drain the node in order to clear any pods running on the node.

**IMPORTANT:** The following command will cordon and drain the node.

```bash
kubectl drain --ignore-daemonsets --delete-local-data "${NODE}"
```

There may be pods that cannot be gracefully evicted due to Pod Disruption Budgets (PDB). For example:

```text
error when evicting pod "<pod>" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
```

In this case, there are some options. If the service is scalable, the scale can be increased. The goal is to get another pod to start up on another node, allowing the drain to delete the original pod.

(`ncn-mw#`) However, it will probably be necessary to force the deletion of the pod:

```bash
kubectl delete pod [-n <namespace>] --force --grace-period=0 <pod>
```

This will delete the offending pod, and Kubernetes should schedule a replacement on another node. Then rerun the `kubectl drain` command,
and it should report that the node is drained.

#### Reset Kubernetes on worker node being removed

(`ncn-w#`) Run the following command **on the node being removed**. The command can be run from a ConMan console window.

```bash
kubeadm reset --force
```

#### Stop running containers on worker node being removed

Run the commands in this section **on the node being removed**. The commands can be run from a ConMan console window.

1. (`ncn-w#`) List any containers running in `containerd`.

   ```bash
   crictl ps
   ```

   Example output:

   ```text
   CONTAINER           IMAGE               CREATED              STATE               NAME                                                ATTEMPT             POD ID
   66a78adf6b4c2       18b6035f5a9ce       About a minute ago   Running             spire-bundle                                        1212                6d89f7dee8ab6
   7680e4050386d       c8344c866fa55       24 hours ago         Running             speaker                                             0                   5460d2bffb4d7
   b6467c907f063       8e6730a2b718c       3 days ago           Running             request-ncn-join-token                              0                   a3a9ca9e1ca78
   e8ce2d1a8379f       64d4c06dc3fb4       3 days ago           Running             istio-proxy                                         0                   6d89f7dee8ab6
   c3d4811fc3cd0       0215a709bdd9b       3 days ago           Running             weave-npc                                    0                   f5e25c12e617e
   ```

1. (`ncn-w#`) If there are any running containers from the output of the `crictl ps` command, then stop them.

   ```bash
   crictl stop <container id from the CONTAINER column>
   ```

#### Remove the worker node from the Kubernetes cluster after the node is drained

(`ncn-mw#`) Remove the worker node from the Kubernetes cluster.

```bash
kubectl delete node "${NODE}"
```

#### Ensure that all pods are stopped on the worker node

(`ncn-mw#`) Check that no pods are running on the worker node being removed.

```bash
kubectl get pods -A -o wide | grep "${NODE}"
```

If no pods are returned, then proceed to the next step. Otherwise, wait for any remaining pods to terminate.

#### No mapped `rbd` devices on the worker node

Ensure that there are no mapped `rbd` devices ***on the worker node being removed***.

(`ncn-w#`) Run the following command **on the node being removed**. The command can be run from a ConMan console window.

```bash
rbd showmapped
```

If mapped devices still exist, then perform the
[Stop running containers on worker node being removed](#stop-running-containers-on-worker-node-being-removed) step again.
If devices are still mapped, then forcibly unmap them using `rbd unmap -o force /dev/rbd#`,
where `/dev/rbd#` is the device that is still returned as mapped.

#### Worker node role removal complete

The worker node role removal is complete. Proceed to [Disable disk boots](#2-disable-disk-boots).

### Storage node remove roles

Open a new tab and follow the [Remove Ceph Node](../../utility_storage/Remove_Ceph_Node.md) procedure in order
to remove Ceph role from the storage node.

Once the storage node role removal is complete, then proceed to [Disable disk boots](#2-disable-disk-boots).

## 2. Disable disk boots

The disk bootloader must be disabled to ensure that the node fetches an updated configuration and image from
CSM. This is a preventative measure in the event that the boot order on the target NCNs are inconsistent.

1. (`ncn#`) Create a script to copy out to the NCNs.

   1. Create `/tmp/disable-disk-boot.sh`.

      Give it the following contents:

      ```bash
      efibootmgr | grep '(UEFI OS|cray)' | awk -F'[^0-9]*' '{print $0}' | sed 's/^Boot//g' | awk '{print $1}' | tr -d '*' | xargs -r -i efibootmgr -b {} -B
      ipmitool chassis bootdev pxe options=efiboot
      ```

   1. Make the script executable.

      ```bash
      chmod +x /tmp/disable-disk-boot.sh
      ```

1. (`ncn#`) Copy the script and invoke it

   - To run on one NCN:

      Modify the `include` variable in the following section to reflect the actual targeted NCN.

      ```bash
      include='ncn-w999'
      scp /tmp/disable-disk-boot.sh "${target_ncn}":/tmp
      ssh "${include}" /tmp/disable-disk-boot.sh
      ```

   - To run on more than 1 NCN:

      Modify the `include` variable in the following section to reflect the actual targeted NCNs.

      ```bash
      include='ncn-w998|ncn-w999'
      readarray NCNS < <(grep -oP 'ncn-\w\d+' /etc/hosts | grep -P "(${include})" | awk '{print $NF}' | sort -u | tr -t '\n' ' ' | sed 's/ *$//g')
      for ncn in "${NCNS[@]}"; do
         scp /tmp/disable-disk-boot.sh "${ncn}":/tmp
      done
      pdsh -b -w "$(printf "%s" "${NCNS[@]}")" '/tmp/disable-disk-boot.sh'
      ```

## 3. Power off the node

**IMPORTANT:** Run these commands from a node ***NOT*** being powered off.

1. (`linux#`) Set the `BMC` variable to the hostname of the BMC of the node being powered off.

   ```bash
   BMC="${NODE}-mgmt"
   ```

1. (`ncn-m001#`) **For `ncn-m001` only**: Collect and record the BMC IP address for `ncn-m001` and the CMN IP address for `ncn-m002`.

   Do this before `ncn-m001` is powered off. These may be needed later.

   1. Record the BMC IP address for `ncn-m001`.

      ```bash
      BMC_IP=$(ipmitool lan print | grep 'IP Address' | grep -v 'Source'  | awk -F ": " '{print $2}')
      echo ${BMC_IP}
      ```

      Example output:

      ```text
      172.30.52.74
      ```

   1. Record the CMN IP address for `ncn-m002`.

      ```bash
      CMN_IP=$(ssh ncn-m002 ip -4 a show bond0.cmn0 | grep inet | awk '{print $2}' | cut -d / -f1)
      echo ${CMN_IP}
      ```

      Example output:

      ```text
      10.102.4.9 
      ```

1. (`linux#`) Set and export the `root` user password of the BMC.

   > `read -s` is used in order to prevent the password from being echoed to the screen or saved in the shell history.

   ```bash
   read -r -s -p "BMC root password: " IPMI_PASSWORD
   export IPMI_PASSWORD
   ```

1. (`linux#`) Power off the node.

   ```bash
   ipmitool -I lanplus -U root -E -H "${BMC}" chassis power off
   ```

1. (`linux#`) Verify that the node is off.

   ```bash
   ipmitool -I lanplus -U root -E -H "${BMC}" chassis power status
   ```

   > Ensure that the power is reporting as off. This may take 5-10 seconds for this to update. Wait about 30 seconds after receiving the correct power status before proceeding.

## Next step

Proceed to [Remove NCN Data](Remove_NCN_Data.md) or return to the main
[Add, Remove, Replace, or Move NCNs](Add_Remove_Replace_NCNs.md) page.
