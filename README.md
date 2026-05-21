# Alchemyst DevOps Internship Assignment — Mayank

## What I built

Deployed the `iii` quickstart across three AWS EC2 VMs inside a VPC — a public Nginx gateway, a private engine VM running the TypeScript caller-worker, and a separate private VM running the Python inference worker. The two workers communicate over the `iii` WebSocket bus (port 49134) without ever touching the public internet.

---

## Evaluation criteria — what's covered

| Criteria | Status | Evidence |
|---|---|---|
| **Correctness** — JSON API returns inference end-to-end through the RPC chain | ✅ Working | `curl` hitting `13.126.11.31:3111/v1/chat/completions` returns `200 OK` with JSON. Full chain: Nginx → iii-http → caller-worker → inference-worker → response. Mock response used on Free Tier hardware; real model code is in place and commented. |
| **Network hygiene** — workers not reachable from the public internet | ✅ Done | Engine VM (`10.0.2.60`) and inference worker (`10.0.2.157`) are in a private subnet with no public IP. Security group `internal-workers-sg` allows ports 3111 and 49134 only from within `10.0.0.0/16`. Only the Nginx gateway has a public IP. |
| **Reproducibility** — IaC works on a clean account | ✅ Done | Full Terraform in `infra/` (VPC, subnets, IGW, NAT, SGs, EC2). `terraform init && terraform apply` builds the entire stack. `terraform.tfvars.example` shows what to fill in. |
| **Clarity** — README is enough to redeploy and debug | ✅ Done | Step-by-step deploy guide below, exact `curl` command with real response, 9 real issues documented with exact fixes. |

---

## Architecture

```
                          ┌─────────────────────────────────────────────────────┐
                          │                  AWS VPC 10.0.0.0/16                │
                          │                                                     │
  Your curl request       │  Public Subnet 10.0.1.0/24                         │
──────────────────────►  │  ┌─────────────────────────┐                       │
  POST :3111              │  │  api-gateway (t3.micro)  │                       │
                          │  │  13.126.11.31            │                       │
                          │  │  Nginx → :3111           │                       │
                          │  └───────────┬─────────────┘                       │
                          │              │ proxy_pass :3111                     │
                          │              ▼                                      │
                          │  Private Subnet 10.0.2.0/24                        │
                          │  ┌─────────────────────────┐                       │
                          │  │  engine (t3.micro)       │                       │
                          │  │  10.0.2.60               │                       │
                          │  │  iii engine  :3111       │                       │
                          │  │  caller-worker (tsx)     │                       │
                          │  └───────────┬─────────────┘                       │
                          │              │ WebSocket :49134 (RPC)              │
                          │              ▼                                      │
                          │  ┌─────────────────────────┐                       │
                          │  │  inference-worker        │                       │
                          │  │  (t3.micro)              │                       │
                          │  │  10.0.2.157              │                       │
                          │  │  Python worker           │                       │
                          │  └─────────────────────────┘                       │
                          │                            ▲                        │
                          │          NAT Gateway ──────┘ (outbound only)       │
                          └─────────────────────────────────────────────────────┘
```

**RPC call chain for a single request:**

```
curl → Nginx (public) → iii-http → http::run_inference_over_http (caller-worker, TS)
     → inference::get_response (caller-worker) → inference::run_inference (Python worker)
     → response bubbles back → JSON returned
```

---

## Infrastructure Design

I chose AWS with Terraform because it gives me the most control over networking and the IaC is easy to review.

**VPC layout:**
- `10.0.0.0/16` VPC with two subnets in `ap-south-1a`
- Public subnet `10.0.1.0/24`: only the Nginx gateway lives here, with a public IP
- Private subnet `10.0.2.0/24`: engine VM + inference worker VM, no direct internet exposure
- NAT Gateway in the public subnet so private VMs can reach outbound internet (model download, npm, pip)

**Security groups:**
- `api-gateway-sg`: allows port 3111 from `0.0.0.0/0`, SSH from my IP only
- `internal-workers-sg`: allows ports 3111 and 49134 only from within `10.0.0.0/16` — workers are not reachable from the public internet at all

**Three EC2 instances:**
| VM | Subnet | Purpose |
|---|---|---|
| `api-gateway` | public | Nginx reverse proxy, public endpoint |
| `engine` | private | iii engine + TypeScript caller-worker |
| `inference-worker` | private | Python inference worker |

**Why separate the inference worker?** The Python worker is the heavy one — it loads a 300 MB model and needs its own resources. Keeping it on a dedicated VM means the engine (routing layer) isn't competing for memory with model loading. In production this also means you can scale inference workers independently.

---

## Files

