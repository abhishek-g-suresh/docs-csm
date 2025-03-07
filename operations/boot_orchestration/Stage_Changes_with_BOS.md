# Staging Changes with BOS

In BOS V2 it is possible to stage changes when creating a session.  These changes will not immediately take effect, and will instead be applied when the `applystaged` endpoint is called.

This is a BOS V2 feature only.  For suggestions on working around this in V1, see [Stage Changes Without BOS](#stage-changes-without-bos).

## Creating a staged session

Creating a staged session is no different than creating a normal session, with one exception, the `staged` value should be set to `True`.  For more on creating sessions see [Create a New V2 Session](Manage_a_BOS_Session.md#Create-a-New-V2-Session)

(`ncn-mw#`)

```bash
cray bos v2 sessions create --template-name TEMPLATE_NAME --operation boot --stage True --format json
```

This creates a new BOS session that can be managed and monitored as normal, but rather than updating the component's desired state, the desired state information will be stored in a `staged_state` field.
The session will continue to run so long as any components have staged state that has not been applied so that status can be used to monitor actions such as rolling upgrades.

## Applying a staged state

Applying staged state is done on a per component basis.  Multiple components can be specified in a single call.
In the CLI this can be done with a comma separated list of `xnames`, or by specifying a range of values.

(`ncn-mw#`)

```bash
cray bos v2 applystaged create --xnames x3000c0s19b[1-4]n0
```

When using the API, components should be provided as a list of xnames.
(`ncn-mw#`)

```bash
curl -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json"  --data '{"xnames":["x3000c0s19b1n0","x3000c0s19b2n0"]}' https://api-gw-service-nmn.local/apis/bos/v2/applystaged
```

When called, any staged data for the given components will be moved to the desired state, clearing out the staged state data.
In addition BOS will check for the associated session in order to determine what kind of operation to apply.  This allows users to stage any operation, including shutdowns.

If for some reason a session that was used to stage data is deleted before `applystaged` is called for the associated components, it will no longer be possible to apply the staged state since BOS will not be able to determine which operation should be taken.

By default staged data will not be cleared when `applystaged` is called, allowing users to call the endpoint multiple times.  This behavior can be changed via the [Options](Options.md) endpoint.

## Stage Changes Without BOS

To stage desired state without BOS V2, users can bypass BOS and set boot artifacts or configuration that will only take place when a node is later booted, whether that occurs manually, or triggered by a task manager.

### Stage Boot Artifacts

For information on staging boot artifacts, see the section [Upload Node Boot Information to Boot Script Service (BSS)](Upload_Node_Boot_Information_to_Boot_Script_Service_BSS.md).

### Stage a Configuration

1. Disable CFS for all nodes receiving the staged configuration. Nodes will automatically re-enable configuration when they are rebooted and will be configured with any staged changes.

    ```bash
    cray cfs components update <xname> --enabled false
    ```

1. Either set the new desired configuration or update the existing configuration.

    If an entirely new configuration is being used or if no configuration was previously set for a component, update the configuration name with the following:

    ```bash
    cray cfs components update <xname> --configuration-name <configuration_name>
    ```

    If all nodes that share a configuration are being staged with an update, updating the shared configuration will stage the change for all relevant nodes.
    Be aware that if this step is taken and not all nodes that use the configuration are disabled in CFS, the configuration will automatically and immediately apply to all enabled nodes that are using it.

    ```bash
    cray cfs configurations update <configuration_name> --file <file_path>
    ```

    Users also have the option of specifying branches rather than commits in configurations.
    If this feature is used, the configuration can also be updated by telling CFS to update the commits for all layers of a configuration that specify branches.
    Similar to when updating the configuration from a file, this will automatically start configuration on any enabled nodes that are using this configuration.
    For information on using branches, see the section ([Use Branches in Configuration Layers](../configuration_management/Configuration_Layers.md#use-branches-in-configuration-layers))
