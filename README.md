<p align="center">
  <img src="docs/Logo/Logo%20Badge.png" width="150" alt="Logo Badge">
</p>

# Click2Call API for FreePBX: Commercial Click-to-Call REST API compatible with FreePBX.

Empower your CRM, web portal, or custom application with seamless Click2Call functionality. This enterprise-grade REST API is designed to originate calls on any version of FreePBX, providing a robust bridge between your business software and your telephony infrastructure.

<p align="center">
  <img src="docs/Logo/Cover.png" alt="Cover" />
</p>

> **Disclaimer**
>
> Click2Call for FreePBX is an independent commercial product developed by Nonikoff.
> It is **not affiliated with, endorsed by, or supported by Sangoma Technologies or the FreePBX project.**

## 🚀 Key Features

- **Universal Click2Call**: Trigger calls between agent extensions and any destination with a single HTTP POST request.
- **Real-time Agent Status**: Monitor agent availability via PJSIP endpoint states directly from your application.
- **Enterprise-Grade Security**: Secure API Key authentication managed directly from the PBX shell.
- **Advanced Trunk Routing**: Supports complex outbound routing needs via service prefixes and granular CallerID overrides.
- **Intelligent Number Sanitization**: Automatically cleans destination numbers (removes non-digits and leading zeros) for maximum carrier compatibility.
- **Built for Scale**: High-performance native Asterisk Manager Interface (AMI) integration.
- **Lightweight Deployment**: Zero external database dependencies; runs natively within your FreePBX environment.

## 📦 How to Install (3-Minute Setup)

1. **Clone**: Clone this repository to your FreePBX server:
   ```bash
   git clone https://github.com/Nonikoff/Click2Call-for-FreePBX.git
   cd Click2Call-for-FreePBX
   ```
2. **Install**: Run the automated installer:
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```
3. **Authorize**: Generate your first API key using the CLI tool (see below).

## ⚙️ How It Works (Performance & Scale)

Unlike other solutions, Click2Call is designed for high-performance environments. It uses a decoupled monitoring architecture:

1.  **Background Worker**: A dedicated service polls the Asterisk Manager Interface (AMI) every 2 seconds for real-time PJSIP device states.
2.  **Database Caching**: Statuses are normalized and stored in a high-speed MariaDB cache, ensuring API responses are sub-millisecond and never put load on your telephony engine.
3.  **Real-time Correlation**: The API automatically correlates live device states with your **FreePBX User Manager** database, providing a seamless link between extensions and agent identities (emails/usernames).

### Agent Status Definitions
| Status | Meaning |
| :--- | :--- |
| `available` | Extension is online and ready to take a call. |
| `busy` | Extension is currently on a call, busy, or ringing. |
| `unavailable` | Extension is offline, unregistered, or unreachable. |

## 🔒 Security, Privacy & Threat Model

We recognize that PBX systems operate at the heart of an organization's communications infrastructure. Click2Call for FreePBX (`click2call-api`) is architected from the ground up with strict data boundaries, unprivileged runtime execution, and full network transparency. Below is an exhaustive breakdown of our system security, privacy guarantees, and threat mitigations.

### Security & Network Behavior

The application maintains strict boundaries around local file access and external network communications:

#### 1. Local Filesystem Access
- **`/etc/freepbx.conf` (Read-Only)**: Accessed strictly during service initialization to parse FreePBX database connection parameters (`$amp_conf['AMPDBUSER']`, `$amp_conf['AMPDBPASS']`) and AMI credentials (`$amp_conf['AMPMGRUSER']`, `$amp_conf['AMPMGRPASS']`). The daemon never modifies or writes to this configuration file.
- **`/var/log/asterisk/click2call*.log` (Append-Only)**: The daemon opens execution and audit logs (`click2call.log`, `agents_status.log`, `api_keys_management.log`, `api_calls.log`) with append-only permissions under `asterisk:asterisk` ownership to record diagnostic metrics without altering existing system logs.
- **`asterisk.api_keys` (MariaDB Table Scoped Access)**: Database interactions are strictly restricted to reading and writing our dedicated `api_keys` table inside the local `asterisk` database. The daemon does **not** query, access, or modify any other tables (such as CDRs, extensions, voicemail, or user credentials).

#### 2. Outbound Network Connections (Strictly Two Endpoints)
The `click2call-api` daemon operates entirely inside your local network boundary and makes **only two outbound HTTPS connections**, both dedicated exclusively to software licensing:
1. **`https://api.ipify.org`**:
   - **Purpose**: Retrieves the PBX server's public IPv4 address required for zero-configuration license binding during startup and scheduled check-ins.
   - **Privacy Guarantee**: Issues a standard, anonymous `GET` request. No telemetry, system metadata, or tracking headers are transmitted.
