#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONF_DIR="$SCRIPT_DIR/apache_conf"
LOG_DIR="/var/log/asterisk"
ASTERISK_CONF_FILE="/etc/asterisk/extensions_custom.conf"
USER="asterisk"
GROUP="asterisk"

# Logs to create
LOG_FILES=(
    "api_calls.log"
    "click2call.log"
    "agents_status.log"
    "api_keys_management.log"
    "api_debug.log"
)

# --- OS Detection ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    ID_LIKE=$ID_LIKE
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
else
    OS=$(uname -s)
fi

echo "Detected OS: $OS"

# --- Pre-checks ---
echo "--- Running Pre-checks ---"

if ! command -v asterisk >/dev/null 2>&1; then
    echo "WARNING: Asterisk command-line tool not found. Is Asterisk installed?"
fi

if ! systemctl is-active --quiet asterisk; then
    echo "WARNING: Asterisk service is not running."
fi

if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
    echo "WARNING: Database service (MariaDB/MySQL) is not running."
fi

# --- 1. Binary Installation ---
echo "--- Installing Compiled Python Binary ---"

# Detect binary to install based on OS
if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* || "$ID" == "ubuntu" ]]; then
    BINARY_SOURCE="$SCRIPT_DIR/bin/debian/app.bin"
elif [[ "$ID" == "centos" || "$ID_LIKE" == *"rhel"* || "$ID" == "fedora" || "$ID_LIKE" == *"centos"* ]]; then
    BINARY_SOURCE="$SCRIPT_DIR/bin/centos/app.bin"
else
    # Fallback based on package manager
    if command -v apt-get >/dev/null 2>&1; then
        BINARY_SOURCE="$SCRIPT_DIR/bin/debian/app.bin"
    else
        BINARY_SOURCE="$SCRIPT_DIR/bin/centos/app.bin"
    fi
fi

if [ ! -f "$BINARY_SOURCE" ]; then
    echo "ERROR: Compiled binary not found at $BINARY_SOURCE"
    exit 1
fi

echo "Installing binary from $BINARY_SOURCE to /usr/local/bin/click2call-api..."
cp -f "$BINARY_SOURCE" "/usr/local/bin/click2call-api"
chown "$USER:$GROUP" "/usr/local/bin/click2call-api"
chmod 755 "/usr/local/bin/click2call-api"

# --- 1.5 Deprecated PHP Code Cleanup ---
echo "--- Cleaning Up Deprecated PHP Code ---"
if [ -d "/var/www/html/api" ]; then
    echo "Backing up old API files to /tmp/api_backup_$(date +%F).tar.gz..."
    tar -czf "/tmp/api_backup_$(date +%F).tar.gz" -C "/var/www/html" api 2>/dev/null || true
    echo "Cleaning up old PHP API files under /var/www/html/api..."
    find "/var/www/html/api" -type f -name "*.php" -delete
    rm -rf "/var/www/html/api/src" "/var/www/html/api/vendor" "/var/www/html/api/scripts"
else
    mkdir -p "/var/www/html/api"
fi
chown -R "$USER:$GROUP" "/var/www/html/api"
chmod 755 "/var/www/html/api"

if [ -d "/var/www/html/rest" ]; then
    echo "Removing deprecated rest directory..."
    rm -rf "/var/www/html/rest"
fi

# --- 2. Log Files ---
echo "--- Configuring Logs ---"

if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chown "$USER:$GROUP" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
fi

for logfile in "${LOG_FILES[@]}"; do
    FULL_PATH="$LOG_DIR/$logfile"
    if [ ! -f "$FULL_PATH" ]; then
        echo "Creating log file: $FULL_PATH"
        touch "$FULL_PATH"
    fi
    chown "$USER:$GROUP" "$FULL_PATH"
    chmod 660 "$FULL_PATH"
done

# --- 3. Asterisk Dialplan Configuration ---
echo "--- Configuring Asterisk Dialplan ---"

if [ -f "$ASTERISK_CONF_FILE" ]; then
    if grep -q "\[click2call-bypass\]" "$ASTERISK_CONF_FILE"; then
        echo "Context [click2call-bypass] already exists in $ASTERISK_CONF_FILE. Skipping."
    else
        echo "Appending [click2call-bypass] context to $ASTERISK_CONF_FILE..."

        # Using quoted 'EOL' to prevent variable expansion in bash
        cat >> "$ASTERISK_CONF_FILE" <<'EOL'

