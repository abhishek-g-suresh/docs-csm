# Updating the Liquid-Cooled EX Cabinet CEC with Default Credentials after a CEC Password Change

This procedure changes the credential for liquid-cooled EX cabinet chassis controllers and node controller (BMCs) used by CSM services after the CECs have been set to a new
global default credential.

**`NOTE`** This procedure does not provision Slingshot switch BMCs (`RouterBMCs`). Slingshot switch BMC default credentials must be changed using the procedures in the Slingshot
product documentation. To update Slingshot switch BMCs, refer to "Change Rosetta Login and Redfish API Credentials" in the `Slingshot Operations Guide (> 1.6.0)`.

This procedure provisions only the default Redfish `root` account passwords. It does not modify Redfish accounts that have been added after an initial system installation.

## Prerequisites

- The `hms-discovery` Kubernetes CronJob has been disabled.
- All blades in the cabinets have been powered off.
- Procedures in [Provisioning a Liquid-Cooled EX Cabinet CEC with Default Credentials](Provisioning_a_Liquid-Cooled_EX_Cabinet_CEC_with_Default_Credentials.md) have
  been performed on all CECs in the system.
- All of the CECs must be configured with the **same** global credential.
- The previous default global credential for liquid-cooled BMCs must be known.

## Procedure

### 1. Update the default credentials used by MEDS for new hardware

The MEDS sealed secret contains the default global credential used by MEDS when it discovers new liquid-cooled EX cabinet hardware.

#### 1.1 Acquire `site-init`

Before redeploying MEDS, update the `customizations.yaml` file in the `site-init` secret in the `loftsman` namespace.

1. Ensure that the `site-init` repository is available on `ncn-m001`.

    If the `site-init` repository is available as a remote repository, then clone it to `ncn-m001`.

    ```bash
    git clone "$SITE_INIT_REPO_URL" site-init
    ```

1. Acquire `customizations.yaml` from the currently running system.

    ```bash
    kubectl get secrets -n loftsman site-init -o jsonpath='{.data.customizations\.yaml}' | base64 -d > site-init/customizations.yaml
    ```

1. Review, add, and commit `customizations.yaml` to the local `site-init` repository as appropriate.

    > **`NOTE`** If `site-init` was cloned from a remote repository, then
    > there may not be any differences and hence nothing to commit. This is
    > okay. If there are differences between what is in the repository and what
    > was stored in the `site-init`, then this suggests that settings were changed at some
    > point.

    ```bash
    cd site-init
    git diff
    git add customizations.yaml
    git commit -m 'Add customizations.yaml from site-init secret'
    ```

1. Acquire sealed secret keys:

    ```bash
    mkdir -p certs
    kubectl -n kube-system get secret sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > certs/sealed_secrets.crt
    kubectl -n kube-system get secret sealed-secrets-key -o jsonpath='{.data.tls\.key}' | base64 -d > certs/sealed_secrets.key
    ```

#### 1.2 Modify MEDS sealed secret to use new global default credential

1. Inspect the original default credentials for MEDS.

    ```bash
    ./utils/secrets-decrypt.sh cray_meds_credentials ./certs/sealed_secrets.key ./customizations.yaml | jq .data.vault_redfish_defaults -r | base64 -d | jq
    ```

    Example output:

    ```json
    {
        "Username": "root",
        "Password": "bar"
    }
    ```

1. Specify the desired default credentials for MEDS to use with new hardware.

    > Replace `foobar` with the `root` user password configured on the CECs.

    ```bash
    echo '{ "Username": "root", "Password": "foobar" }' | base64 > creds.json.b64
    ```

1. Update and regenerate the `cray_meds_credentials` sealed secret.

    ```bash
    cat << EOF | yq w - 'data.vault_redfish_defaults' "$(<creds.json.b64)" | yq r -j - | ./utils/secrets-encrypt.sh | yq w -f - -i ./customizations.yaml 'spec.kubernetes.sealed_secrets.cray_meds_credentials'
    {
        "kind": "Secret",
        "apiVersion": "v1",
        "metadata": {
            "name": "cray-meds-credentials",
            "namespace": "services",
            "creationTimestamp": null
        },
        "data": {}
    }
    EOF
    ```

