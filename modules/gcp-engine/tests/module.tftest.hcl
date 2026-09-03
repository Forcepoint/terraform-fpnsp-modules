# The provider is mocked, so every assertion must hold at plan time.

mock_provider "google" {}

variables {
  name = "engine-test"
  zone = "europe-north1-a"

  boot_disk = {
    initialize_params = {
      image = "projects/example/global/images/engine-7-6-0"
    }
  }

  network_interfaces = [
    {
      subnetwork    = "management"
      access_config = [{ nat_ip = "203.0.113.10" }]
    },
    {
      subnetwork = "outside"
    },
    {
      subnetwork = "inside"
    },
  ]
}

run "per_interface_outputs_follow_guest_order" {
  command = plan

  assert {
    condition     = keys(output.network_interfaces) == ["nic0", "nic1", "nic2"]
    error_message = "The per-interface outputs must be keyed in guest order, nic0 first."
  }

  assert {
    condition     = contains(keys(output.external_ips), "nic0")
    error_message = "The management interface's external IP must be surfaced."
  }

  assert {
    condition     = !contains(keys(output.external_ips), "nic1")
    error_message = "An interface without an access_config must not appear in external_ips."
  }
}

run "network_interface_blocks_pass_through" {
  command = plan

  variables {
    network_interfaces = [
      {
        subnetwork   = "management"
        network_ip   = "10.0.0.10"
        nic_type     = "VIRTIO_NET"
        stack_type   = "IPV4_IPV6"
        ipv6_address = "2001:db8::1"

        access_config = [
          {
            nat_ip                 = "203.0.113.10"
            network_tier           = "STANDARD"
            public_ptr_domain_name = "example.com"
          },
        ]

        ipv6_access_config = [
          {
            network_tier  = "PREMIUM"
            external_ipv6 = "2600::1"
          },
        ]

        alias_ip_range = [
          {
            ip_cidr_range         = "10.2.0.0/24"
            subnetwork_range_name = "extra"
          },
        ]
      },
    ]
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].network_ip == "10.0.0.10"
    error_message = "network_ip must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].nic_type == "VIRTIO_NET"
    error_message = "nic_type must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].stack_type == "IPV4_IPV6"
    error_message = "stack_type must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].ipv6_address == "2001:db8::1"
    error_message = "ipv6_address must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].access_config[0].nat_ip == "203.0.113.10"
    error_message = "access_config.nat_ip must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].access_config[0].network_tier == "STANDARD"
    error_message = "access_config.network_tier must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].access_config[0].public_ptr_domain_name == "example.com"
    error_message = "access_config.public_ptr_domain_name must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].ipv6_access_config[0].network_tier == "PREMIUM"
    error_message = "ipv6_access_config.network_tier must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].ipv6_access_config[0].external_ipv6 == "2600::1"
    error_message = "A static external IPv6 must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].alias_ip_range[0].ip_cidr_range == "10.2.0.0/24"
    error_message = "alias_ip_range must reach the instance unchanged."
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].alias_ip_range[0].subnetwork_range_name == "extra"
    error_message = "alias_ip_range.subnetwork_range_name must reach the instance unchanged."
  }
}

run "an_empty_access_config_is_an_ephemeral_external_ip" {
  command = plan

  variables {
    network_interfaces = [
      {
        subnetwork    = "management"
        access_config = [{}]
      },
    ]
  }

  assert {
    condition     = length(google_compute_instance.engine.network_interface[0].access_config) == 1
    error_message = "An empty access_config still requests an external address; omit the block for none."
  }
}

run "no_access_config_means_no_public_ip" {
  command = plan

  variables {
    network_interfaces = [
      { subnetwork = "inside" },
    ]
  }

  assert {
    condition     = length(google_compute_instance.engine.network_interface[0].access_config) == 0
    error_message = "Without an access_config the interface must have no external address."
  }
}

run "subnetwork_project_defaults_to_the_instance_project" {
  command = plan

  variables {
    project_id = "instance-project"

    network_interfaces = [
      {
        subnetwork = "projects/host-project/regions/europe-north1/subnetworks/mgmt"
      },
    ]
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].subnetwork_project == "instance-project"
    error_message = "Without subnetwork_project the instance's project must be used."
  }
}

