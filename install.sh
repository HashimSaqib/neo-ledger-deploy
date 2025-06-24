#!/bin/bash
# Temp/tmp directories, permissions
# neoledger installation script for Debian-based systems
# This script installs and configures the neoledger application
# (both backend and frontend components)

set -e  # Exit on error

# Function to display error messages
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to display status messages
echo_status() {
    echo "===> $1"
}

# Detect OS
echo_status "Detecting operating system..."
if [ -f /etc/debian_version ]; then
    echo_status "Detected Debian-based system"
else
    error_exit "Unsupported operating system. This script supports Debian-based systems only."
fi

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

# Check for setup.env file
if [ ! -f "setup.env" ]; then
    echo_status "Creating setup.env template file..."
    cat > setup.env << EOF
# NeoLedger Configuration
# Please update these values before running the installation script

# Frontend URL (e.g., neoledger.example.com)
FRONTEND_URL=

# Backend URL (e.g., api.neoledger.example.com)
BACKEND_URL=

# Admin Email
ADMIN_EMAIL=

# Admin Password
ADMIN_PW=

# PostgreSQL User
POSTGRES_USER=

# PostgreSQL Password
POSTGRES_PASSWORD=
EOF
    error_exit "Please edit the setup.env file with your configuration values and run the script again."
fi

# Load configuration
echo_status "Loading configuration from setup.env..."
source setup.env

# Validate configuration
if [ -z "$FRONTEND_URL" ]; then
    error_exit "FRONTEND_URL is not set in setup.env"
fi

if [ -z "$BACKEND_URL" ]; then
    error_exit "BACKEND_URL is not set in setup.env"
fi

if [ -z "$ADMIN_EMAIL" ]; then
    error_exit "ADMIN_EMAIL is not set in setup.env"
fi

if [ -z "$ADMIN_PW" ]; then
    error_exit "ADMIN_PW is not set in setup.env"
fi

if [ -z "$POSTGRES_USER" ]; then
    error_exit "POSTGRES_USER is not set in setup.env"
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    error_exit "POSTGRES_PASSWORD is not set in setup.env"
fi

echo_status "Using FRONTEND_URL: $FRONTEND_URL"
echo_status "Using BACKEND_URL: $BACKEND_URL"

# Fix locale issues
echo_status "Fixing locale settings..."
apt-get update


# Update system
echo_status "Updating system packages..."
apt-get update || error_exit "Failed to update package lists"

# Install required packages
echo_status "Installing required packages..."
apt-get install -y \
    perl apache2 postgresql postgresql-contrib libdbd-pg-perl wget \
    libdbi-perl texlive texlive-latex-extra texlive-pstricks texlive-science cpanminus unzip \
    git curl certbot python3-certbot-apache \
    build-essential \
    libbz2-dev zlib1g-dev \
    libarchive-zip-perl libxml-simple-perl libxml-libxml-perl \
    libdatetime-perl libdatetime-format-strptime-perl \
    libdatetime-format-iso8601-perl libdate-calc-perl \
    libfile-slurp-perl libjson-perl libmojolicious-perl \
    libdbi-perl libdbd-pg-perl libmime-base64-perl \
    libio-compress-perl libencode-perl \
    || error_exit "Failed to install required packages"

# Configure PostgreSQL
echo_status "Configuring PostgreSQL..."