2. **`https://license.nonikoff.com`**:
   - **Purpose**: Validates the active software license and retrieves a cryptographic RS256-signed JSON Web Token (JWT) generated by our serverless Cloudflare Worker backend.
   - **Frequency**: Checked exactly **once every 24 hours** (or upon local cache expiration or manual key creation).

#### 3. Absolute Privacy Guarantee
We explicitly guarantee that **no telephony data, customer records, or internal configurations are ever transmitted outside your server**. Specifically, our software **NEVER** collects, stores, or transmits:
- ❌ Call recordings or customer audio/RTP streams
- ❌ Contact lists, phonebooks, or customer phone numbers
- ❌ Call Detail Records (CDRs) or call history logs
- ❌ PBX extension lists or User Manager directories
- ❌ System passwords, SSH keys, or Asterisk Manager Interface (AMI) credentials

### Binary Architecture & Why Nuitka

#### What is `click2call-api`?
`click2call-api` is a high-performance, asynchronous Python application built with FastAPI and compiled using **Nuitka** into a standalone, natively executable binary file (`/usr/local/bin/click2call-api`).

#### Why do we compile our application?
1. **Dependency Isolation & Environment Stability**: FreePBX installations span diverse operating systems (Debian, Ubuntu, CentOS 7, RHEL, and Rocky Linux) across multiple FreePBX versions (15, 16, and 17). Each OS ships with different system Python versions and shared library constraints. Compiling our application with Nuitka bundles our exact, tested Python runtime and dependencies (FastAPI, Uvicorn, PyJWT, PyMySQL) into a single, self-contained binary. This completely eliminates dependency conflicts, virtual environment corruption, and `pip` upgrade failures that could destabilize your PBX environment.
2. **Intellectual Property Protection**: As commercial enterprise software, compilation safeguards our proprietary business logic, multi-level routing engines, and RS256 licensing verification algorithms from unauthorized distribution and tampering.
3. **Security Assurance**: Compilation is used **strictly for system stability and commercial IP protection**—never for code obfuscation, covert telemetry, or malicious activities.

#### Multi-Distribution Support
We provide functionally identical, rigorously tested standalone binaries specifically compiled for both **Debian/Ubuntu** (`apt`-based systems) and **CentOS/RHEL/Rocky Linux** (`yum`/`dnf`-based systems).

### Licensing Resilience & Fail-Open Behavior

To ensure that commercial licensing checks never interfere with your mission-critical telephony operations, we implement a resilient, fault-tolerant verification architecture:

- **Verification Frequency**: The system connects to `https://license.nonikoff.com` **once every 24 hours** to verify license validity.
- **Cryptographic Local Caching**: Upon successful validation, the server returns an **RS256-signed JSON Web Token (JWT)**, which is securely cached inside the local `asterisk.api_keys` table.
- **Fail-Open Operational Guarantee**:
  - **What happens if `https://license.nonikoff.com` or Cloudflare is offline?**
  - If the external licensing server is temporarily unreachable due to network outages, DNS routing issues, firewall restrictions, or upstream maintenance, the application immediately falls back to validating its **local tamper-proof RS256 cache**.
  - As long as a valid cached JWT exists on the server, **normal call origination (`click2call`), agent status queries (`agents_status`), and API responses continue without interruption**. Your telephony workflows remain 100% operational during external network disruptions.

### Network Auditing & Verification

We invite and encourage system administrators, security teams, and network auditors to independently verify our network behavior and strict boundary enforcement using standard enterprise network analysis tools such as `tcpdump`, `Wireshark`, `iptables` logging, `pfSense`, or `OPNsense`.

#### Live `tcpdump` Verification Snippet
You can verify in real time that the `click2call-api` binary communicates exclusively with `api.ipify.org` and `license.nonikoff.com` by running the following command from your PBX root shell:

```bash
# Monitor all outbound HTTPS (Port 443) traffic originating from the PBX host
sudo tcpdump -i any -n -v "tcp port 443 and (dst host api.ipify.org or dst host license.nonikoff.com)"
```

To confirm that **no hidden connections or unexpected data transfers** occur, you can capture all outbound HTTPS traffic and verify that no other IP addresses or destinations are contacted by the service:

```bash
# Verify zero unexpected external outbound connections
sudo tcpdump -i any -n 'tcp dst port 443' | grep -vE "local_network_prefix|dns_servers"
```