run "subnetwork_project_override_wins" {
  command = plan

  variables {
    project_id = "instance-project"

    network_interfaces = [
      {
        subnetwork         = "projects/host-project/regions/europe-north1/subnetworks/mgmt"
        subnetwork_project = "host-project"
      },
    ]
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[0].subnetwork_project == "host-project"
    error_message = "A Shared VPC subnetwork must keep its host project."
  }
}

run "initial_contact_becomes_the_startup_script" {
  command = plan

  variables {
    initial_contact = "stonegate/system/hostname string engine-test\n"
    ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI00000000000000000000000000000000000 me@example"]
  }

  assert {
    condition     = google_compute_instance.engine.metadata["startup-script"] == "stonegate/system/hostname string engine-test\n"
    error_message = "initial_contact must be delivered through the startup-script metadata key."
  }

  assert {
    condition     = startswith(google_compute_instance.engine.metadata["ssh-keys"], "gencloud:ssh-ed25519 ")
    error_message = "SSH keys must be prefixed with the gencloud login."
  }

  assert {
    condition     = google_compute_instance.engine.metadata["block-project-ssh-keys"] == "TRUE"
    error_message = "Project-wide SSH keys must be blocked by default."
  }

  assert {
    condition     = terraform_data.initial_contact.triggers_replace != null
    error_message = "A changed initial_contact must be able to trigger replacement."
  }
}

run "cloud_contact_document_is_accepted" {
  command = plan

  variables {
    initial_contact = "{\"smc-contact\":{\"address\":\"smc.example.com\",\"apikey\":\"secret\"},\"type\":\"single-firewall\"}"
  }

  assert {
    condition     = can(jsondecode(google_compute_instance.engine.metadata["startup-script"]))
    error_message = "A cloud contact document must be passed through unmodified."
  }
}

run "no_initial_contact_metadata_without_inputs" {
  command = plan

  assert {
    condition     = !contains(keys(google_compute_instance.engine.metadata), "startup-script")
    error_message = "Without initial_contact there must be no startup-script key at all."
  }

  assert {
    condition     = !contains(keys(google_compute_instance.engine.metadata), "ssh-keys")
    error_message = "Without ssh_public_keys there must be no ssh-keys key at all."
  }

  assert {
    condition     = terraform_data.initial_contact.triggers_replace == null
    error_message = "With no initial_contact there is nothing to trigger replacement on."
  }
}

run "caller_metadata_wins" {
  command = plan

  variables {
    initial_contact = "stonegate/system/hostname string engine-test\n"

    metadata = {
      startup-script = "overridden"
      FP_HA_role     = "primary"
    }
  }

  assert {
    condition     = google_compute_instance.engine.metadata["startup-script"] == "overridden"
    error_message = "var.metadata is merged last, so it must override computed keys."
  }

  assert {
    condition     = google_compute_instance.engine.metadata["FP_HA_role"] == "primary"
    error_message = "Extra metadata keys must be passed through."
  }
}

run "ha_metadata_toggles" {
  command = plan

  variables {
    enable_serial_console = true
  }

  assert {
    condition     = google_compute_instance.engine.metadata["enable-guest-attributes"] == "TRUE"
    error_message = "Guest attributes are required by the GCP HA module and must be on by default."
  }

  assert {
    condition     = google_compute_instance.engine.metadata["serial-port-enable"] == "TRUE"
    error_message = "The serial console toggle must reach the instance metadata."
  }
}

run "guest_attributes_can_be_disabled" {
  command = plan

  variables {
    enable_guest_attributes = false
  }

  assert {
    condition     = !contains(keys(google_compute_instance.engine.metadata), "enable-guest-attributes")
    error_message = "Setting enable_guest_attributes to false must omit the metadata key."
  }
}

run "forwarding_is_enabled_by_default" {
  command = plan

  assert {
    condition     = google_compute_instance.engine.can_ip_forward
    error_message = "An engine must be allowed to forward packets it is not addressed to."
  }
}

run "no_service_account_unless_asked" {
  command = plan

  assert {
    condition     = length(google_compute_instance.engine.service_account) == 0
    error_message = "With no account, the block must be omitted so GCP attaches no default account."
  }
}

