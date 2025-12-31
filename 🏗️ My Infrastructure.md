### 1. ☁️ The Server (Hardware)

- **Provider:** [Hetzner Cloud](https://console.hetzner.cloud/)
- **Location:** Germany (Nuremberg/Falkenstein) — _Low latency for PT._
- **Server Type:** **CX22** (Intel/AMD x86 Architecture).
- **Specs:**
    - **CPU:** 2 vCPU
    - **RAM:** 4 GB
    - **Disk:** 40 GB NVMe
- **Operating System:** Ubuntu 24.04 LTS
- **Cost:** ~€4.35 / month (excl. VAT).
- **IP Address:** _(Check your Hetzner Dashboard)_

### 2. 🛠️ The Management Layer (PaaS)

- **Software:** [Coolify](https://coolify.io/)
- **Function:** Manages Docker containers, Reverse Proxy, and SSL certificates automatically.
- **Installation:** Self-hosted on the Hetzner server ("Localhost").
- **Access Port:** `http://YOUR_IP:8000` (initially) or via your configured domain.

### 3. 🧩 The Software Stack (Applications)

All applications are running as Docker containers managed by Coolify.

### **A. Automation Core (n8n)**

- **Type:** `n8n with PostgreSQL` (Production Grade).
- **Domain:** `https://n8n.n8nauto.win/
- **Database:** PostgreSQL (Internal, dedicated container).
- **Docker Image Tag:** `latest` (Auto-updates on redeploy).

### **B. Vector Database**

- **Software:** [Qdrant](https://qdrant.tech/)
- **Type:** Docker Service.
- **Domain (Dashboard):** `https://qdrant.n8nauto.win/dashboard`
- **Internal Access:** `http://qdrant:6333` (For n8n to talk to it).
- **Collection Name:** `traffic_law`
- **Vector Configuration:**
    - **Dimensions:** `1536` (Compatible with OpenAI `text-embedding-3-small`).
    - **Distance Metric:** `Cosine`.
- **Auth:** Protected by `QDRANT_API_KEY`.

### C. Business Database

- **Software:** PostgreSQL.
- **Type:** Docker Service (Separate from n8n internal DB).
- **Access Configuration:**
    - **Internal (n8n):** Connects via Docker Internal Network (Host: `uuid` or container name from Coolify).
    - **External (DBeaver):** **SSH Tunnel** (Recommended).
        - _Host:_ `HETZNER_IP`
        - _Port:_ `5432`
        - _Via SSH:_ `root@YOUR_HETZNER_IP`
- **Security:** "Ports Mappings" left **Empty** (Not exposed to the public internet).
- **Naming Conventions:**
    - **Format:** `snake_case` (e.g., `first_name`).
    - **Language:** English.
    - **Tables:** Plural (e.g., `users`, `orders`).
    - **Schema:** `public`.

### 4. 🌐 Networking & DNS

- **Provider:** Cloudflare.
- **SSL Mode:** **Full (Strict)**.
- **Records:**
    - `A` Record | `n8n` -> Points to Hetzner IP (Proxied ☁️).
    - `A` Record | `qdrant` -> Points to Hetzner IP (Proxied ☁️).

---

### 🔑 Credentials Backup

1. **Hetzner Root Password** (SSH).
2. **Coolify Login** (Email/Pass).
3. **n8n Owner Account** (Email/Pass).
4. **Qdrant API Key** (From Coolify Env Vars).
5. **OpenRouter API Key**.
6. OpenAI API Key
7. Google AI Studio API Key

---

### 📝 Quick Commands (PowerShell)

- **Connect to Server:** `ssh root@YOUR_IP_ADDRESS`
- **Check Docker Status:** `docker ps`
- **Check Coolify Logs:** `docker logs -f coolify`