1. Decrypt updated sealed secret for review.

    The sealed secret should match the credentials set on the CEC.

    ```bash
    ./utils/secrets-decrypt.sh cray_meds_credentials ./certs/sealed_secrets.key ./customizations.yaml | jq .data.vault_redfish_defaults -r | base64 -d | jq
    ```

    Example output:

    ```json
    {
        "Username": "root",
        "Password": "foobar"
    }
    ```

1. Update the `site-init` secret containing `customizations.yaml` for the system.

    ```bash
    kubectl delete secret -n loftsman site-init
    kubectl create secret -n loftsman generic site-init --from-file=customizations.yaml
    ```

1. Check in changes made to `customizations.yaml`.

    ```bash
    git diff
    git add customizations.yaml
    git commit -m 'Update customizations.yaml with global default credential for MEDS'
    ```

1. Push to the remote repository as appropriate.

    ```bash
    git push
    ```

#### 1.3 Redeploy MEDS to pick up the new sealed secret and push credentials into Vault

1. Determine the version of MEDS.

    ```bash
    MEDS_VERSION=$(kubectl -n loftsman get cm loftsman-core-services -o jsonpath='{.data.manifest\.yaml}' | yq r - 'spec.charts.(name==cray-hms-meds).version')
    echo $MEDS_VERSION
    ```

1. Create `meds-manifest.yaml`.

    ```bash
    cat > meds-manifest.yaml << EOF
    apiVersion: manifests/v1beta1
    metadata:
        name: meds
    spec:
        charts:
        - name: cray-hms-meds
          version: $MEDS_VERSION
          namespace: services
    EOF
    ```

1. Merge `customizations.yaml` with `meds-manifest.yaml`.

    ```bash
    manifestgen -c customizations.yaml -i ./meds-manifest.yaml > ./meds-manifest.out.yaml
    ```

1. Redeploy the MEDS Helm chart.

    ```bash
    loftsman ship \
        --charts-repo https://packages.local/repository/charts \
        --manifest-path meds-manifest.out.yaml
    ```

1. Wait for the MEDS Vault loader job to run to completion.

    ```bash
    kubectl wait -n services job cray-meds-vault-loader --for=condition=complete --timeout=5m
    ```

1. Verify the default credentials have changed in Vault.

    ```bash
    VAULT_PASSWD=$(kubectl -n vault get secrets cray-vault-unseal-keys -o json | jq -r '.data["vault-root"]' |  base64 -d)
    kubectl -n vault exec -it cray-vault-0 -c vault -- env VAULT_TOKEN=$VAULT_PASSWD VAULT_ADDR=http://127.0.0.1:8200 vault kv get secret/meds-cred/global/ipmi
    ```

    Example output:

    ```text
    ====== Data ======
    Key         Value
    ---         -----
    Password    foobar
    Username    root
    ```

### 2. Update credentials for existing EX hardware in the system

1. Set `CRED_PASSWORD` to the new updated password:

    ```bash
    read -s CRED_PASSWORD
    echo $CRED_PASSWORD
    ```

    Expected output:

    ```text
    foobar
    ```

