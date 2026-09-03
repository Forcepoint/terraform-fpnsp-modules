# Forcepoint Network Security Platform Terraform modules

Terraform modules for deploying Forcepoint Network Security Platform on public
cloud providers.

| Module                             | Deploys                                   |
|------------------------------------|-------------------------------------------|
| [`gcp-engine`](modules/gcp-engine) | Security Engine on Google Cloud           |
| [`aws-smc`](modules/aws-smc)       | Security Management Center servers on AWS |

Each module documents its own inputs, outputs and examples. Start from the
module's README and its `examples/` directory.

## Usage

The `//` separates the repository from the module's path inside it:

```hcl
module "engine" {
  source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine"

  name = "engine-a"
  zone = "europe-north1-a"
  # ...
}
```

Pin a tag or commit in production, so a new revision cannot change
infrastructure unexpectedly. The subdirectory goes before `?ref=`:

```hcl
source = "github.com/Forcepoint/terraform-fpnsp-modules//modules/gcp-engine?ref=v0.1.0"
```

## Support

These modules are provided as-is and support is best effort based. For the
product itself, refer to your Forcepoint support agreement.

## License

Apache 2.0, see [LICENSE](LICENSE).
