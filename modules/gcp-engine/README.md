# Forcepoint Network Security Platform for Google Cloud

Deploys one Forcepoint Network Security Platform Security Engine as a
Google Compute Engine instance, and hands it the initial contact data that
registers it with your Security Management Center (SMC).

The module owns the instance and nothing else. The network it sits on is
created by you and passed in as inputs: the subnetworks, addresses and
security rules. The engine itself is configured in the SMC: policy, VPN
and routing.

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
resource "google_compute_address" "mgmt_internal" {
  name         = "engine-a-mgmt-internal"
  region       = "europe-north1"
  subnetwork   = google_compute_subnetwork.management.id
  address_type = "INTERNAL"
}

resource "google_compute_address" "mgmt_external" {
  name   = "engine-a-mgmt-external"
  region = "europe-north1"
}

module "engine" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine"

  name       = "engine-a"
  project_id = "my-project"
  zone       = "europe-north1-a"

  boot_disk = {
    initialize_params = {
      image = "projects/my-project/global/images/engine-7-6-0"
    }
  }

  network_interfaces = [
    {
      subnetwork    = google_compute_subnetwork.management.id
      network_ip    = google_compute_address.mgmt_internal.address
      access_config = [{
        nat_ip = google_compute_address.mgmt_external.address
      }]
    },
    {
      subnetwork = google_compute_subnetwork.lan.id
    },
  ]

  initial_contact = file("engine.cfg")
  ssh_public_keys = [file("~/.ssh/id_ed25519.pub")]

  network_tags = ["engine"]
}
```

## Requirements

| Requirement                 | Detail                                           |
|-----------------------------|--------------------------------------------------|
| Terraform                   | >= 1.5 to use, >= 1.7 to run the tests           |
| `hashicorp/google` provider | >= 6.0, < 9.0, input to the module               |
| Google cloud credentials    | For example through gcloud login                 |
| Engine image                | Imported outside of this module                  |
| SMC                         | Reachable from `nic0`, for an SMC-managed engine |

## Inputs

| Name                                                        | Description                                                                                                                   | Type           | Default                                              | Required |
|-------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|----------------|------------------------------------------------------|----------|
| `allow_stopping_for_update`                                 | Let Terraform stop the instance for changes that require it, such as machine type or interfaces.                              | `bool`         | `true`                                               | no       |
| `block_project_ssh_keys`                                    | Ignore project-wide SSH keys, so only `ssh_public_keys` grant access.                                                         | `bool`         | `true`                                               | no       |
| [`boot_disk`](#boot_disk)                                   | Boot disk, mirroring the instance's `boot_disk` block. Must carry an engine image.                                            | `object`       | n/a                                                  | **yes**  |
| `can_ip_forward`                                            | Allow the instance to send and receive packets whose source or destination is not its own address.                            | `bool`         | `true`                                               | no       |
| `create_instance_group`                                     | Create a zonal unmanaged instance group for use as a load balancer backend.                                                   | `bool`         | `false`                                              | no       |
| `deletion_protection`                                       | Reject delete calls, including `terraform destroy`, until cleared.                                                            | `bool`         | `false`                                              | no       |
| `enable_guest_attributes`                                   | Enable the guest attributes endpoint, required by the GCP HA Module for peer status signalling.                               | `bool`         | `true`                                               | no       |
| `enable_serial_console`                                     | Enable serial console access. Reachable by anyone holding the IAM permission on the project.                                  | `bool`         | `false`                                              | no       |
| `initial_contact_replace_on_change`                         | Replace the instance when `initial_contact` changes.                                                                          | `bool`         | `true`                                               | no       |
| [`initial_contact`](#initial_contact)                       | Initial contact data. Sensitive. `null` boots an unconfigured engine.                                                         | `string`       | `null`                                               | no       |
| `instance_group_name`                                       | Name of the instance group. Defaults to `<name>-ig`.                                                                          | `string`       | `null`                                               | no       |
| [`instance_group_named_ports`](#instance_group_named_ports) | Named ports on the instance group. Backend services reference the port by name.                                               | `list(object)` | `[]`                                                 | no       |
| `labels`                                                    | Labels applied to the instance and the boot disk.                                                                             | `map(string)`  | `{}`                                                 | no       |
| `machine_type`                                              | Machine type. Determines throughput (egress bandwidth per vCPU) and maximum NIC count (one vCPU per interface).               | `string`       | `"n2-standard-4"`                                    | no       |
| `metadata`                                                  | Additional instance metadata, merged last. Overrides any key this module computes, including `startup-script` and `ssh-keys`. | `map(string)`  | `{}`                                                 | no       |
| `min_cpu_platform`                                          | Minimum CPU platform, for example `Intel Cascade Lake`.                                                                       | `string`       | `null`                                               | no       |
| `name`                                                      | Name of the Security Engine instance. Must be a valid GCE resource name.                                                      | `string`       | n/a                                                  | **yes**  |
| [`network_interfaces`](#network_interfaces)                 | Interfaces in guest order, mirroring the instance's `network_interface` blocks.                                              | `list(object)` | n/a                                                  | **yes**  |
| `network_tags`                                              | Network tags applied to the instance. VPC firewall rules and routes select instances by these.                                | `list(string)` | `[]`                                                 | no       |
| `project_id`                                                | Project to deploy into. Defaults to the provider's project.                                                                   | `string`       | `null`                                               | no       |
| `resource_policies`                                         | Self-links of resource policies to attach, for example a snapshot schedule.                                                   | `list(string)` | `[]`                                                 | no       |
| [`scheduling`](#scheduling)                                 | Instance scheduling, mirroring the instance's `scheduling` block.                                                             | `object`       | `{}`                                                 | no       |
| [`service_account`](#service_account)                       | Service account to attach, mirroring the instance's `service_account` block.                                                  | `object`       | `null`                                               | no       |
| [`ssh_public_keys`](#ssh_public_keys)                       | Public keys in OpenSSH `authorized_keys` format, granted access as `gencloud`                                                 | `list(string)` | `[]`                                                 | no       |
| `zone`                                                      | Zone to deploy into, for example `europe-north1-a`.                                                                           | `string`       | n/a                                                  | **yes**  |

### `network_interfaces`

The list index in `network_interfaces` is the guest interface index: element 0
is `nic0`, element 1 is `nic1`. The SMC numbers its interface definitions the
same way, so the order is part of the contract with it. The provider attaches
the interfaces in list order; the effect of a change is per [What replaces
the instance](#what-replaces-the-instance).

Each entry mirrors the instance's `network_interface` block, so an interface
written for a plain `google_compute_instance` attaches here unchanged. The
module passes the blocks through and reserves no addresses: `network_ip` and
`access_config.nat_ip` take the values you give, and an `access_config` entry
without `nat_ip` takes an ephemeral one.

Three GCP constraints:

1. **`nic0` is management.** It is the only interface with a DHCP default route
   and metadata server access. Use it as the control interface in the SMC.
2. **One network per interface.** A three-interface engine needs three networks.
   The module rejects duplicates.
3. **All subnetworks in the region of `var.zone`.**

An ephemeral external IP is released when the instance stops, and an
unpinned internal IP can change on replacement. For an IP that must survive
both, reserve a `google_compute_address` in your root module and pass its
`.address` attribute, the way the [example](examples/single-engine) does.

| Attribute                     | Type           | Default       | Description                                                 |
|-------------------------------|----------------|---------------|-------------------------------------------------------------|
| `subnetwork`                  | `string`       | **required**  | self-link, partial URL or name                              |
| `subnetwork_project`          | `string`       | `null`        | subnetwork owner. Set for Shared VPC                        |
| `network_ip`                  | `string`       | `null`        | static internal IPv4, inside the subnetwork's primary range |
| `ipv6_address`                | `string`       | `null`        | static internal IPv6, dual-stack interfaces                 |
| `nic_type`                    | `string`       | `null`        | `VIRTIO_NET` or unset; the engine supports no other type    |
| `queue_count`                 | `number`       | `null`        | `null` lets GCP derive it from the vCPU count               |
| `stack_type`                  | `string`       | `null`        | `IPV4_ONLY` or `IPV4_IPV6`; `null` for the GCP default      |
| `access_config`               | `list(object)` | `[]`          | at most one entry; no entry means no external IPv4          |
| `ipv6_access_config`          | `list(object)` | `[]`          | at most one entry for an external IPv6                      |
| `alias_ip_range`              | `list(object)` | `[]`          | `{ ip_cidr_range, subnetwork_range_name }`                  |

`access_config` entry: `nat_ip` (IP of an external address you own; omit it
for an ephemeral one), `network_tier` (`PREMIUM` or `STANDARD`),
`public_ptr_domain_name` (reverse DNS record).

`ipv6_access_config` entry: `network_tier` (required, `PREMIUM` only),
`external_ipv6` (a static external IPv6 you own) and `name`. An entry
requires `stack_type = "IPV4_IPV6"` on the same interface.

To route workloads through the engine, point a VPC route's `next_hop_ip` at
`internal_ips["nic1"]` and scope it with `tags`.

### `initial_contact`

Optional. Initial contact data, passed to the engine through user-data. The
engine reads it on first boot and contacts the SMC, which then shows the engine
as online. Leave it unset to boot an unconfigured engine, and configure it
later over the console with `sg-reconfigure`.

Produce it by creating the engine element in the SMC and saving its initial
configuration. The file carries a one-time password with limited validity, so
generate it close to the apply. A base64-wrapped configuration is not
accepted: the engine on Google Cloud does not decode it.

For cloud-initiated contact, where the engine creates its own SMC element over
the SMC API, pass a JSON document instead of an `engine.cfg`. It carries the
SMC address and an API key. See the Forcepoint documentation for the format.

### `ssh_public_keys`

Installed for user `gencloud`, the engine's cloud login:

```bash
ssh gencloud@$(terraform output -raw management_external_ip)
```

`block_project_ssh_keys` defaults to `true`, so project-wide keys grant no
access.

The engine installs the keys at first boot only: its sshd fetches the
`ssh-keys` metadata once, while `authorized_keys` does not exist yet, and skips
the fetch on every later boot. New or rotated keys therefore take effect only
on a fresh instance; replace it to rotate keys.

### `boot_disk`

| Attribute                              | Type     | Default                                              | Description                                           |
|----------------------------------------|----------|------------------------------------------------------|-------------------------------------------------------|
| `auto_delete`                          | `bool`   | `true`                                               | delete the disk with the instance                     |
| `device_name`                          | `string` | `null`                                               | name under `/dev/disk/by-id/google-*`                 |
| `kms_key_self_link`                    | `string` | `null`                                               | customer-managed encryption key                       |
| `initialize_params.image`              | `string` | **required**                                         | self-link, partial URL or name of the engine image    |
| `initialize_params.size`               | `number` | `null`                                               | GB. `null` uses the image's size                      |
| `initialize_params.type`               | `string` | `"pd-balanced"`                                      | `pd-balanced`, `pd-ssd`, `pd-standard`, `hyperdisk-*` |
| `initialize_params.provisioned_iops`   | `number` | `null`                                               | for disk types that support it                        |
| `initialize_params.provisioned_throughput` | `number` | `null`                                           | MB/s, for disk types that support it                  |

The image is imported into the project outside of this module and must carry
the `MULTI_IP_SUBNET` guest OS feature, or the engine forwards nothing. Set
the feature as the final step of the import.

```bash
gcloud compute images create engine-7-6-0 \
  --source-image ngfw-7-6-0-imported \
  --guest-os-features MULTI_IP_SUBNET \
  --project my-project