### Runtime Permissions & System Footprint

The system conforms to principle-of-least-privilege engineering standards:

- **Service Daemon Name**: `click2call.service` (systemd unit managed via `systemctl`).
- **Unprivileged Runtime Execution**: The daemon runs strictly under the unprivileged `asterisk` system user and group (`User=asterisk`, `Group=asterisk`). It possesses zero root privileges during operational runtime.
- **Root (`sudo`) Requirement**: Root access (`sudo`) is required **only once during execution of `./install.sh`** to perform initial setup tasks: placing the executable in `/usr/local/bin`, installing Apache reverse proxy configuration files in `/etc/httpd/conf.d/` (CentOS/RHEL) or `/etc/apache2/sites-available/` (Debian/Ubuntu), and enabling the systemctl service. Once installation completes, root privileges are never requested or utilized again.
- **Network Ports Opened**: The daemon binds strictly to loopback (`127.0.0.1:8000` or the first dynamically allocated free port starting at `8000`). **No external unauthenticated network ports are opened directly to the public internet**. All incoming requests pass through your existing Apache web server, where `mod_proxy` rules validate clean URLs and route traffic locally.
- **Log Locations**: All logs are restricted to `/var/log/asterisk/click2call*.log` and owned by `asterisk:asterisk`.

### Threat Model & Data Boundary Table

The following table summarizes our exact data boundaries, distinguishing data retained strictly within your local PBX from the minimal licensing metadata transmitted off-server:

| Data Category | Storage / Execution Location | Transmitted Off-Server? | Purpose / Protection Guarantee |
| :--- | :--- | :--- | :--- |
| **API Keys & Secrets** | Local (`asterisk.api_keys` MariaDB table) | ❌ **No** | Stored locally and checked in-memory to authenticate REST API requests. |
| **AMI Credentials** | Local (`/etc/freepbx.conf` read-only) | ❌ **No** | Read locally during startup to establish loopback connection to Asterisk (`127.0.0.1:5038`). |
| **Call Detail Records (CDRs)** | Local (`asterisk.cdr` / FreePBX database) | ❌ **No** | Generated and managed natively by FreePBX/Asterisk. Never accessed by our API. |
| **Phone Numbers & Extensions** | Local (In-memory during AMI command) | ❌ **No** | Used strictly to send local `Originate` and `ExtensionState` commands to Asterisk. |
| **Customer Audio & Media** | Local (RTP streams handled by Asterisk) | ❌ **No** | Media flows directly between Asterisk and endpoints; our daemon only triggers signaling. |
| **Application & Audit Logs** | Local (`/var/log/asterisk/*.log`) | ❌ **No** | Maintained locally for system troubleshooting and administrator auditing. |
| **PBX Public IP Address** | In-memory during check (`api.ipify.org`) | ✅ **Yes** (Strictly IP only) | Queried via `https://api.ipify.org` to bind zero-configuration license to server instance. |
| **License Check Request** | Sent to `https://license.nonikoff.com` | ✅ **Yes** (Metadata + IP) | Transmits server public IP and license key over TLS to verify active RS256 license signature. |
| **RS256 Signed License JWT** | Local (`asterisk.api_keys` cache) | ❌ **No** | Cached locally to guarantee offline fail-open execution for 24+ hours if cloud check fails. |

### Why Commercial & Closed Source?

Click2Call for FreePBX is a commercial enterprise software suite. Open-source PBX integration scripts often suffer from unmaintained dependencies, security vulnerabilities, or breaking changes across major FreePBX platform upgrades (such as migrating from PHP 7.4 on FreePBX 15 to PHP 8.2 on FreePBX 17).

Our commercial model ensures continuous compatibility maintenance, automated CI/CD testing across Linux distributions, and dedicated engineering support. While source distribution is restricted and compiled with Nuitka to protect our commercial intellectual property and licensing architecture, we provide **complete behavioral and network transparency**:
- Every network request can be independently audited via `tcpdump`.
- Every local file and database interaction is strictly bounded and documented.
- The runtime operates unprivileged under the `asterisk` system account.

### Firewall Requirements
**IMPORTANT**: Your CRM/Application server IP address **MUST** be whitelisted in the FreePBX Firewall (Connectivity -> Firewall -> Networks) to allow HTTP traffic to the API endpoints.

### Authentication
Security is handled via unique **API Keys**. We do not use external tokens, ensuring your credentials never leave your private PBX environment.

## 🛠 HTTP API Reference

