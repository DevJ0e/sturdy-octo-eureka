#!/bin/bash
# ==============================================================================
# MASTER BOOTSTRAP: Odoo 19 Template Builder (Debian 13 Stable)
# Author: [Your Studio Name]
# Description: Generates the specialized deployment scripts for Odoo 19.
# ==============================================================================

set -e

# Define the toolkit directory
TOOLKIT_DIR="$HOME/odoo-toolkit"
mkdir -p "$TOOLKIT_DIR"
cd "$TOOLKIT_DIR"

# ------------------------------------------------------------------------------
# FILE 1: Core Installation
# ------------------------------------------------------------------------------
cat <<'EOF' > 01_install_odoo.sh
#!/bin/bash
set -e
echo "--- Installing Odoo 19 Core & Dependencies ---"
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-pip python3-venv python3-dev \
    postgresql-17 postgresql-17-pgvector build-essential \
    libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev \
    libldap2-dev libssl-dev libffi-dev libjpeg-dev \
    libpq-dev libtiff5-dev libopenjp2-7-dev liblcms2-dev \
    libwebp-dev node-less xfonts-75dpi xfonts-base wkhtmltopdf cloud-init

sudo useradd -m -U -r -d /opt/odoo -s /bin/bash odoo || true
sudo -u odoo git clone https://www.github.com/odoo/odoo --depth 1 --branch 19.0 /opt/odoo/odoo-server

cd /opt/odoo
sudo -u odoo python3 -m venv venv
sudo -u odoo ./venv/bin/pip install --upgrade pip
sudo -u odoo ./venv/bin/pip install -r odoo-server/requirements.txt
sudo -u odoo ./venv/bin/pip install psycopg2-binary num2words

# Create Systemd Service
sudo tee /etc/systemd/system/odoo.service > /dev/null <<SERVICE
[Unit]
Description=Odoo 19
After=postgresql.service
[Service]
User=odoo
Group=odoo
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/odoo-server/odoo-bin -c /etc/odoo.conf
[Install]
WantedBy=multi-user.target
SERVICE

# Create Base Config
sudo tee /etc/odoo.conf > /dev/null <<CONF
[options]
admin_passwd = admin
db_user = odoo
proxy_mode = True
addons_path = /opt/odoo/odoo-server/addons
CONF

sudo chown odoo: /etc/odoo.conf
sudo systemctl daemon-reload
sudo systemctl enable --now odoo
EOF

# ------------------------------------------------------------------------------
# FILE 2: Database Configuration (Remote Access)
# ------------------------------------------------------------------------------
cat <<'EOF' > 02_config_database.sh
#!/bin/bash
echo "--- Configuring PostgreSQL 17 for Remote Access ---"
PG_VER=$(psql --version | grep -oE '[0-9]+' | head -1)
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/$PG_VER/main/postgresql.conf
echo "host all all 0.0.0.0/0 scram-sha-256" | sudo tee -a /etc/postgresql/$PG_VER/main/pg_hba.conf
sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;"
sudo systemctl restart postgresql
EOF

# ------------------------------------------------------------------------------
# FILE 3: Template Sanitization
# ------------------------------------------------------------------------------
cat <<'EOF' > 03_prepare_template.sh
#!/bin/bash
echo "--- Sanitizing VM for Proxmox Templating ---"
sudo truncate -s 0 /etc/machine-id
sudo rm /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo rm -f /etc/ssh/ssh_host_*
sudo apt-get clean
sudo history -c
echo "SUCCESS: System is clean. Shutdown and convert to template in Proxmox."
EOF

# Set Permissions
chmod +x *.sh

echo "========================================================"
echo "TOOLKIT GENERATED SUCCESSFULLY"
echo "Location: $TOOLKIT_DIR"
echo "Order: Run 01, then 02, then 03."
echo "========================================================"