1. Update the credentials used by CSM services for all previously discovered EX cabinet BMCs to the new global default.

    ```bash
    \
    cray hsm inventory redfishEndpoints list --format json > /tmp/redfishEndpoints.json
    cray hsm state components list --format json  > /tmp/components.json

    REDFISH_ENDPOINTS=$(jq .RedfishEndpoints[].ID -r /tmp/redfishEndpoints.json | sort -V)
    for RF in $REDFISH_ENDPOINTS; do
        echo "$RF: Checking..."
        TYPE=$(jq -r --arg XNAME "$RF" '.RedfishEndpoints[] | select(.ID == $XNAME).Type' /tmp/redfishEndpoints.json)
        if [[ -z "$TYPE" ]]; then
            echo "$RF missing Type, skipping..."
            continue
        elif [[ "$TYPE" == "RouterBMC" ]]; then
            echo "$RF is a RouterBMC, skipping..."
            continue
        fi
        CLASS=$(jq -r --arg XNAME "$RF" '.Components[] | select(.ID == $XNAME).Class' /tmp/components.json)
        if [[ "$CLASS" != "Mountain" ]]; then
            echo "$RF is not Mountain, skipping..."
            continue
        fi
        echo "$RF: Updating credentials"
        cray hsm inventory redfishEndpoints update ${RF} --user root --password ${CRED_PASSWORD}
    done
    ```

    It will take some time for the above bash script to run. It will take approximately 5 minutes to update all of the credentials for a single fully populated cabinet.

    > Alternatively, use the following command on each BMC. Replace `BMC_XNAME` with the BMC component name (xname) to update the credentials:
    >
    > ```bash
    > cray hsm inventory redfishEndpoints update BMC_XNAME --user root --password ${CRED_PASSWORD}
    > ```

1. Restart the `hms-discovery` Kubernetes CronJob.

   ```bash
   kubectl -n services patch cronjobs hms-discovery -p '{"spec" : {"suspend" : false }}'
   ```

   After 2-3 minutes, the `hms-discovery` CronJob will start to power on all of the currently powered off compute slots.

1. Wait for compute slots to be powered on and for HSM to re-discover the updated Redfish endpoints.

    ```bash
    sleep 300
    ```