[click2call-bypass]
; Custom context that bypasses FreePBX CallerID security
exten => _X.,1,NoOp(=== Click2Call Bypass Context ===)
 same => n,NoOp(CALLERID(num): ${CALLERID(num)})
 same => n,NoOp(REALCALLERIDNUM: ${REALCALLERIDNUM})

 ; Save agent extension for billing (use standard CDR field)
 same => n,GotoIf($["${CALLERID(num)}" = ""]?use_api_cid)
 same => n,Set(CHANNEL(accountcode)=${CALLERID(num)})
 same => n,Set(__AGENT_EXTENSION=${CALLERID(num)})

 same => n(use_api_cid),GotoIf($["${REALCALLERIDNUM}" = ""]?use_default)

 ; Set TRUNKCIDOVERRIDE to the API Key CID (for the trunk)
 same => n,Set(TRUNKCIDOVERRIDE=${REALCALLERIDNUM})
 same => n,Set(CALLERID(name)=Click2Call)
 same => n,Set(__API_CALLER_ID=${REALCALLERIDNUM})
 same => n,NoOp(Using API CallerID for Trunk: ${REALCALLERIDNUM})

 ; PREPEND the API CallerID to the destination number for prefix-based routing
 same => n,Goto(from-internal,${REALCALLERIDNUM}${EXTEN},1)

 same => n(use_default),NoOp(No custom CallerID, using extension)
 same => n,Goto(from-internal,${EXTEN},1)

[macro-dialout-trunk-predial-hook]
exten => s,1,NoOp(=== Click2Call CDR Fix ===)
; If this is an API call (REALCALLERIDNUM is set), force CDR destination to be the stripped number (OUTNUM)
same => n,ExecIf($["${REALCALLERIDNUM}" != ""]?Set(CDR(dst)=${OUTNUM}))
same => n,MacroExit()
EOL

        echo "Reloading Asterisk Dialplan..."
        asterisk -rx "dialplan reload"
    fi
else
    echo "WARNING: $ASTERISK_CONF_FILE not found. Could not add dialplan context."
fi

# --- 3.5 Dynamic Port Selection ---
echo "--- Finding Free API Port ---"
is_port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tulnp | grep -q ":$port "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulnp | grep -q ":$port "
    else
        # Fallback check via bash
        (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1
    fi
}

API_PORT=8000
while is_port_in_use "$API_PORT"; do
    echo "Port $API_PORT is in use, checking next port..."
    API_PORT=$((API_PORT + 1))
done
echo "Selected API Port: $API_PORT"

# --- 4. Apache Configuration ---
echo "--- Configuring Apache ---"

if [ ! -d "$SOURCE_CONF_DIR" ]; then
     echo "WARNING: Local Apache configuration folder '$SOURCE_CONF_DIR' not found."
     echo "Skipping Apache configuration copy."
else
    if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* || "$ID" == "ubuntu" ]]; then
        # === DEBIAN / UBUNTU ===
        APACHE_CONF_DIR="/etc/apache2/conf-available"

        echo "Copying configs to $APACHE_CONF_DIR..."
        cp "$SOURCE_CONF_DIR/click2call.conf" "$APACHE_CONF_DIR/"

        echo "Configuring reverse proxy port to $API_PORT..."
        sed -i "s/8000/$API_PORT/g" "$APACHE_CONF_DIR/click2call.conf"

        echo "Enabling configurations..."
        a2enconf click2call

        echo "Enabling modules..."
        a2enmod proxy
        a2enmod proxy_http
        a2enmod headers

        echo "Testing configuration..."
        apache2ctl configtest

        echo "Restarting Apache..."
        systemctl restart apache2
        systemctl status apache2 --no-pager

    elif [[ "$ID" == "centos" || "$ID_LIKE" == *"rhel"* || "$ID" == "fedora" || "$ID_LIKE" == *"centos"* ]]; then
        # === CENTOS / RHEL ===
        APACHE_CONF_DIR="/etc/httpd/conf.d"

        echo "Copying configs to $APACHE_CONF_DIR..."
        cp "$SOURCE_CONF_DIR/click2call.conf" "$APACHE_CONF_DIR/"

        echo "Configuring reverse proxy port to $API_PORT..."
        sed -i "s/8000/$API_PORT/g" "$APACHE_CONF_DIR/click2call.conf"

        echo "Adjusting Apache log paths for CentOS/RHEL..."
        sed -i \
            -e 's#^\s*ErrorLog\s\+.*#ErrorLog /var/log/httpd/click2call_error.log#' \
            -e 's#^\s*CustomLog\s\+.*#CustomLog /var/log/httpd/click2call_access.log combined#' \
            "$APACHE_CONF_DIR/click2call.conf"

        # Ensure permissions on configs
        chown "root:root" "$APACHE_CONF_DIR/click2call.conf"
        chmod 644 "$APACHE_CONF_DIR/click2call.conf"

        echo "Testing configuration..."
        httpd -t

        echo "Restarting Apache (httpd)..."
        systemctl restart httpd
        systemctl status httpd --no-pager

    else
        echo "Unsupported OS family ($ID). Please configure Apache manually."
    fi
