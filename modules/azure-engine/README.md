# Forcepoint Network Security Platform for Azure

Deploys one Forcepoint Network Security Platform Security Engine as an
Azure Linux virtual machine, and hands it the initial contact data that
registers it with your Security Management Center (SMC).

The engine boots from the template Forcepoint publishes to the Azure
Marketplace. You accept the offer's terms once in your subscription and
deploy; there is no image to build or upload.

The module owns the virtual machine, its network interfaces and the public
IP addresses it creates. The network it sits on is created by you and
passed in as inputs: the virtual network, the subnets and the security
rules. The engine itself is configured in the SMC: policy, VPN and
routing.

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Resources](#resources)
- [What replaces the instance](#what-replaces-the-instance)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)

## Quick start

```hcl
module "engine" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/azure-engine"

  name                = "engine-a"
  resource_group_name = "engine-rg"
  location            = "westeurope"
  size                = "Standard_B4ms"

  network_interfaces = [
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.mgmt.id
          private_ip_address_allocation = "Static"
          private_ip_address            = "10.0.0.10"
          public_ip                     = {}
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.lan.id
          private_ip_address_allocation = "Static"
          private_ip_address            = "10.0.1.10"
        },
      ]
    },
    {
      ip_configuration = [
        {
          subnet_id                     = azurerm_subnet.wan.id
          private_ip_address_allocation = "Static"
          private_ip_address            = "10.0.100.10"
          public_ip                     = {}
        },
      ]
    },
  ]

  ssh_public_keys = [file("~/.ssh/id_ed25519.pub")]
  initial_contact = file("engine.cfg")
}
```

## Requirements

| Requirement                  | Detail                                                                           |
|------------------------------|----------------------------------------------------------------------------------|
| Terraform                    | >= 1.9                                                                           |
| `hashicorp/azurerm` provider | >= 4.0, < 6.0, input to the module                                               |
| Provider configuration       | `provider "azurerm" { features {} }` in the root module, required on azurerm 4.x |
| Azure credentials            | For example through `az login` or a service principal                            |
| Marketplace offer            | Terms accepted in the subscription, for the default template                     |
| SMC                          | Reachable from `nic0`, for an SMC-managed engine                                 |

## Inputs

| Name                                        | Description                                                                                           | Type           | Default     | Required |
|---------------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|-------------|----------|
| `admin_username`                            | Login the `ssh_public_keys` grant access as.                                                          | `string`       | `"azure"`   | no       |
| `availability_set_id`                       | ID of an availability set to run the virtual machine in.                                              | `string`       | `null`      | no       |
| [`boot_diagnostics`](#boot_diagnostics)     | Boot diagnostics, on by default.                                                                      | `object`       | `{}`        | no       |
| `capacity_reservation_group_id`             | ID of a capacity reservation group to allocate the virtual machine to.                                | `string`       | `null`      | no       |
| `computer_name`                             | Host name of the virtual machine, applied at first boot.                                              | `string`       | `null`      | no       |
| `dedicated_host_group_id`                   | ID of a dedicated host group to run the virtual machine within.                                       | `string`       | `null`      | no       |
| `dedicated_host_id`                         | ID of a dedicated host to run the virtual machine on.                                                 | `string`       | `null`      | no       |
| `disk_controller_type`                      | Disk controller for the virtual machine's disks: `SCSI` or `NVMe`.                                    | `string`       | `null`      | no       |
| `eviction_policy`                           | What happens when a spot virtual machine is evicted: `Deallocate` or `Delete`.                        | `string`       | `null`      | no       |
| [`identity`](#identity)                     | Managed service identity for the virtual machine.                                                     | `object`       | `null`      | no       |
| [`initial_contact`](#initial_contact)       | Initial contact data. Sensitive. `null` boots an unconfigured engine.                                 | `string`       | `null`      | no       |
| `location`                                  | Azure location to deploy into, for example `westeurope`.                                              | `string`       | n/a         | **yes**  |
| `max_bid_price`                             | Maximum hourly price for a spot virtual machine.                                                      | `number`       | `null`      | no       |
| `name`                                      | Name of the Security Engine virtual machine.                                                          | `string`       | n/a         | **yes**  |
| [`network_interfaces`](#network_interfaces) | Interfaces in guest order; each element mirrors the provider's `azurerm_network_interface` arguments. | `list(object)` | n/a         | **yes**  |
| [`os_disk`](#os_disk)                       | Operating system disk, mirroring the virtual machine's `os_disk` block.                               | `object`       | `{}`        | no       |
| `priority`                                  | Virtual machine priority: `Regular` or `Spot`.                                                        | `string`       | `"Regular"` | no       |
| `resource_group_name`                       | Name of the resource group to deploy into.                                                            | `string`       | n/a         | **yes**  |
| `size`                                      | Virtual machine size, for example `Standard_B4ms`.                                                    | `string`       | n/a         | **yes**  |
| [`source_image`](#source_image)             | Boot image: the Forcepoint marketplace template by default, or a custom image.                        | `object`       | `{}`        | no       |
| [`ssh_public_keys`](#ssh_public_keys)       | Public keys in OpenSSH `authorized_keys` format, granted access as `admin_username`.                  | `list(string)` | n/a         | **yes**  |
| `tags`                                      | Tags applied to the virtual machine. The interfaces and public IPs are not tagged.                    | `map(string)`  | `{}`        | no       |
| `zone`                                      | Availability zone, for example `1`. `null` leaves the placement within the location.                  | `number`       | `null`      | no       |

### `network_interfaces`

The list index in `network_interfaces` is the guest interface index: element
0 is `nic0`, element 1 is `nic1`. The SMC numbers its interface definitions
the same way, so the order is part of the contract with it. The effect of a
change is per [What replaces the instance](#what-replaces-the-instance).

The module creates one `azurerm_network_interface` per element, in
`location`, and attaches the addresses you give it; it reserves none.
`nic0` is the management interface. An ephemeral private address can change
when the NIC is replaced, so for an address that must survive, pass a
`private_ip_address` inside the subnet's prefix, the way the
[example](examples/single-engine) pins host 10 of each subnet.

Each element mirrors the provider's `azurerm_network_interface` arguments:
the interface's arguments, and one or more `ip_configuration` blocks with
the provider's `ip_configuration` arguments. The first configuration is the
interface's primary address; additional configurations are secondary
addresses on the same guest interface, in the same subnet, for example for
the reserved public IPs of an HA pair.
A single configuration is primary without the flag; with more than one,
exactly one must carry `primary = true`. Each configuration can carry its
own public IP.

| Attribute                   | Type           | Default         | Description                                                                |
|-----------------------------|----------------|-----------------|----------------------------------------------------------------------------|
| `name`                      | `string`       | `<name>-nic<N>` | network interface name                                                     |
| `ip_forwarding`             | `bool`         | `true`          | IP forwarding on the interface; required for the engine to forward traffic |
| `dns_servers`               | `list(string)` | `null`          | DNS servers for the interface                                              |
| `network_security_group_id` | `string`       | `null`          | network security group to attach to the interface                          |
| `ip_configuration`          | `list(object)` | **required**    | the interface's IP configurations, one or more, in order                   |

`ip_configuration` mirrors the provider's `ip_configuration` block, plus the
`public_ip` object the module creates when present:

| Attribute                       | Type     | Default      | Description                                                               |
|---------------------------------|----------|--------------|---------------------------------------------------------------------------|
| `name`                          | `string` | `ip-nic<N>`  | configuration name; `ip-nic<N>-<number>` from the second on               |
| `primary`                       | `bool`   | `false`      | marks the primary configuration; exactly one when there is more than one  |
| `subnet_id`                     | `string` | **required** | ID of the subnet                                                          |
| `private_ip_address_allocation` | `string` | `"Dynamic"`  | `Dynamic` or `Static`                                                     |
| `private_ip_address`            | `string` | `null`       | static private address, inside the subnet's prefix                        |
| `private_ip_address_version`    | `string` | `"IPv4"`     | `IPv4` or `IPv6`                                                          |
| `public_ip_address_id`          | `string` | `null`       | attach an existing public IP instead of creating one                      |
| `public_ip`                     | `object` | `null`       | the public IP the module creates for the configuration                    |

`public_ip` mirrors the provider's `azurerm_public_ip` arguments:

| Attribute                 | Type     | Default             | Description                                                                   |
|---------------------------|----------|---------------------|-------------------------------------------------------------------------------|
| `name`                    | `string` | `<name>-nic<N>-pip` | public IP name; `<name>-nic<N>-<number>-pip` from the second configuration on |
| `allocation_method`       | `string` | `"Static"`          | `Static` or `Dynamic`                                                         |
| `sku`                     | `string` | `"Standard"`        | `Standard` or `Basic`                                                         |
| `ip_version`              | `string` | `"IPv4"`            | `IPv4` or `IPv6`                                                              |
| `zone`                    | `string` | the VM's `zone`     | zonal public IPs are Standard SKU                                             |
| `domain_name_label`       | `string` | `null`              | FQDN label for the public IP                                                  |
| `idle_timeout_in_minutes` | `number` | `null`              | TCP idle timeout, in minutes                                                  |
| `ddos_protection_plan_id` | `string` | `null`              | DDoS protection plan to apply                                                 |

Constraints:

1. **`nic0` is management.** Use it as the control interface in the SMC.
2. **One subnet per interface.** A three-interface engine needs three
   subnets, and all configurations of an interface use its subnet. The
   module rejects duplicates and mixed subnets.
3. **All subnets in `var.location`.**
4. **At most one public IP per configuration.** Either created by the module
   (`public_ip`) or existing (`public_ip_address_id`); not both.
5. **A dynamic public IP can only be `Basic` SKU, and a zonal one `Standard`.**
   Public IPs on a zonal virtual machine inherit `var.zone`.

To route workloads through the engine, point a route table's default route
at `private_ips["nic1"]` with next hop type `VirtualAppliance`, and attach
it to the workload subnets only.

### `source_image`

By default the engine boots from the template Forcepoint publishes to the
Azure Marketplace. The marketplace fields form the template's
`Publisher:Offer:Sku:Version` reference; the module attaches the matching
marketplace plan to the virtual machine.

| Attribute   | Type     | Default             | Description                                                 |
|-------------|----------|---------------------|-------------------------------------------------------------|
| `publisher` | `string` | `"forcepoint-llc"`  | Marketplace publisher                                       |
| `offer`     | `string` | `"forcepoint-ngfw"` | Marketplace product                                         |
| `sku`       | `string` | `"ngfw_payg"`       | Marketplace plan; `ngfw_byol` brings your own license       |
| `version`   | `string` | `"7.3.5"`           | template version, for example `7.5.1`                       |
| `image_id`  | `string` | `null`              | custom image, community image or shared image gallery image |

Accept the offer's terms in your subscription before the first apply, or
Azure rejects the virtual machine with a message pointing at the marketplace
offer:

```bash
az vm image terms accept --publisher forcepoint-llc \
  --offer forcepoint-ngfw --plan ngfw_payg
```

When `image_id` is set it replaces the template entirely: the marketplace
fields are ignored and no plan is attached. A change to any marketplace
field, or to `image_id`, replaces the instance, as documented in
[What replaces the instance](#what-replaces-the-instance).

### `initial_contact`

Optional. Initial contact data, passed to the engine through custom data. The
engine reads it on first boot and contacts the SMC, which then shows the engine
as online. Leave it unset to boot an unconfigured engine, and configure it
later over the console with `sg-reconfigure`.

Produce it by creating the engine element in the SMC and saving its initial
configuration. The file carries a one-time password with limited validity, so
generate it close to the apply. A base64-wrapped configuration is not
accepted: the module base64-encodes it.

For cloud-initiated contact, where the engine creates its own SMC element over
the SMC API, pass a JSON document instead of an `engine.cfg`. It carries the
SMC address and an API key. See the Forcepoint documentation for the format.

### `ssh_public_keys`

Installed for `admin_username`, by default `azure`, the engine's cloud login:

```bash
ssh azure@$(terraform output -raw management_public_ip)
```

Azure installs the keys at creation only, so a change to `ssh_public_keys`
or `admin_username` replaces the instance.

### `os_disk`

| Attribute                | Type     | Default             | Description                                                                        |
|--------------------------|----------|---------------------|------------------------------------------------------------------------------------|
| `caching`                | `string` | `"ReadWrite"`       | `ReadWrite` or `None`                                                              |
| `disk_size_gb`           | `number` | `null`              | GB. `null` uses the image's minimum size                                           |
| `storage_account_type`   | `string` | `"StandardSSD_LRS"` | `Standard_LRS`, `StandardSSD_LRS`, `StandardSSD_ZRS`, `Premium_LRS`, `Premium_ZRS` |
| `disk_encryption_set_id` | `string` | `null`              | ID of a disk encryption set to encrypt the disk with                               |

### `boot_diagnostics`

Stores the serial console output and screenshots of the first boot. Enabled by
default for capturing boot time output.

| Attribute             | Type     | Default | Description                                                                                                             |
|-----------------------|----------|---------|-------------------------------------------------------------------------------------------------------------------------|
| `enabled`             | `bool`   | `true`  | store the boot diagnostics                                                                                              |
| `storage_account_uri` | `string` | `null`  | endpoint of the storage account receiving the diagnostics; `null` uses a managed storage account for the resource group |

### `identity`

The managed service identity of the virtual machine. `null` (the default)
configures no identity.

| Attribute      | Type           | Default      | Description                                                                   |
|----------------|----------------|--------------|-------------------------------------------------------------------------------|
| `type`         | `string`       | **required** | `SystemAssigned`, `UserAssigned`, or `SystemAssigned, UserAssigned`           |
| `identity_ids` | `list(string)` | `null`       | IDs of user-assigned identities; required when `type` includes `UserAssigned` |

An HA pair, for example, runs its failover script under a user-assigned
identity authorized on the Azure API.

## Outputs

| Name                    | Description                                                                                                       |
|-------------------------|-------------------------------------------------------------------------------------------------------------------|
| `id`                    | Fully qualified resource identifier of the engine virtual machine.                                                |
| `instance`              | The full `azurerm_linux_virtual_machine` object, for attributes this module does not surface. Sensitive.          |
| `location`              | Location the engine runs in.                                                                                      |
| `management_private_ip` | Private IPv4 address of `nic0`, the SMC management address.                                                       |
| `management_public_ip`  | Public IPv4 address of `nic0`'s first IP configuration, or `null` when it has none.                               |
| `name`                  | Name of the engine virtual machine.                                                                               |
| `network_interfaces`    | Per-interface `index`, `name`, `subnet_id`, `private_ip`, `public_ip` and `ip_configurations`, keyed by NIC name. |
| `private_ips`           | Private IPv4 address per interface, keyed `nic0`, `nic1`, and so on.                                              |
| `public_ip_ids`         | Resource ID of the public IP on each IP configuration that has one, keyed like `public_ips`.                      |
| `public_ips`            | Public IPv4 address per IP configuration the module gave a public IP, keyed `nic<N>`, then `nic<N>-<number>`.     |
| `resource_group_name`   | Resource group the engine runs in.                                                                                |

## Resources

| Resource                                                                                                                                                                                      | Type     | Created when                                        |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------|
| [`azurerm_linux_virtual_machine.engine`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine)                                               | resource | always                                              |
| [`azurerm_network_interface.engine`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface)                                                       | resource | one per `network_interfaces` element                |
| [`azurerm_public_ip.engine`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip)                                                                       | resource | per `ip_configuration` carrying a `public_ip` block |
| [`azurerm_network_interface_security_group_association.engine`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_security_group_association) | resource | per interface with a `network_security_group_id`    |

## What replaces the instance

Replacement means downtime for a single engine.

| Change                                                                                                                            | Effect                                                |
|-----------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------|
| `initial_contact`                                                                                                                 | **replaces**                                          |
| `source_image`: a different marketplace template, or a different `image_id`                                                       | **replaces**                                          |
| `admin_username`, `ssh_public_keys`                                                                                               | **replaces**                                          |
| `resource_group_name`, `location`, `zone`                                                                                         | **replaces**                                          |
| `computer_name`, `priority`, `eviction_policy`, `availability_set_id`                                                             | **replaces**                                          |
| `os_disk.storage_account_type`                                                                                                    | **replaces**                                          |
| `network_interfaces`: an interface added or removed                                                                               | stop, update, start                                   |
| `size`                                                                                                                            | stop, update, start                                   |
| `network_interfaces`: any other attribute                                                                                         | in place on the NIC; the virtual machine is untouched |
| `os_disk` (`caching`, `disk_size_gb`), `tags`                                                                                     | in place                                              |
| the other virtual machine attributes (`identity`, `boot_diagnostics`, `max_bid_price`, the placement IDs, `disk_controller_type`) | in place                                              |

`initial_contact` replaces because Azure takes custom data at creation only,
and the engine reads it only on first boot.

Stop, update, start changes deallocate the virtual machine for the update.

## Troubleshooting

**The apply fails on the marketplace plan.** Azure rejects virtual machines
whose marketplace offer is not yet accepted in the subscription. Accept the
offer's terms (the command is in the [`source_image`](#source_image) input)
and apply again.

**Never appears in the SMC.** Check that a network security rule permits
the engine to reach the SMC, that the one-time password has not expired, and
that `nic0` really is management.

**Traffic is not forwarded.** Confirm `ip_forwarding` is true on the
interfaces that carry forwarded traffic, and that a route table sends the
workloads' traffic to the engine's interface address with next hop type
`VirtualAppliance`.

**The engine's IP changed after a replacement.** Pass static
`private_ip_address` values; the module attaches what you give it and
reserves nothing.

**SSH refused.** Check `admin_username` and the key. Whether SSH answers is
governed by the engine's policy; use the serial console to diagnose.

**The first boot went wrong and the console is empty.** Boot diagnostics are
on by default and store the serial console output and screenshots in a
managed storage account (or the one in `boot_diagnostics`); they are the
only record of a first boot that never came up.

## Examples

| Example                                   | What it shows                                                                                                                                            |
|-------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`single-engine`](examples/single-engine) | Management, WAN and LAN legs, from an empty subscription.                                                                                                |
| [`standby-ha`](examples/standby-ha)       | A standby HA pair in two availability zones, with the failover script's Azure-side readiness: reserved public IPs, `FP_HA_` tags, the failover identity. |

## Support

These modules are provided as-is and support is best effort based. For the
product itself, refer to your Forcepoint support agreement.

## License

Apache 2.0, see [LICENSE](../../LICENSE).