1. Wait for all updated Redfish endpoints to become `DiscoverOK`.

    The following Bash script will find all Redfish endpoints for the liquid-cooled BMCs that are not in `DiscoverOK`, and display their `lastDiscoveryStatus`.

    ```bash
    \
    cray hsm inventory redfishEndpoints list --laststatus '!DiscoverOK' --format json > /tmp/redfishEndpoints.json
    cray hsm state components list --format json  > /tmp/components.json

    REDFISH_ENDPOINTS=$(jq .RedfishEndpoints[].ID -r /tmp/redfishEndpoints.json | sort -V)
    for RF in $REDFISH_ENDPOINTS; do
        TYPE=$(jq -r --arg XNAME "$RF" '.RedfishEndpoints[] | select(.ID == $XNAME).Type' /tmp/redfishEndpoints.json)
        if [[ -z "$TYPE" ]]; then
            continue
        elif [[ "$TYPE" == "RouterBMC" ]]; then
            continue
        fi
        CLASS=$(jq -r --arg XNAME "$RF" '.Components[] | select(.ID == $XNAME).Class' /tmp/components.json)
        if [[ "$CLASS" != "Mountain" ]]; then
            continue
        fi
        DISCOVERY_STATUS=$(jq -r --arg XNAME "$RF" '.RedfishEndpoints[] | select(.ID == $XNAME).DiscoveryInfo.LastDiscoveryStatus' /tmp/redfishEndpoints.json)
        echo "$RF: $DISCOVERY_STATUS"
    done
    ```

    Example output:

    ```text
    x1001c0r5b0: HTTPsGetFailed
    x1001c1s0b0: HTTPsGetFailed
    x1001c1s0b1: HTTPsGetFailed
    x1001c2s0b1: DiscoveryStarted
    ```

    For each Redfish endpoint that is reported use the following to troubleshoot why it is not `DiscoverOK` or `DiscoveryStarted`:

    - If the Redfish endpoint is `DiscoveryStarted`, then that BMC is currently in the process of being inventoried by HSM. Wait a
      few minutes and re-try the Bash script above to re-check the current discovery status of the `RedfishEndpoints`.

        > The hms-discovery cronjob (if enabled) will trigger a discover on BMCs that are not currently in `DiscoverOK` or
        > `DiscoveryStarted` every three minutes.

    - If the Redfish endpoint is `HTTPsGetFailed`, then HSM had issues contacting BMC.

        1. Verify that the BMC component name (xname) is resolvable and pingable.

           ```bash
           ping x1001c1s0b0
           ```

        1. If a `NodeBMC` is not pingable, then verify that the slot powering the BMC is powered on.

            If this is a `ChassisBMC`, then skip this step.

            For example, the `NodeBMC` `x1001c1s0b0` is in slot `x1001c1s0`:

            ```bash
            cray capmc get_xname_status create --xnames x1001c1s0
            ```

            Example output:

            ```toml
            e = 0
            err_msg = ""
            on = [ "x1001c1s0b0",]
            ```

            If the slot is off, power it on:

            ```bash
            cray capmc xname_on create --xnames x1001c1s0
            ```

        1. If the BMC is reachable and in `HTTPsGetFailed`, then verify that the BMC is accessible with the new default global credential.

            Replace `BMC_XNAME` with the hostname of the Redfish endpoint.

            ```bash
            curl -k -u root:$CRED_PASSWORD https://BMC_XNAME/redfish/v1/Managers | jq
            ```

            If the error message below is returned, then the BMC must have a `StatefulReset` action performed on it.
            The `StatefulReset` action clears previously user-defined credentials that are taking precedence over the CEC-supplied
            credential. It also clears NTP, `syslog`, and SSH key configurations on the BMC.

            ```json
            {
                "error": {
                    "@Message.ExtendedInfo": [
                    {
                        "@odata.type": "#Message.v1_0_5.Message",
                        "Message": "While attempting to establish a connection to /redfish/v1/Managers, the service was denied access.",
                        "MessageArgs": [
                        "/redfish/v1/Managers"
                        ],
                        "MessageId": "Security.1.0.AccessDenied",
                        "Resolution": "Attempt to ensure that the URI is correct and that the service has the appropriate credentials.",
                        "Severity": "Critical"
                    }
                    ],
                    "code": "Security.1.0.AccessDenied",
                    "message": "While attempting to establish a connection to /redfish/v1/Managers, the service was denied access."
                }
            }
            ```

            Perform a `StatefulReset` on the liquid-cooled BMC. Replace `BMC_XNAME` with the hostname of the BMC.
            The `OLD_DEFAULT_PASSWORD` must match the credential that was previously set on the BMC. This is mostly
            likely the previous global default credential for liquid-cooled BMCs.

            ```bash
            curl -k -u root:OLD_DEFAULT_PASSWORD -X POST -H 'Content-Type: application/json' -d \
                        '{"ResetType": "StatefulReset"}' \
                        https://BMC_XNAME/redfish/v1/Managers/BMC/Actions/Manager.Reset
            ```

            After the `StatefulReset` action has been issued, the BMC will be unreachable for a few minutes as it performs the `StatefulReset`.

### 3. Reapply BMC settings if a `StatefulReset` was performed on any BMC

> **`NOTE`** This section only needs to be performed if any liquid-cooled node or chassis BMCs that had to be `StatefulReset`.

1. For each liquid-cooled BMC to which the `StatefulReset` action was applied, delete the BMC from HSM.

    Replace `BMC_XNAME` with the BMC component name (xname) to delete.

    ```bash
    cray hsm inventory redfishEndpoints delete BMC_XNAME
    ```

1. Restart MEDS to re-setup the NTP and `syslog` configuration for the Redfish endpoints.

    1. View running MEDS pods.

        ```bash
        kubectl -n services get pods -l app.kubernetes.io/instance=cray-hms-meds
        ```

        Example output:

        ```text
        NAME                         READY   STATUS    RESTARTS   AGE
        cray-meds-6d8b5875bc-4jngc   2/2     Running   0          17d
        ```

    1. Restart MEDS.

        ```bash
        kubectl -n services rollout restart deployment cray-meds
        kubectl -n services rollout status deployment cray-meds
        ```

1. Wait five minutes for MEDS to re-discover the deleted Redfish endpoints.

    ```bash
    sleep 300
    ```

