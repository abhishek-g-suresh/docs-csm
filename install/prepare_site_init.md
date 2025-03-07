# Prepare `site init`

These procedures guide administrators through setting up the `site-init`
directory which contains important customizations for various products.

1. [Background](#1-background)
1. [Create and Initialize `site-init` Directory](#2-create-and-initialize-site-init-directory)
1. [Create Baseline System Customizations](#3-create-baseline-system-customizations)
    1. [Setup LDAP configuration](#setup-ldap-configuration)
    1. [End of LDAP configuration](#end-of-ldap-configuration)
1. [Customer-Specific Customizations](#4-customer-specific-customizations)

## 1. Background

The `shasta-cfg` directory included in the CSM release tarball includes relatively static,
installation-centric artifacts, such as:

- Cluster-wide network configuration settings required by Helm charts deployed by product stream Loftsman manifests
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- Sealed Secret Generate Blocks -- a form of plain-text input that renders to a Sealed Secret
- Helm chart value overrides that are merged into Loftsman manifests by product stream installers

## 2. Create and initialize `site-init` directory

> **`NOTE`** If the pre-installation is resuming here, ensure the environment variables have been properly set
> by following [Set reusable environment variables](pre-installation.md#15-set-reusable-environment-variables) and then coming back
> to this page.

1. (`pit#`) Set the `SITE_INIT` variable.

    > **Important:** All procedures on this page assume that `SITE_INIT` variable has been set.

    ```bash
    SITE_INIT="${PITDATA}/prep/site-init"
    ```

1. (`pit#`) Create the `site-init` directory.

    ```bash
    mkdir -pv "${SITE_INIT}"
    ```

1. (`pit#`) Initialize `site-init` from CSM.

    ```bash
    "${CSM_PATH}/shasta-cfg/meta/init.sh" "${SITE_INIT}"
    ```

### 3. Create Baseline System Customizations

The following steps update `${SITE_INIT}/customizations.yaml`
with system-specific customizations.

1. (`pit#`) Change into the `site-init` directory

    ```bash
    cd "${SITE_INIT}"
    ```

1. (`pit#`) Merge the system-specific settings generated by CSI into
    `customizations.yaml`.

    ```bash
    yq merge -xP -i "${SITE_INIT}/customizations.yaml" <(yq prefix -P "${PITDATA}/prep/${SYSTEM_NAME}/customizations.yaml" spec)
    ```

1. (`pit#`) Set the cluster name.

    ```bash
    yq write -i "${SITE_INIT}/customizations.yaml" spec.wlm.cluster_name "${SYSTEM_NAME}"
    ```

1. (`pit#`) Make a backup copy of `${SITE_INIT}/customizations.yaml`.

    ```bash
    cp -pv "${SITE_INIT}/customizations.yaml" "${SITE_INIT}/customizations.yaml.prepassword"
    ```

1. (`pit#`) Review the configuration to generate these sealed secrets in `customizations.yaml` in the `site-init` directory:

    - `spec.kubernetes.sealed_secrets.cray_reds_credentials`
    - `spec.kubernetes.sealed_secrets.cray_meds_credentials`
    - `spec.kubernetes.sealed_secrets.cray_hms_rts_credentials`
    - Replace the `Username` and `Password` references in match the existing settings of your system hardware components.

    > **`NOTE`**
    >
    > - The `cray_reds_credentials` are used by the River Endpoint Discovery Service (REDS) for River components.
    > - The `cray_meds_credentials` are used by the Mountain Endpoint Discovery Service (MEDS) for the liquid-cooled components in an Olympus (Mountain) cabinet.
    > - The `cray_hms_rts_credentials` are used by the Redfish Translation Service (RTS) for any hardware components which are not managed by Redfish, such as a ServerTech PDU in a River Cabinet.
    >
    > See the `Decrypt Sealed Secrets for Review` section of [Manage Sealed Secrets](../operations/security_and_authentication/Manage_Sealed_Secrets.md#decrypt-sealed-secrets-for-review),
    > if needing to examine credentials from prior installations.

    ```bash
    vim "${SITE_INIT}/customizations.yaml"
    ```

1. (`pit#`) Review the changes that you made.

    ```bash
    diff ${SITE_INIT}/customizations.yaml ${SITE_INIT}/customizations.yaml.prepassword
    ```

1. (`pit#`) Validate that REDS/MEDS/RTS credentials are correct.

    For all credentials, make sure that `Username` and `Password` values are correct.

    - Validate REDS credentials:

        > **`NOTE`** These credentials are used by the REDS and HMS discovery services, targeting River Redfish
        BMC endpoints and management switches
        >
        > - For `vault_redfish_defaults`, the only entry used is:
        >
        >     ```json
        >     {"Cray": {"Username": "root", "Password": "XXXX"}
        >     ```
        >
        > - Ensure the `Cray` key exists. This key is not used in any of the other credential specifications.

        ```bash
        yq read "${SITE_INIT}/customizations.yaml" 'spec.kubernetes.sealed_secrets.cray_reds_credentials.generate.data[*].args.value' | jq
        ```

    - Validate MEDS credentials:

        These credentials are used by the MEDS service, targeting Redfish BMC endpoints.

        ```bash
        yq read "${SITE_INIT}/customizations.yaml" 'spec.kubernetes.sealed_secrets.cray_meds_credentials.generate.data[0].args.value' | jq
        ```

    - Validate RTS credentials:

        These credentials are used by the Redfish Translation Service, targeting River Redfish BMC endpoints and PDU controllers.

        ```bash
        yq read "${SITE_INIT}/customizations.yaml" 'spec.kubernetes.sealed_secrets.cray_hms_rts_credentials.generate.data[*].args.value' | jq
        ```

1. To customize the PKI Certificate Authority (CA) used by the platform, see
    [Certificate Authority](../background/certificate_authority.md).

    > **`IMPORTANT`** The CA may not be modified after install.

#### Setup LDAP configuration

> **`NOTE`** Skip past LDAP configuration to [here](#end-of-ldap-configuration) if there is no LDAP configuration at this time. If LDAP should be enabled later,
> follow [Add LDAP User Federation](../operations/security_and_authentication/Add_LDAP_User_Federation.md) after installation.

1. (`pit#`) Set environment variables for the LDAP server and its port.

   In the example below, the LDAP server has the hostname `dcldap2.us.cray.com` and is using the port 636.

   ```bash
   LDAP=dcldap2.us.cray.com
   PORT=636
   ```

1. (`pit#`) Load the `openjdk` container image.

   > **`NOTE`** Requires a properly configured Docker or Podman
   > environment.

   ```bash
   "${CSM_PATH}/hack/load-container-image.sh" artifactory.algol60.net/csm-docker/stable/docker.io/library/openjdk:11-jre-slim
   ```

1. (`pit#`) Get the issuer certificate.

    Retrieve the issuer certificate for the LDAP server at port 636. Use `openssl s_client` to connect
    and show the certificate chain returned by the LDAP host:

    ```bash
    openssl s_client -showcerts -connect "${LDAP}:${PORT}" </dev/null
    ```

1. Enter the issuer's certificate into `cacert.pem`.

    Either manually extract (i.e., cut/paste) the issuer's
    certificate into `cacert.pem`, or try the following commands to
    create it automatically.

    > **`NOTE`** The following commands were verified using OpenSSL
    > version `1.1.1d` and use the `-nameopt RFC2253` option to ensure
    > consistent formatting of distinguished names.
    > Unfortunately, older versions of OpenSSL may not support
    > `-nameopt` on the `s_client` command or may use a different
    > default format. However,
    > the issuer certificate can be manually extracted
    > from the output of the above `openssl s_client` example, if the
    > following commands are unsuccessful.

    1. (`pit#`) Observe the issuer's DN.

        ```bash
        openssl s_client -showcerts -nameopt RFC2253 -connect "${LDAP}:${PORT}" </dev/null 2>/dev/null | grep issuer= | sed -e 's/^issuer=//'
        ```

        Expected output includes a line similar to one of the below examples:

        Self-signed Certificate:

        ```text
        emailAddress=dcops@hpe.com,CN=Data Center,OU=HPC/MCS,O=HPE,ST=WI,C=US
        ```

        Signed Certificate:

        ```text
         CN=DigiCert Global G2 TLS RSA SHA256 2020 CA1,O=DigiCert Inc,C=US
         ```

    1. (`pit#`) Extract the issuer's certificate.

        > **`NOTE`** The issuer DN is properly escaped as part of the
        > `awk` pattern below. It must be changed to match the value
        > for `emailAddress`, `CN`, `OU`, etc. for your LDAP. If the value
        > you are using is different, be sure to escape it properly!

        ```bash
        openssl s_client -showcerts -nameopt RFC2253 -connect "${LDAP}:${PORT}" </dev/null 2>/dev/null |
                  awk '/s:emailAddress=dcops@hpe.com,CN=Data Center,OU=HPC\/MCS,O=HPE,ST=WI,C=US/,/END CERTIFICATE/' |
                  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > cacert.pem
        ```

1. (`pit#`) Create `certs.jks`.

    > **`NOTE`** The alias used in this command for `cray-data-center-ca` should be changed to match your LDAP.

    ```bash
    podman run --rm -v "$(pwd):/data" \
            artifactory.algol60.net/csm-docker/stable/docker.io/library/openjdk:11-jre-slim keytool \
            -importcert -trustcacerts -file /data/cacert.pem -alias cray-data-center-ca \
            -keystore /data/certs.jks -storepass password -noprompt
    ```

1. (`pit#`) Create `certs.jks.b64` by base-64 encoding `certs.jks`.

    ```bash
    base64 certs.jks > certs.jks.b64
    ```

1. (`pit#`) Inject and encrypt `certs.jks.b64` into `customizations.yaml`.

    ```bash
    cat <<EOF | yq w - 'data."certs.jks"' "$(<certs.jks.b64)" | \
        yq r -j - | ${SITE_INIT}/utils/secrets-encrypt.sh | \
        yq w -f - -i ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray-keycloak'
    {
      "kind": "Secret",
      "apiVersion": "v1",
      "metadata": {
        "name": "keycloak-certs",
        "namespace": "services",
        "creationTimestamp": null
      },
      "data": {}
    }
    EOF
    ```

1. (`pit#`) Update the `keycloak_users_localize` sealed secret with the
    appropriate value for `ldap_connection_url`.

    1. (`pit#`) Set `ldap_connection_url` in `customizations.yaml`.

       ```bash
       yq write -i "${SITE_INIT}/customizations.yaml" \
                'spec.kubernetes.sealed_secrets.keycloak_users_localize.generate.data.(args.name==ldap_connection_url).args.value' \
                "ldaps://${LDAP}"
       ```

    1. (`pit#`) Review the `keycloak_users_localize` sealed secret.

       ```bash
       yq read "${SITE_INIT}/customizations.yaml" spec.kubernetes.sealed_secrets.keycloak_users_localize
       ```

1. Configure the `ldapSearchBase` and `localRoleAssignments` settings for
    the `cray-keycloak-users-localize` chart in `customizations.yaml`.

    > **`NOTE`** There may be one or more groups in LDAP for admins and one or more for users.
    > Each admin group needs to be assigned to role `admin` and set to both `shasta` and `cray` clients in Keycloak.
    > Each user group needs to be assigned to role `user` and set to both `shasta` and `cray` clients in Keycloak.

    1. (`pit#`) Set `ldapSearchBase` in `customizations.yaml`.

       > **`NOTE`** This example sets `ldapSearchBase` to `dc=dcldap,dc=dit`

       ```bash
       yq write -i "${SITE_INIT}/customizations.yaml" spec.kubernetes.services.cray-keycloak-users-localize.ldapSearchBase 'dc=dcldap,dc=dit'
       ```

    1. (`pit#`) Set `localRoleAssignments` in `customizations.yaml`.

       > **`NOTE`** This example sets `localRoleAssignments` for the LDAP groups `employee`,
       > `craydev`, and `shasta_admins` to be the `admin` role, and the LDAP group `shasta_users`
       > to be the `user` role.

       ```bash
       yq write -s - -i "${SITE_INIT}/customizations.yaml" <<EOF
       - command: update
         path: spec.kubernetes.services.cray-keycloak-users-localize.localRoleAssignments
         value:
         - {"group": "employee", "role": "admin", "client": "shasta"}
         - {"group": "employee", "role": "admin", "client": "cray"}
         - {"group": "craydev", "role": "admin", "client": "shasta"}
         - {"group": "craydev", "role": "admin", "client": "cray"}
         - {"group": "shasta_admins", "role": "admin", "client": "shasta"}
         - {"group": "shasta_admins", "role": "admin", "client": "cray"}
         - {"group": "shasta_users", "role": "user", "client": "shasta"}
         - {"group": "shasta_users", "role": "user", "client": "cray"}
       EOF
       ```

    1. (`pit#`) Review the `cray-keycloak-users-localize` values.

       ```bash
       yq read "${SITE_INIT}/customizations.yaml" spec.kubernetes.services.cray-keycloak-users-localize
       ```

#### End of LDAP configuration

1. (`pit#`) Configure the Unbound DNS resolver (if needed).

    > **Important** If access to a site DNS server is required **and** this DNS server was specified to `csi` using the `site-dns`
    > option (either on the command line or in the `system_config.yaml` file),
    > **then no further action is required and this step should be skipped**.

    The default configuration is as follows:

    ```yaml
    cray-dns-unbound:
        domain_name: '{{ network.dns.external }}'
        forwardZones:
          - name: "."
            forwardIps:
              - "{{ network.netstaticips.system_to_site_lookups }}"
    ```

    The configured site DNS server can be verified by inspecting the value set for `system_to_site_lookups`.

    ```bash
    yq r ${SITE_INIT}/customizations.yaml spec.network.netstaticips.system_to_site_lookups
    ```

    Possible output:

    ```text
    172.30.84.40
    ```

    If there is **no requirement to resolve external hostnames (including other services on the site network) or no upstream DNS server**,
    then the `cray-dns-unbound` service should be configured to forward to the `cray-dns-powerdns` service.

    1. (`pit#`) Update the `forwardZones` configuration for the `cray-dns-unbound` service to point to the `cray-dns-powerdns` service.

        ```bash
        yq write -s - -i ${SITE_INIT}/customizations.yaml <<EOF
        - command: update
          path: spec.kubernetes.services.cray-dns-unbound.forwardZones
          value:
          - name: "."
            forwardIps:
            - "10.92.100.85"
        EOF
        ```

    1. (`pit#`) Review the `cray-dns-unbound` values.

        > **`IMPORTANT`** **Do not** remove the `domain_name` entry, it is required for Unbound to forward requests to PowerDNS correctly.

        ```bash
        yq read "${SITE_INIT}/customizations.yaml" spec.kubernetes.services.cray-dns-unbound
        ```

        Expected output:

        ```yaml
        domain_name: '{{ network.dns.external }}'
        forwardZones:
          - name: "."
            forwardIps:
              - "10.92.100.85"
        ```

    See the following documentation regarding known issues when operating with no upstream DNS server.
    - [Spire Database Cluster DNS Lookup Failure](../troubleshooting/known_issues/spire_database_lookup_error.md)
    - [Spire database connection pool configuration in an air-gapped environment](../troubleshooting/known_issues/spire_database_airgap_configuration.md)

1. (Optional) Configure PowerDNS zone transfer and DNSSEC. See the [PowerDNS Configuration Guide](../operations/network/dns/PowerDNS_Configuration.md) for more information.

   - If zone transfer is to be configured, then review `customizations.yaml` and ensure that the `primary_server`, `secondary_servers`, and `notify_zones` values are set correctly.

   - If DNSSEC is to be used, then add the desired keys into the `dnssec` SealedSecret.

1. Configure Prometheus SNMP Exporter.

   The Prometheus SNMP exporter needs to be configured with a list of management network switches to scrape metrics from in
   order to populate the System Health Service Grafana dashboards.

   See [Prometheus SNMP Exporter](../operations/network/management_network/snmp_exporter_configs.md) for more information.

1. (`pit#`) Load the `zeromq` container image required by Sealed Secret Generators.

    > **`NOTE`** Requires a properly configured Docker or Podman environment.

    ```bash
    "${CSM_PATH}/hack/load-container-image.sh" artifactory.algol60.net/csm-docker/stable/docker.io/zeromq/zeromq:v4.0.5
    ```

1. (`pit#`) Re-encrypt existing secrets.

    ```bash
    "${SITE_INIT}/utils/secrets-reencrypt.sh" \
        "${SITE_INIT}/customizations.yaml" \
        "${SITE_INIT}/certs/sealed_secrets.key" \
        "${SITE_INIT}/certs/sealed_secrets.crt"
    ```

    It is not an error if this script gives no output.

1. (`pit#`) Generate secrets.

    ```bash
    "${SITE_INIT}/utils/secrets-seed-customizations.s"h "${SITE_INIT}/customizations.yaml"
    ```

1. Leave the `site-init` directory.

    ```bash
    cd "${PITDATA}"
    ```

1. `site-init` is now prepared. Resume [Initialize the LiveCD](pre-installation.md#36-initialize-the-livecd).

## 4. Customer-specific customizations

Customer-specific customizations are any changes on top of the baseline
configuration to satisfy customer-specific requirements. It is recommended that
customer-specific customizations be tracked on branches separate from the
mainline in order to make them easier to manage.

Apply any customer-specific customizations by merging the corresponding
branches into `master` branch of `site-init`.

When considering merges, and especially when resolving conflicts, carefully
examine differences to ensure all changes are relevant. For example, when
applying a customer-specific customization used in a prior version, be sure the
change still makes sense. It is common for options to change as new features are
introduced and bugs are fixed.