### Click2Call
Initiate a call between an agent and a destination.
- **Endpoint**: `POST /api/v1/{api_key}/click2call`
- **Parameters**: `agent` (required), `number` (required), `sync` (optional boolean, default `false`)
- **Example**:
  ```bash
  curl -X POST "https://your-pbx/api/v1/MY-SECURE-KEY/click2call?agent=101&number=5550123&sync=true"
  ```
- **Example Response**:
  ```json
  {
    "call_id": "848a605f-7bc3-c3f2-1a4d-b9e123456789",
    "caller_id": "101",
    "extension": "101",
    "destination": "5550123",
    "sync": true,
    "status": "Success"
  }
  ```

### Agent Status
Monitor real-time agent availability.
- **Endpoint**: `GET /api/v1/{api_key}/agents_status`
- **Example Response**:
  ```json
  [
    { "ext": "101", "status": "available" }
  ]
  ```

### Error Responses
| Status | Error Message | Solution |
| :--- | :--- | :--- |
| **400** | `Invalid destination number` | Ensure number contains only 0-9, +, or spaces. |
| **400** | `Agent logged off` | No active PJSIP endpoints detected for this extension. |
| **403** | `Invalid API key` | Verify the key exists using the CLI management tool. |
| **500** | `AMI authentication failed` | Check Asterisk Manager credentials in FreePBX. |

## ⌨️ CLI Management Tool

Manage your integrations securely from the PBX shell using `/usr/local/bin/click2call-api`.

### Key Management (`--keys`)
| Command | Description |
| :--- | :--- |
| `--keys --create-key` | Interactively create a new key and assign a routing CallerID. |
| `--keys --list-keys` | Display all active keys, logins, and associated CallerIDs. |
| `--keys --get-key` | Get details of a specific key. |
| `--keys --update-caller-id` | Change the routing prefix/CallerID for an existing key. |
| `--keys --reset-key` | Reset a key's secret or value. |
| `--keys --enable-key` | Enable an API key. |
| `--keys --disable-key` | Disable an API key. |
| `--keys --delete-key` | Instantly revoke access for a specific integration. |

### Presence Management (`--presence`)
| Command | Description |
| :--- | :--- |
| `--presence --action {query,set}` | Query or set a device state. |
| `--presence --device DEVICE` | Asterisk device name (e.g., PJSIP/101). |
| `--presence --state STATE` | State to set (e.g., available, busy, offline). |
| `--presence --message MESSAGE` | Optional description message for status. |

**Example**:
```bash
/usr/local/bin/click2call-api --keys --list-keys
```

## 🛣️ Advanced Trunk Routing

Click2Call gives you absolute control over which trunk is used for an API call.

### Scenario 1: Multi-Provider (Prefix Based)
You can force different CRM departments to use different trunks by assigning unique CallerIDs (prefixes) to their API Keys.
1. Assign a prefix (e.g., `8001`) to an API Key via CLI.
2. In FreePBX **Outbound Routes**, create a route with:
   - **Prefix**: `8001`
   - **Trunk**: Your specific Provider Trunk.
3. The API automatically prepends this prefix to the destination number.

### Scenario 2: Single Provider
Simply leave the API Key CallerID empty or set it to your main outbound number. The call will follow your default FreePBX outbound rules.

## 📊 Professional Logging

Monitor your system in real-time using standard Linux tools:

- **API Traffic**: `tail -f /var/log/asterisk/click2call.log`
- **Presence Data**: `tail -f /var/log/asterisk/agents_status.log`
- **Security Audit**: `grep "ERROR" /var/log/asterisk/api_keys_management.log`

## 🔐 Licensing & Pricing

FreePBX Click2Call is a commercial product. Our system automatically secures your installation based on your server's public IP (`https://license.nonikoff.com`).

### Pricing
- **🎁 15-Day Free Trial**: **$0** (Immediate activation via Telegram bot, locked to 1 trial per server IP)
- **6-Month License**: **120 USDT** (TRC20 / ERC20)
- **1-Year License**: **200 USDT** (TRC20 / ERC20)
- **Extensions**: **Unlimited** (no per-user or per-agent fees)

**To activate your 15-day free trial or purchase a license, launch our automated Telegram bot:**
👉 **[@lic_c2c_pay_bot](https://t.me/lic_c2c_pay_bot)**

For other inquiries, enterprise support, or custom integrations:
👉 **alex@nonikoff.com**

FreePBX is a trademark of Sangoma Technologies.
This project is an independent product and is not affiliated with or endorsed by Sangoma.

---
*Developed for professionals who demand reliable FreePBX integrations.*
