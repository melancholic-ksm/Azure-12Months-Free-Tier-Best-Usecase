# Azure Free Tier 12-Month Plan with Cloudflare + Backblaze CDN

## 🎯 Goal

Keep **3 Linux VMs** powered on continuously for 12 months under Azure Free Tier (12 months + Always Free services), with minimal extra charges (\~\$1–8/month), while using **Cloudflare + Backblaze B2** for CDN and asset offloading to reduce outbound data egress costs.

---

## 🖥️ VM Specifications

### VM1 – B1s 

- **Name:** sprt-vm
- **Size:** B1s (1 vCPU, 1 GiB RAM)
- **Architecture:** AMD x64 (Intel/AMD CPU)
- **OS Image:** Ubuntu 24.04-LTS Gen2
- **Hyper-V Generation:** Gen2
- **URN:** Canonical\:ubuntu-24\_04-lts\:server\:latest
- **OS Disk:** 64 GB **P6 Standard SSD** (free tier)
- **Networking:** Private VNet + NIC, **Dynamic Basic IPv4 Public IP (free)**
- **Purpose:** Lightweight workloads, testing, or API/microservice



---

### **VM2 – B2ats\_v2**

- **Name:** mgmt-vm
- **Size:** B2ats v2 (2 vCPUs, 1 GiB RAM)
- **Architecture:** AMD x64 (Intel/AMD CPU)
- **OS Image:** Ubuntu 24.04-LTS Gen2
- **Hyper-V Generation:** Gen2
- **URN:** Canonical\:ubuntu-24\_04-lts\:server\:latest
- **OS Disk:** 64 GB **P6 Standard SSD** (free tier)
- **Networking:** Private VNet + NIC, **Dynamic Basic IPv4 Public IP (free)**
- **Purpose:** Medium workloads, main web service handling

---

### **VM3 – B2pts\_v2**

- **Name:** powr-vm
- **Size:** B2pts v2 (2 vCPUs, 1 GiB RAM, Premium SSD capable)
- **Architecture:** AMD x64 (Intel/AMD CPU)
- **OS Image:** Ubuntu 24.04-LTS Gen2
- **Hyper-V Generation:** Gen264\:latest
- **URN:** Canonical\:ubuntu-24\_04-lts\:server-arm64\:latest
- **OS Disk:** 32 GB **Standard HDD S4** (lowest cost, \~\$1.5–\$2/month)
- **Networking:** Same VNet + NIC, **Dynamic Basic IPv4 Public IP (free)**
- **Purpose:** Additional services, background jobs, scaling capacity

---

## 🌐 Networking Setup

- **No Load Balancer used**
  - Only mgmt-vm have Static (SKU: Standard) Public IP to connect to VM. 
  - ##### **Cost: $0.005/hour**
 - Only mgmt-vm will have a public IP (mgmt-pip).
 - sprt-vm and powr-vm are private-only).
 - To connect sprt-vm and powr-vm you will connect to mgmt-vm first and from inside mgmt-vm you will connect to _**sprt/powr**_ vm accordingly.
 - Outbound egress minimized by caching/static asset delivery via Cloudflare + Backblaze B2.

---

## 📦 Storage Plan

- **OS Disks:**
  - VM1 → 64 GB P6 SSD (free)
  - VM2 → 64 GB P6 SSD (free)
  - VM3 → 32 GB S4 HDD (paid)
- **No Data Disks** attached
- **Assets, HTML, videos, illustrations** → stored in **Backblaze B2 bucket**, fronted by **Cloudflare CDN** (zero egress fees)

---

## 🐧 OS & Config

- **Standardized OS:** Ubuntu 24.04-LTS Gen2 on all VMs
- **URN for B2ats v2** _mgmt-vm_ **and B1s** _sprt-vm_: `Canonical\:ubuntu-24\_04-lts\:server\:latest`^
- **URN for B2pts v2** _powr-vm_: `Canonical:ubuntu-24_04-lts:server-arm64:latest`^
- **Boot Diagnostics:** Enabled (stored in free tier Storage Account)
- **Updates:** Automatic security patching enabled

 ###### ^: Recheck before proceeding, if you want different one to use according to your requirements
---

## 💰 Cost Summary

- **VM Usage:** Free (B1s + B2ats\_v2 + B2pts\_v2 CPU/RAM covered by free tier)
- **OS Disks:** 2 × free P6 SSDs, 1 × paid S4 HDD (\~\$1.5–\$2/mo)
- **Public IPs:** One Standard SKU Static PIP (\~\$3.66/mo)(\~\$0.005/mo)
- **Outbound Egress:** Minimized via Cloudflare + Backblaze B2 (0 fees for cached assets)
- **Estimated Total:** \~\$1.5–\$2 per month → \~\$18–\$24 per year
                       \~\$3.66 per month →  \~\$42-\$45 per year
---

✅ With this updated plan, all 3 VMs stay online for 12 months, OS disks assigned properly (2 free SSDs + 1 minimal HDD), and CDN offloading keeps egress charges near zero. 
 Using Cloudflare Tunnel we can avoid \$45 per year charged due to Public IP.
  (When Site is in ready state)

  Further to avoid \$2/mo \/\/\ $24/year, choose anyone VM from **B2pts-v2**`(powr-vm)` {ARM based}  or **B1s** `(sprt-vm)` {AMD based} according to your need.
---



##