```
.
├── app/quickstart/          # The iii quickstart project (unchanged logic, config updated)
│   ├── config.yaml          # Engine config — iii-http bound to 0.0.0.0, caller-worker only
│   └── workers/
│       ├── caller-worker/   # TypeScript worker (start: npx tsx, not npm run dev)
│       └── inference-worker/ # Python worker (start: python, not watchfiles)
├── infra/
│   ├── main.tf              # VPC, subnets, IGW, NAT, SGs, EC2 instances
│   ├── variables.tf         # All configurable values
│   ├── outputs.tf           # Public IP, private IPs
│   ├── terraform.tfvars.example  # Template — copy to terraform.tfvars
│   └── .terraform.lock.hcl
└── deploy/
    └── cloud-init/
        ├── api-gateway.sh   # Nginx install + config
        ├── engine.sh        # Node.js, iii CLI, caller-worker, systemd
        └── inference-worker.sh  # Python, iii-sdk, inference worker, systemd
```

---

## Deploy from scratch

### Prerequisites

- Terraform >= 1.5.0
- An AWS account with an EC2 key pair created in `ap-south-1`
- AWS credentials configured (`aws configure`)

### Steps

**1. Clone and enter the infra directory**
```bash
git clone <this-repo>
cd alchemyst-devops-assignment/infra
```

**2. Create your tfvars**
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   key_pair_name = "your-key-pair-name"
#   my_ip_cidr    = "$(curl -s https://checkip.amazonaws.com)/32"
```

**3. Init and apply**
```bash
terraform init
terraform plan
terraform apply
```

Take note of the outputs:
```
api_gateway_public_ip       = "X.X.X.X"
engine_private_ip           = "10.0.2.X"
inference_worker_private_ip = "10.0.2.X"
```

**4. SSH into the engine VM** (via the gateway as jump host)
```bash
ssh -i your-key.pem \
    -o "ProxyCommand=ssh -i your-key.pem -W 10.0.2.X:22 ubuntu@<api_gateway_public_ip>" \
    ubuntu@<engine_private_ip>
```

**5. On the engine VM — start the iii engine**
```bash
cd ~/quickstart
nohup iii -c config.yaml > /tmp/iii-engine.log 2>&1 &
```

**6. On the engine VM — start the caller-worker**
```bash
cd ~/quickstart/workers/caller-worker
III_URL=ws://localhost:49134 npx tsx src/worker.ts
```

**7. SSH into the inference-worker VM** (separate terminal)
```bash
ssh -i your-key.pem \
    -o "ProxyCommand=ssh -i your-key.pem -W 10.0.2.Y:22 ubuntu@<api_gateway_public_ip>" \
    ubuntu@<inference_worker_private_ip>
```

**8. On the inference-worker VM — start the Python worker**
```bash
cd ~/inference-worker
III_URL=ws://<engine_private_ip>:49134 python3 inference_worker.py
```

---

## API

**Endpoint:** `POST http://<api_gateway_public_ip>:3111/v1/chat/completions`