1. Verify that all expected hardware has been discovered.

    The following Bash script will find all Redfish endpoints for the liquid-cooled BMCs that are not in `DiscoverOK`, and display their last discovery status.

    ```bash
    \
    cray hsm inventory redfishEndpoints list --laststatus '!DiscoverOK' --format json > /tmp/redfishEndpoints.json
    cray hsm state components list --format json  > /tmp/components.json

    REDFISH_ENDPOINTS=$(jq .RedfishEndpoints[].ID -r /tmp/redfishEndpoints.json | sort -V)
    for RF in $REDFISH_ENDPOINTS; do
        TYPE=$(jq -r --arg XNAME "$RF" '.RedfishEndpoints[] | select(.ID == $XNAME).Type' /tmp/redfishEndpoints.json)
        if [[ -z "$TYPE" ]]; then
            continue
        elif [[ "$TYPE" == "RouterBMC" ]]; then
            continue
        fi
        CLASS=$(jq -r --arg XNAME "$RF" '.Components[] | select(.ID == $XNAME).Class' /tmp/components.json)
        if [[ "$CLASS" != "Mountain" ]]; then
            continue
        fi
        DISCOVERY_STATUS=$(jq -r --arg XNAME "$RF" '.RedfishEndpoints[] | select(.ID == $XNAME).DiscoveryInfo.LastDiscoveryStatus' /tmp/redfishEndpoints.json)
        echo "$RF: $DISCOVERY_STATUS"
    done
    ```

1. Restore SSH keys configured by Cray console services on liquid-cooled Node BMCs.

    Get the SSH console private key from Vault:

    ```bash
    VAULT_PASSWD=$(kubectl -n vault get secrets cray-vault-unseal-keys \
                -o json | jq -r '.data["vault-root"]' |  base64 -d)

    kubectl -n vault exec -t cray-vault-0 -c vault \
                -- env VAULT_TOKEN=$VAULT_PASSWD VAULT_ADDR=http://127.0.0.1:8200 \
                VAULT_FORMAT=json vault read transit/export/signing-key/mountain-bmc-console \
                | jq -r .data.keys[]  > ssh-console.key
    ```

1. Generate the SSH public key.

    ```bash
    chmod 0600 ssh-console.key
    export SCSD_SSH_CONSOLE_KEY=$(ssh-keygen -yf ssh-console.key)
    echo $SCSD_SSH_CONSOLE_KEY
    ```

1. Delete the SSH console private key from disk.

    ```bash
    rm ssh-console.key
    ```

1. Generate a payload for the SCSD service.

    The administrator must be authenticated to the Cray CLI before proceeding. See [Configure the Cray Command Line Interface](../configure_cray_cli.md).

    ```bash
    cat > scsd_cfg.json <<DATA
    {
        "Force":false,
        "Targets":
    $(cray hsm state components list --class Mountain --type NodeBMC --format json | jq -r '[.Components[] | .ID]'),
        "Params":{
            "SSHConsoleKey":"$(echo $SCSD_SSH_CONSOLE_KEY)"
        }
    }
    DATA
    ```

    Alternatively create a `scsd_cfg.json` file with only the SSH console key:

    ```bash
    cat > scsd_cfg.json <<DATA
    {
        "Force":false,
        "Targets":[
            "x1000c0s0b0",
            "x1000c0s0b0"
         ],
        "Params":{
            "SSHConsoleKey":"$(echo $SCSD_SSH_CONSOLE_KEY)"
        }
    }
    DATA
    ```

1. Edit the `Targets` array to contain the `NodeBMCs` that have have had the `StatefulReset` action.

    1. Inspect the generated `scsd_cfg.json` file.

        Ensure that the following are true before running the `cray scsd` command in the following step:

       - The component name (xname) looks valid/appropriate.
         - Limit the `scsd_cfg.json` file to `NodeBMCs` that have had the `StatefulReset` action applied to them.
       - The `SSHConsoleKey` settings match the desired public key.

    1. Apply SSH console key to the `NodeBMCs`:

       ```bash
       cray scsd bmc loadcfg create scsd_cfg.json
       ```

    1. Check the output to verify all hardware has been set with the correct keys.

        Passwordless SSH to the consoles should now function as expected.
