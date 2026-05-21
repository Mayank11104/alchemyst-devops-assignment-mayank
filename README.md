# Alchemyst DevOps Internship Assignment — Mayank

This repo contains:

- `app/quickstart`: The Alchemyst `iii` distributed inference quickstart (engine + workers).
- `infra/`: Infrastructure-as-code to deploy the workers across multiple AWS VMs in a private subnet.
- `deploy/cloud-init/`: VM bootstrap scripts (cloud-init) that install dependencies and start the workers.

I will:

1. Provision a VPC with a public subnet (API gateway) and a private subnet (iii engine + workers).
2. Run the TypeScript caller worker and Python inference worker on separate VMs that talk over RPC via the `iii` engine.
3. Expose a JSON HTTP API for `/v1/chat/completions` through a single public endpoint.
4. Make the whole stack reproducible with Terraform and cloud-init.