fi

# --- 5. Database Initialization ---
echo "--- Initializing Database Schema ---"
if [ -f "/usr/local/bin/click2call-api" ]; then
    /usr/local/bin/click2call-api --keys --list-keys > /dev/null 2>&1
    echo "✓ Database schema verified."
else
    echo "WARNING: Could not find click2call-api binary to initialize database."
fi

# --- 6. License Configuration ---
echo "--- Configuring License ---"
LICENSE_FILE="/etc/click2call_license"

if [ -t 0 ]; then
    # Interactive mode
    if [ -f "$LICENSE_FILE" ]; then
        echo "Existing license key found."
        read -sp "Enter new License Key (press Enter to keep current): " NEW_KEY
        echo ""
        if [ -n "$NEW_KEY" ]; then
            printf "%s\n" "$NEW_KEY" > "$LICENSE_FILE"
        fi
    else
        read -sp "Enter your Click2Call License Key (leave empty for DEVELOPMENT-KEY): " LICENSE_KEY
        echo ""
        if [ -z "$LICENSE_KEY" ]; then
            LICENSE_KEY="DEVELOPMENT-KEY"
            echo "WARNING: No license key provided. Using DEVELOPMENT-KEY."
        fi
        printf "%s\n" "$LICENSE_KEY" > "$LICENSE_FILE"
    fi
else
    # Non-interactive mode
    if [ -n "$LICENSE_KEY" ]; then
        printf "%s\n" "$LICENSE_KEY" > "$LICENSE_FILE"
        echo "License key set from environment variable."
    elif [ -f "$LICENSE_FILE" ]; then
        echo "Existing license key found. Keeping it in non-interactive mode."
    else
        LICENSE_KEY="DEVELOPMENT-KEY"
        printf "%s\n" "$LICENSE_KEY" > "$LICENSE_FILE"
        echo "WARNING: Non-interactive mode and no LICENSE_KEY env var. Using DEVELOPMENT-KEY."
    fi
fi

# Set permissions
chown "root:$GROUP" "$LICENSE_FILE"
chmod 640 "$LICENSE_FILE"
echo "✓ License configuration processed."

# --- 7. Systemd Service ---
echo "--- Configuring Systemd Service for Click2Call Python API ---"

# Stop and disable old PHP service if it exists
if systemctl is-active --quiet click2call-agent-status; then
    echo "Stopping old click2call-agent-status service..."
    systemctl stop click2call-agent-status
fi
if systemctl is-enabled --quiet click2call-agent-status; then
    echo "Disabling old click2call-agent-status service..."
    systemctl disable click2call-agent-status
fi
if [ -f "/etc/systemd/system/click2call-agent-status.service" ]; then
    rm -f "/etc/systemd/system/click2call-agent-status.service"
fi

# Create new Python API service
SERVICE_FILE="/etc/systemd/system/click2call.service"
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Click2Call Python API Service
After=network.target asterisk.service mariadb.service mysql.service

[Service]
Type=simple
User=asterisk
Group=asterisk
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/click2call-api --port $API_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

echo "Enabling and starting click2call service..."
systemctl daemon-reload
systemctl enable click2call
systemctl restart click2call
systemctl status click2call --no-pager
echo "✓ Click2Call service configured."

echo "--- Installation Complete ---"