run "service_account_is_attached_with_scopes" {
  command = plan

  variables {
    service_account = {
      email = "engine@example.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = google_compute_instance.engine.service_account[0].email == "engine@example.iam.gserviceaccount.com"
    error_message = "The service account must reach the instance."
  }

  assert {
    condition     = contains(google_compute_instance.engine.service_account[0].scopes, "https://www.googleapis.com/auth/cloud-platform")
    error_message = "The default scope must be cloud-platform, restricted by IAM instead."
  }
}

run "instance_group_is_optional" {
  command = plan

  assert {
    condition     = length(google_compute_instance_group.engine) == 0
    error_message = "No instance group unless create_instance_group is set."
  }
}

run "instance_group_carries_named_ports" {
  command = plan

  variables {
    create_instance_group = true

    instance_group_named_ports = [
      { name = "http", port = 80 },
    ]
  }

  assert {
    condition     = google_compute_instance_group.engine[0].name == "engine-test-ig"
    error_message = "The instance group name must default to <name>-ig."
  }

  assert {
    condition     = google_compute_instance_group.engine[0].zone == "europe-north1-a"
    error_message = "The instance group must be zonal, in the instance's zone."
  }
}

run "a_boot_disk_image_is_required" {
  command = plan

  variables {
    boot_disk = {
      initialize_params = {
        image = ""
      }
    }
  }

  expect_failures = [var.boot_disk]
}

run "a_null_boot_disk_image_is_rejected" {
  command = plan

  variables {
    boot_disk = {
      initialize_params = {
        image = null
      }
    }
  }

  expect_failures = [var.boot_disk]
}

run "duplicate_subnetworks_are_rejected" {
  command = plan

  variables {
    network_interfaces = [
      { subnetwork = "shared" },
      { subnetwork = "shared" },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "same_subnetwork_name_in_different_projects_is_allowed" {
  command = plan

  variables {
    network_interfaces = [
      { subnetwork = "mgmt", subnetwork_project = "host-a" },
      { subnetwork = "mgmt", subnetwork_project = "host-b" },
    ]
  }

  assert {
    condition     = google_compute_instance.engine.network_interface[1].subnetwork_project == "host-b"
    error_message = "Same-named subnetworks in different host projects are different subnetworks."
  }
}

run "gvnic_is_rejected" {
  command = plan

  variables {
    network_interfaces = [
      {
        subnetwork = "management"
        nic_type   = "GVNIC"
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "ipv6_access_config_requires_a_dual_stack_interface" {
  command = plan

  variables {
    network_interfaces = [
      {
        subnetwork         = "management"
        ipv6_access_config = [{ network_tier = "PREMIUM" }]
      },
    ]
  }

  expect_failures = [var.network_interfaces]
}

run "an_interface_is_required" {
  command = plan

  variables {
    network_interfaces = []
  }

  expect_failures = [var.network_interfaces]
}

run "invalid_instance_name_is_rejected" {
  command = plan

  variables {
    name = "Engine_Test"
  }

  expect_failures = [var.name]
}

run "a_region_is_not_a_zone" {
  command = plan

  variables {
    zone = "europe-north1"
  }

  expect_failures = [var.zone]
}

run "preemptible_requires_its_companion_settings" {
  command = plan

  variables {
    scheduling = {
      preemptible = true
    }
  }

  expect_failures = [var.scheduling]
}

run "spot_requires_its_companion_settings" {
  command = plan

  variables {
    scheduling = {
      provisioning_model = "SPOT"
    }
  }

  expect_failures = [var.scheduling]
}

run "preemptible_with_spot_and_companion_settings" {
  command = plan

  variables {
    scheduling = {
      preemptible         = true
      provisioning_model  = "SPOT"
      automatic_restart   = false
      on_host_maintenance = "TERMINATE"
    }
  }

  assert {
    condition     = google_compute_instance.engine.scheduling[0].preemptible
    error_message = "The preemptible flag must reach the instance scheduling."
  }

  assert {
    condition     = google_compute_instance.engine.scheduling[0].provisioning_model == "SPOT"
    error_message = "The SPOT model must reach the instance scheduling."
  }
}

run "garbage_initial_contact_is_rejected" {
  command = plan

  variables {
    initial_contact = "just some text that is neither an engine.cfg nor JSON"
  }

  expect_failures = [var.initial_contact]
}

run "base64_wrapped_initial_contact_is_rejected" {
  command = plan

  variables {
    initial_contact = base64encode("stonegate/system/hostname string engine-test\n")
  }

  expect_failures = [var.initial_contact]
}
