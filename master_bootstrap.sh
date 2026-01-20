#!/bin/bash
# ==============================================================================
# MASTER BOOTSTRAP: Odoo 19 Template Builder (Debian 13 Stable)
# Author: [Your Studio Name]
# Description: Generates the specialized deployment scripts for Odoo 19.
# ==============================================================================

set -e
TOOLKIT_DIR="$HOME/odoo-toolkit"
mkdir -p "$TOOLKIT_DIR"
cd "$TOOLKIT_DIR"

# ------------------------------------------------------------------------------
# FILE 1: The "Zero-Touch" Installer
# ------------------------------------------------------------------------------
cat <<'EOF' > 01_install_odoo.sh
#!/bin/bash
set -e
export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "--- 1. Installing System Dependencies ---"
apt update && apt upgrade -y
apt install -y git python3-pip python3-venv python3-dev \
    postgresql-17 postgresql-17-pgvector build-essential \
    libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev \
    libldap2-dev libssl-dev libffi-dev libjpeg-dev \
    libpq-dev node-less xfonts-75dpi xfonts-base fontconfig libxrender1

echo "--- 2. Patching wkhtmltopdf for Debian 13 ---"
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
dpkg -i wkhtmltox_0.12.6.1-3.bookworm_amd64.deb || apt install -f -y
rm wkhtmltox_0.12.6.1-3.bookworm_amd64.deb

echo "--- 3. Configuring PostgreSQL Role ---"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1 || \
sudo -u postgres createuser -s odoo
sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;"

echo "--- 4. Cloning Odoo 19 Source ---"
useradd -m -U -r -d /opt/odoo -s /bin/bash odoo || true
rm -rf /opt/odoo/odoo-server
git clone https://www.github.com/odoo/odoo --depth 1 --branch 19.0 /opt/odoo/odoo-server
chown -R odoo:odoo /opt/odoo

echo "--- 5. Setting up Virtual Environment ---"
sudo -u odoo python3 -m venv /opt/odoo/venv
sudo -u odoo /opt/odoo/venv/bin/pip install --upgrade pip
sudo -u odoo /opt/odoo/venv/bin/pip install -r /opt/odoo/odoo-server/requirements.txt
sudo -u odoo /opt/odoo/venv/bin/pip install psycopg2-binary num2words

echo "--- 6. Creating Systemd Service ---"
cat <<SERVICE | tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo 19
After=postgresql.service
[Service]
Type=simple
User=odoo
Group=odoo
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/odoo-server/odoo-bin -c /etc/odoo.conf
Restart=always
[Install]
WantedBy=multi-user.target
SERVICE

echo "--- 7. Initializing Config & Starting ---"
cat <<CONF | tee /etc/odoo.conf
[options]
admin_passwd = admin
db_user = odoo
proxy_mode = True
addons_path = /opt/odoo/odoo-server/addons
CONF
chown odoo:odoo /etc/odoo.conf
chmod 640 /etc/odoo.conf

systemctl daemon-reload
systemctl enable --now odoo
echo "SUCCESS: Odoo 19 is active at http://$(hostname -I | awk '{print $1}'):8069"
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