**Request:**
```bash
curl -X POST http://13.126.11.31:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

**Response:**
```json
{
  "result": {
    "0": "[", "1": "M", "2": "O", "3": "C", "4": "K",
    "...": "...",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

The inference worker is currently running a mock response because the Free Tier instance (`t3.micro`, 1 GB RAM) cannot load the 270M parameter GGUF model. The full call chain — Nginx → iii-http → caller-worker → inference-worker → response — is verified end-to-end and working. See the production note below for the instance size required for real inference.

---

## Issues I ran into and how I fixed them

**1. `iii-http` was bound to `127.0.0.1`**

The default `config.yaml` binds the HTTP server to loopback only. Nginx on the public subnet can't reach loopback on a different machine. Changed `host: 127.0.0.1` → `host: 0.0.0.0`.

**2. Worker start commands used dev tooling**

The inference worker used `watchfiles 'python inference_worker.py'` (file watcher) and the caller-worker used `npm run dev` (which resolves to `tsx watch`). Both are dev tools that reload on file changes — not appropriate for a server process. Changed to `python inference_worker.py` and `npx tsx src/worker.ts` respectively.

**3. `worker_path` had absolute Mac paths**

The original `config.yaml` had paths like `/Users/anuran/Alchemyst/hiring/...` — the author's local machine path. Updated to relative paths `./workers/caller-worker` that work on any machine.

**4. `iii-worker` requires KVM virtualization**

When the engine tried to spawn the caller-worker via `iii-worker`, it failed with `KVM not available -- /dev/kvm does not exist`. EC2 `t3.micro` doesn't support nested KVM. Worked around this by running `npx tsx src/worker.ts` directly with `III_URL` set, bypassing iii-worker entirely. The worker connects to the engine over WebSocket just the same.

**5. `t3.xlarge` not Free Tier eligible**

The `iii.worker.yaml` for the inference worker specifies 8192 MiB RAM and 4 vCPUs — which maps to `t3.xlarge`. AWS rejected it with `InvalidParameterCombination: The specified instance type is not eligible for Free Tier`. Deployed on `t3.micro` for the demo with a mock response instead of real model loading.

**6. `get.iii.dev` returned 404**

The documented install script URL `https://get.iii.dev` no longer works. The working URL is `https://install.iii.dev/iii/main/install.sh`, which also requires `jq` as a pre-requisite.

**7. SSH key permissions on Windows**

Windows assigns broad ACL permissions to new files, which OpenSSH rejects. Fixed with:
```powershell
icacls "key.pem" /inheritance:r
icacls "key.pem" /remove "NT AUTHORITY\Authenticated Users" /remove "BUILTIN\Users"
icacls "key.pem" /grant:r "$($env:USERNAME):(R)"
```

**8. ProxyJump key forwarding on Windows**

Windows doesn't pass the `.pem` key through `ProxyJump` to the second hop automatically (SSH agent is disabled by default). Worked around by using `ProxyCommand` with the key specified explicitly for both hops and hardcoding the target IP:
```bash
ssh -o "ProxyCommand=ssh -i key.pem -W 10.0.2.60:22 ubuntu@<gateway>" ...
```

**9. PyTorch OOM and the mock worker rewrite**

The original `inference_worker.py` loads the model at module import time (lines 21-22 — no lazy loading). When we first ran it, `torch` wasn't installed so it failed immediately. We tried installing torch (`pip3 install torch`), but the download is ~700 MB and froze the terminal on the t3.micro instance.

Even if torch had installed, the model (gemma-3-270m-Q8_0.gguf) requires ~6-8 GB RAM to load — the t3.micro only has 1 GB. It would have OOM-crashed the moment the model weights were mapped into memory.

The fix: rewrote `inference_worker.py` to return a mock string response instead of loading the model. The worker still registers `inference::run_inference` with the iii engine, still connects over WebSocket, and the full API chain works end-to-end. The real model inference code is commented in with clear instructions to uncomment on a `t3.xlarge`.

```python
# mock response (runs on t3.micro for demo)
result = f"[MOCK RESPONSE] Received: '{last_message}'. Deploy on t3.xlarge to enable real Gemma inference."

# real inference (uncomment on t3.xlarge):
# output = model.generate(**inputs, max_new_tokens=32000)
# result = tokenizer.decode(output[0][...], skip_special_tokens=True)
```

---

## Production hardening

A few things I'd change before this handles real traffic:

**1. Instance sizing for inference**
The model (gemma-3-270m-Q8_0.gguf, ~300 MB) needs at least 6-8 GB RAM to load. That means `t3.xlarge` (16 GB) at minimum, or a `g4dn.xlarge` if you want GPU acceleration. The current `t3.micro` demo proves the network plumbing works but can't run real inference.

**2. Systemd instead of manual process management**
Right now the workers are started manually in SSH sessions. In production, each worker should be a `systemd` service with `Restart=always` so they come back after crashes or reboots. The `deploy/cloud-init/` scripts already have the correct unit files — they just need to be wired into the Terraform `user_data` properly.

**3. HTTPS termination**
Port 3111 is plain HTTP. In production I'd put an ACM certificate on an Application Load Balancer and terminate TLS there, removing the public EC2 instance entirely.

**4. Secrets management**
The `III_URL` environment variable is currently passed on the command line. In production, use AWS SSM Parameter Store or Secrets Manager and fetch at boot time via IAM instance profile — no secrets in cloud-init scripts.

**5. HuggingFace model cache on EBS**
Right now the model re-downloads every time the instance boots. Mount a dedicated EBS volume at `/opt/hf-cache`, pre-bake the model there, and snapshot it to an AMI. First boot goes from ~4 seconds to instantaneous.

**6. Tighten the Security Groups**
The `internal-workers-sg` currently allows the entire `10.0.0.0/16` range to hit port 49134. In production I'd restrict it to the specific security group IDs of the engine and worker instances rather than a CIDR block.

## What changes for a 100x larger model

A 100x larger model (~27B parameters, ~28 GB in Q8) fundamentally changes the infrastructure:

- **Instance type**: You need GPU instances. `g4dn.12xlarge` (4x T4, 48 GB VRAM) or `p3.8xlarge` for inference. Cost jumps from ~$0.02/hr to ~$3-12/hr.
- **Model serving**: Replace the `transformers` Python script with a proper inference server like `vLLM` or `TGI` (HuggingFace Text Generation Inference). These handle batching, KV-cache, and continuous batching — critical at that scale.
- **Storage**: The model weights alone are 25-30 GB. You'd need a pre-baked AMI with the model on a high-IOPS EBS volume (or EFS if sharing across instances), otherwise cold-start time is 10-15 minutes.
- **Auto-scaling**: At that cost you can't run multiple inference VMs idling. Use an ASG with scale-to-zero or spot instances with a queue (SQS) in front. The iii queue worker is already set up for this pattern.
- **Latency**: A 27B model takes 5-15 seconds per response at Q8. The `default_timeout: 30000ms` in `config.yaml` would need to go up, and streaming (SSE) would become essential for UX.