# Update PostgreSQL authentication method from peer to md5
echo_status "Updating PostgreSQL authentication method..."
PG_VERSION=$(ls -d /etc/postgresql/*/ | sort -V | tail -n1 | cut -d'/' -f4)
PG_HBA_CONF="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
sed -i 's/local\s\+all\s\+all\s\+peer/local all all md5/g' $PG_HBA_CONF
systemctl restart postgresql

# Create PostgreSQL user with provided credentials
echo_status "Creating PostgreSQL user and setting permissions..."
sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD' CREATEDB;" || echo "User may already exist, continuing..."
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD' CREATEDB;" || error_exit "Failed to update PostgreSQL user"

# Restart PostgreSQL
systemctl reload postgresql 

# Install Perl modules using cpanm (only the ones not available in Debian packages)
cpanm --notest --force \
    SQL::Abstract \
    File::Copy::Recursive \
    Dotenv \
    Mojo::Template \
    IO::Compress::Zip \
    XML::Hash::XS \
    DBIx::Simple \
    Email::Stuffer \
    Email::Sender::Transport::SMTP \
    PDF::WebKit \
    Authen::SASL \
    Minion \
    Mojo::Pg \
    Text::CSV \
# Install wkhtmltopdf, needed for HTML TO PDF converstion
apt-get install -y wkhtmltopdf

# Create backend directory and clone repository
mkdir -p /var/www/html/ 
cd /var/www/html/ 

# Clone backend repository
git clone https://github.com/HashimSaqib/sql-ledger-api.git 
cd sql-ledger-api

# Create tmp directory
echo_status "Creating tmp directory..."
mkdir -p tmp
chmod 755 tmp

# Make backup script executable
echo_status "Making backup script executable..."
if [ -f "backup_datasets.pl" ]; then
    chmod +x backup_datasets.pl
    echo_status "backup_datasets.pl is now executable"
else
    echo "Warning: backup_datasets.pl not found in the repository"
fi

# Create .env file for backend
cat > .env << EOF

# DATABASE SETTINGS
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# NEOLEDGER URL FOR FILES
BACKEND_URL=$BACKEND_URL
FRONT_END_URL=$FRONTEND_URL

# PUBLIC SIGNUP & DATABASE CREATION
PUBLIC_SIGNUP=1
ALLOW_DB_CREATION=1
SUPER_USERS=$ADMIN_EMAIL

# SMTP settings
SEND_IN_BLUE=
SMTP_FROM_NAME=Neo Ledger
SMTP_HOST=
SMTP_PORT=465
SMTP_SSL=1
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_SASL=Authen::SASL


# DROPBOX SETTINGS FOR DOCUMENT MANAGEMENT
DROPBOX_KEY=
DROPBOX_SECRET=

# GOOGLE DRIVE SETTINGS FOR DOCUMENT MANAGEMENT
GOOGLE_CLIENT_ID=
GOOGLE_SECRET=
ALL_DRIVE =0
EOF

# Set proper ownership for the backend directory
echo_status "Setting proper ownership for backend directory..."
chown -R www-data:www-data /var/www/html/sql-ledger-api

# Create PostgreSQL database and import schema
sudo -u postgres psql -c "CREATE DATABASE centraldb OWNER $POSTGRES_USER;" || error_exit "Failed to create database"

# Import schema as the database owner
export PGPASSWORD="$POSTGRES_PASSWORD"
psql -U "$POSTGRES_USER" -h 127.0.0.1 centraldb < centraldb.sql || error_exit "Failed to import database schema"

# Enable pgcrypto extension
psql -U "$POSTGRES_USER" -h 127.0.0.1 centraldb -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" || error_exit "Failed to enable pgcrypto extension"

# Insert admin user
psql -U "$POSTGRES_USER" -h 127.0.0.1 centraldb -c "INSERT INTO profile (email, password) VALUES ('$ADMIN_EMAIL', crypt('$ADMIN_PW', gen_salt('bf')));" || error_exit "Failed to create admin user"

# Grant all privileges on the database to the user
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE centraldb TO $POSTGRES_USER;" || error_exit "Failed to grant database privileges"

# Install Node.js and npm (version 20 LTS)
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1 || [[ "$(node -v)" != v20* ]]; then
    # Remove existing nodejs if installed
    apt-get remove -y nodejs npm || true
    
    # Install Node.js 20 LTS
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || error_exit "Failed to setup Node.js repository"
    apt-get install -y nodejs || error_exit "Failed to install Node.js"
    
    # Verify installation
    node -v
    npm -v
fi

# Install frontend
cd /var/www/html/ || error_exit "Failed to change directory"

# Clone frontend repository
if [ -d "neo-ledger" ]; then
    cd neo-ledger
    git pull || error_exit "Failed to update frontend repository"
else
    git clone https://github.com/HashimSaqib/neo-ledger.git || error_exit "Failed to clone frontend repository"
    cd neo-ledger
fi

# Create or update neoledger.json in frontend repo
cat > neoledger.json << EOF
{
  "apiurl": "https://${BACKEND_URL}"
}
EOF

# Install Quasar CLI
npm install -g @quasar/cli || error_exit "Failed to install Quasar CLI"

# Install dependencies and build frontend
npm install || error_exit "Failed to install frontend dependencies"

quasar build || error_exit "Failed to build frontend"

# Start backend service with hypnotoad
cd /var/www/html/sql-ledger-api
hypnotoad index.pl || echo "Failed to start hypnotoad. Will try again after web server setup."

# Configure Minion workers for background job processing
echo_status "Configuring Minion workers for background job processing..."
cat > /etc/systemd/system/minion.service << EOF
[Unit]
Description=SQL-Ledger API Minion Workers
After=postgresql.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/html/sql-ledger-api
ExecStart=/var/www/html/sql-ledger-api/index.pl minion worker -m production
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Minion service
systemctl daemon-reload
systemctl enable minion
systemctl start minion || echo "Failed to start Minion service. Will try again after web server setup."

# Configure daily backup cron job
echo_status "Setting up daily backup cron job..."

# Create backup directory
echo_status "Creating backup directory..."
mkdir -p /var/backups/neoledger
chown www-data:www-data /var/backups/neoledger
chmod 755 /var/backups/neoledger

if [ -f "/var/www/html/sql-ledger-api/backup_datasets.pl" ]; then
    # Create cron job for www-data user to run backup daily at 2 AM
    cat > /tmp/backup_cron << EOF
# Daily backup of NeoLedger datasets at 2:00 AM
0 2 * * * cd /var/www/html/sql-ledger-api && ./backup_datasets.pl
EOF
    
    # Install the cron job for www-data user
    crontab -u www-data /tmp/backup_cron
    rm /tmp/backup_cron
    
    echo_status "Daily backup cron job configured for www-data user at 2:00 AM"
    echo_status "Backup script will use its internal logging system"
    echo_status "Backup directory created at /var/backups/neoledger"
else
    echo "Warning: backup_datasets.pl not found, skipping cron job setup"
fi

# Make sure Apache is installed and enabled
apt-get install -y apache2
a2enmod proxy proxy_http ssl rewrite
systemctl enable apache2
systemctl restart apache2

# Configure web server for frontend
cat > /etc/apache2/sites-available/${FRONTEND_URL}.conf << EOF
<VirtualHost *:80>
    ServerName ${FRONTEND_URL}
    DocumentRoot /var/www/html/neo-ledger/dist/spa
    
    <Directory /var/www/html/neo-ledger/dist/spa>
        Options FollowSymLinks
        AllowOverride None
        Require all granted

        RewriteEngine On

        # If a directory or a file exists, use it directly
        RewriteCond %{REQUEST_FILENAME} -f [OR]
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^ - [L]

        # Otherwise, redirect all to index.html
        RewriteRule ^ index.html [L]
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/${FRONTEND_URL}-error.log
    CustomLog \${APACHE_LOG_DIR}/${FRONTEND_URL}-access.log combined
RewriteCond %{SERVER_NAME} =${FRONTEND_URL}
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
EOF

# Configure web server for backend
echo_status "Configuring web server for backend..."
cat > /etc/apache2/sites-available/${BACKEND_URL}.conf << EOF
<VirtualHost *:80>
    ServerName ${BACKEND_URL}
    
    ProxyPreserveHost On
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/
    
    ErrorLog \${APACHE_LOG_DIR}/${BACKEND_URL}-error.log
    CustomLog \${APACHE_LOG_DIR}/${BACKEND_URL}-access.log combined
</VirtualHost>
EOF

# Enable sites
a2ensite ${FRONTEND_URL}.conf
a2ensite ${BACKEND_URL}.conf
systemctl reload apache2

# Retry starting backend service
cd /var/www/html/sql-ledger-api
hypnotoad index.pl 

# Get SSL certificates with certbot
echo_status "Obtaining SSL certificates..."
certbot --apache -d ${FRONTEND_URL} --non-interactive --agree-tos --email admin@${FRONTEND_URL} --redirect 
certbot --apache -d ${BACKEND_URL} --non-interactive --agree-tos --email admin@${BACKEND_URL} --redirect 

# Final restart of services
echo_status "Restarting services..."
systemctl restart apache2
cd /var/www/html/sql-ledger-api && hypnotoad index.pl

# Display final status
echo_status "Installation completed successfully!"
echo_status "Frontend URL: https://${FRONTEND_URL}"
echo_status "Backend URL: https://${BACKEND_URL}"
echo_status "Admin Email: ${ADMIN_EMAIL}"
echo_status "Daily backups scheduled at 2:00 AM"
echo_status "Backup directory: /var/backups/neoledger"

# Remove setup.env file (important because this contains credentials)
rm -f setup.env || echo "Warning: Could not remove setup.env file"