```

`boot_disk.initialize_params.image` takes the final image's name.

A change to `initialize_params.image` that resolves to a different image
replaces the instance, as documented in
[What replaces the instance](#what-replaces-the-instance).

### `service_account`

| Attribute | Type           | Default                                            | Description                            |
|-----------|----------------|----------------------------------------------------|----------------------------------------|
| `email`   | `string`       | **required**                                       | account to attach                      |
| `scopes`  | `list(string)` | `["https://www.googleapis.com/auth/cloud-platform"]` | tokens the metadata server can issue |

`null` attaches no account, not even the project default. Required for engine
features that call Google APIs, such as HA failover.

### `scheduling`

| Attribute             | Type     | Default      | Description                                         |
|-----------------------|----------|--------------|-----------------------------------------------------|
| `automatic_restart`   | `bool`   | `true`       | restart after a GCP-initiated termination           |
| `on_host_maintenance` | `string` | `"MIGRATE"`  | `MIGRATE` or `TERMINATE`                            |
| `preemptible`         | `bool`   | `false`      | requires the two settings above and `SPOT`          |
| `provisioning_model`  | `string` | `"STANDARD"` | `STANDARD` or `SPOT`; `SPOT` requires the two above |

### `instance_group_named_ports`

| Attribute | Type     | Default      | Description                      |
|-----------|----------|--------------|----------------------------------|
| `name`    | `string` | **required** | name a backend service refers to |
| `port`    | `number` | **required** | TCP port number                  |

## Outputs

| Name                            | Description                                                                                         |
|---------------------------------|-----------------------------------------------------------------------------------------------------|
| `external_ips`                  | External IPv4 address per interface that has one, keyed by NIC name.                                |
| `external_ipv6s`                | External IPv6 address per dual-stack interface that has one, keyed by NIC name.                     |
| `id`                            | Fully qualified instance identifier, `projects/<project>/zones/<zone>/instances/<name>`.            |
| `instance_group_id`             | ID of the unmanaged instance group, or `null` when `create_instance_group` is `false`.              |
| `instance_group_self_link`      | Self-link of the unmanaged instance group, or `null` when `create_instance_group` is `false`        |
| `instance_id`                   | Numeric server-assigned instance ID, stable for the life of the instance.                           |
| `instance`                      | The full `google_compute_instance` object, for attributes this module does not surface.             |
| `internal_ips`                  | Internal IPv4 address per interface, keyed `nic0`, `nic1`, and so on.                               |
| `management_external_ip`        | External IPv4 address of `nic0`, or `null` when the management interface has none.                  |
| `management_internal_ip`        | Internal IPv4 address of `nic0`, the SMC management address.                                        |
| `name`                          | Name of the engine instance.                                                                        |
| `network_interfaces`            | Per-interface `index`, `subnetwork`, `network`, `internal_ip` and `external_ip`, keyed by NIC name. |
| `self_link`                     | Self-link of the engine instance.                                                                   |
| `service_account_email`         | Service account attached to the instance, or `null` when none is.                                   |
| `zone`                          | Zone the instance runs in.                                                                          |

## Resources

| Resource                                                                                                                                        | Type        | Created when                                    |
|-------------------------------------------------------------------------------------------------------------------------------------------------|-------------|-------------------------------------------------|
| [`google_compute_instance.engine`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)             | resource    | always                                          |
| [`google_compute_instance_group.engine`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_group) | resource    | `create_instance_group = true`                  |
| [`terraform_data.initial_contact`](https://developer.hashicorp.com/terraform/language/resources/terraform-data)                                 | resource    | always, inert unless replacement is enabled     |

## What replaces the instance

Replacement means downtime for a single engine.

| Change                                                             | Effect                             |
|--------------------------------------------------------------------|------------------------------------|
| `initial_contact`                                                  | **replaces**                       |
| `boot_disk.initialize_params.image` resolving to a different image | **replaces**                       |
| `network_interfaces`: an interface added or removed                | stop, update, start                |
| `network_interfaces`: `subnetwork` or `subnetwork_project`         | stop, update, start                |
| `machine_type`, `min_cpu_platform`, `service_account`              | stop, update, start                |
| `network_interfaces`: `access_config`                              | in place, no restart               |
| `metadata`, `labels`, `network_tags`                               | in place, no restart               |
| `ssh_public_keys`                                                  | in place, no effect until replaced |
| `create_instance_group`                                            | in place                           |

`initial_contact` replaces because GCP applies metadata in place, while the
engine reads it only on first boot. Set
`initial_contact_replace_on_change = false` if you re-provision by other means.

Stop, update, start changes need `allow_stopping_for_update`, which defaults
to `true`.

## Troubleshooting

**Never appears in the SMC.** Check that a VPC firewall rule permits the engine
to reach the SMC, that the one-time password has not expired, and that `nic0`
really is management.

**Traffic is not forwarded.** Confirm the image carries `MULTI_IP_SUBNET`
(`gcloud compute images describe <image> --format='value(guestOsFeatures)'`),
that `can_ip_forward` is true, and that a VPC route sends traffic to the
engine's LAN address.

**The engine's IP changed after a replacement.** Reserve the addresses with
`google_compute_address` and pass them through `network_ip` or
`access_config.nat_ip`; the module attaches what you give it and reserves
nothing.

**SSH refused.** Use `enable_serial_console = true` to diagnose.

**A rotated key is refused on an existing engine.** The engine installs SSH
keys at first boot only, so changing `ssh_public_keys` on a running instance
has no effect. Replace the instance for the new keys to land.

## Examples

| Example                                   | What it shows                                        |
|-------------------------------------------|------------------------------------------------------|
| [`single-engine`](examples/single-engine) | Management, WAN and LAN legs, from an empty project. |

## Support

These modules are provided as-is and support is best effort based. For the
product itself, refer to your Forcepoint support agreement.

## License

Apache 2.0, see [LICENSE](../../LICENSE).
