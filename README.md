# NeoLedger Installation Guide

## Quick Installation Guide

1. While it is not required, we recommend going through the detailed installation guide below before proceeding.
2. Clone the repository or download the installation script
3. Create a `setup.env` file with your configuration:
   ```bash
   # NeoLedger Configuration
   FRONTEND_URL=neoledger.example.com
   BACKEND_URL=api.neoledger.example.com
   ADMIN_EMAIL=admin@example.com
   ADMIN_PW=your_secure_password
   POSTGRES_USER=postgres_username
   POSTGRES_PASSWORD=postgres_secure_password
   ```
4. Make the installation script executable:
   ```bash
   chmod +x install.sh
   ```
5. Run the installation script as root:
   ```bash
   sudo ./install.sh
   ```
6. Update .env inside /var/www/html/sql-ledger-api to include SEND_IN_BLUE api key OR smtp details.
7. Ensure your DNS records point to your server for both the frontend and backend domains
8. Setup Google Drive OR Dropbox for document Management (Detail below).

## Overview of the Installation Process

The installation script (`install.sh`) automates the complete setup of NeoLedger.

### What the Script Installs

- **System packages**: Apache, PostgreSQL, Perl, texlive, git, curl, certbot, etc.
- **Backend**: SQL Ledger API (Perl-based)
- **Frontend**: NeoLedger (Quasar/Vue.js application)
- **Database**: PostgreSQL with centraldb schema
- **Web server**: Apache with virtual hosts
- **SSL certificates**: Using Certbot/Let's Encrypt
- **Background Jobs**: Minion job queue system with systemd service

### Configuration Process

1. **System preparation**:

   - Updates system packages
   - Installs required system packages

2. **PostgreSQL setup**:

   - Creates PostgreSQL user with provided credentials
   - Updates PostgreSQL authentication method from `peer` to `md5`
   - Creates `centraldb` database with the user as owner
   - Enables pgcrypto extension
   - Creates admin user with credentials from setup.env

3. **Backend setup**:

   - Clones backend repository (sql-ledger-api)
   - Creates a `tmp` directory for temporary files
   - Creates .env configuration file with PostgreSQL credentials
   - Starts backend service with hypnotoad

4. **Frontend setup**:

   - Installs Node.js v20 LTS
   - Installs Quasar CLI
   - Clones frontend repository (neo-ledger)
   - Creates neoledger.json configuration file
   - Builds the frontend application

5. **Web server configuration**:
   - Creates Apache virtual hosts for frontend and backend
   - Configures proxy for backend API
   - Sets up URL rewriting for SPA frontend
   - Obtains and configures SSL certificates

### Created Files and Directories

- `/var/www/html/sql-ledger-api/` - Backend application
- `/var/www/html/neo-ledger/` - Frontend application
- `/var/www/html/sql-ledger-api/.env` - Backend configuration
- `/var/www/html/neo-ledger/neoledger.json` - Frontend API URL configuration
- `/etc/apache2/sites-available/[FRONTEND_URL].conf` - Apache frontend config
- `/etc/apache2/sites-available/[BACKEND_URL].conf` - Apache backend config

## Manual Installation Guide

If you prefer to install NeoLedger manually, follow these steps:

### 1. Prerequisites

```bash
# Update system
apt-get update && apt-get upgrade -y

# Install required packages
apt-get install -y perl apache2 postgresql postgresql-contrib libdbd-pg-perl wget \
 libdbi-perl texlive texlive-latex-extra texlive-pstricks texlive-science cpanminus unzip \
 git curl certbot python3-certbot-apache build-essential libbz2-dev zlib1g-dev \
 libarchive-zip-perl libxml-simple-perl libxml-libxml-perl libdatetime-perl \
 libdatetime-format-strptime-perl libdatetime-format-iso8601-perl libdate-calc-perl \
 libfile-slurp-perl libjson-perl libmojolicious-perl libdbi-perl libdbd-pg-perl \
 libmime-base64-perl libio-compress-perl libencode-perl wkhtmltopdf

```

### 2. Install Additional Perl Modules

```bash
cpanm --notest --force SQL::Abstract File::Copy::Recursive Dotenv Mojo::Template \
 IO::Compress::Zip XML::Hash::XS DBIx::Simple Email::Stuffer Email::Sender::Transport::SMTP \
 Minion Mojo::Pg
```

### 3. Configure PostgreSQL

```bash
# Create PostgreSQL user
sudo -u postgres psql -c "CREATE USER postgres_username WITH PASSWORD 'postgres_secure_password' CREATEDB;"

# Update PostgreSQL authentication method from peer to md5
# Modify the PostgreSQL configuration file (pg_hba.conf) by changing the line:
# "local all all peer" to "local all all md5"
# This changes authentication from 'peer' (system user-based) to 'md5' (password-based),
# allowing database connections using username/password credentials

PG_VERSION=$(ls -d /etc/postgresql/*/ | sort -V | tail -n1 | cut -d'/' -f4)
PG_HBA_CONF="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
sed -i 's/local\s\+all\s\+all\s\+peer/local all all md5/g' $PG_HBA_CONF
systemctl restart postgresql

# Create database with user as owner
sudo -u postgres psql -c "CREATE DATABASE centraldb OWNER postgres_username;"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE centraldb TO postgres_username;"

# Enable pgcrypto extension
export PGPASSWORD="postgres_secure_password"
psql -U postgres_username -h 127.0.0.1 centraldb -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Import schema
psql -U postgres_username -h 127.0.0.1 centraldb < centraldb.sql

# Create admin user
psql -U postgres_username -h 127.0.0.1 centraldb -c "INSERT INTO profile (email, password) VALUES ('admin@example.com', crypt('your_password', gen_salt('bf')));"
```

### 4. Install Node.js and Quasar CLI

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Quasar CLI
npm install -g @quasar/cli
```

### 5. Setup Backend

```bash
# Create directory and clone repository
mkdir -p /var/www/html/
cd /var/www/html/
git clone https://github.com/HashimSaqib/sql-ledger-api.git
cd sql-ledger-api

# Create tmp directory
mkdir -p tmp
chmod 755 tmp


# Create .env file
# If API is defined in SEND_IN_BLUE, send in blue will be used to send email. Send Name is defined in SMTP_FROM_NAME & SMTP_USERNAME is used for send email. SMTP is used if no value in SEND_IN_BLUE. Email functionality is needed to send invite email for database access.
cat > .env << EOF
SEND_IN_BLUE=
SMTP_FROM_NAME=
SMTP_HOST=
SMTP_PORT=
SMTP_SSL=
SMTP_STARTTLS=
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_SASL=
PUBLIC_SIGNUP=1
ALLOW_DB_CREATION=1
SUPER_USERS=
DROPBOX_KEY=
DROPBOX_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_SECRET=
ALL_DRIVE=0
POSTGRES_USER=postgres_username
POSTGRES_PASSWORD=postgres_secure_password
EOF

# Set proper ownership for the backend directory
chown -R www-data:www-data /var/www/html/sql-ledger-api
# Start backend service
# Runs the backend on Port 3000 which we reverse Proxy to.
# Creates a file called hypnotoad.pid with the pid of the process.
# Process needs to be killed & restarted whenever ENV changes.
hypnotoad index.pl

# Configure and start Minion workers
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
systemctl start minion
```

### 6. Setup Frontend

```bash
cd /var/www/html/
git clone https://github.com/HashimSaqib/neo-ledger.git
cd neo-ledger

# Create configuration file
cat > neoledger.json << EOF
{
"apiurl": "https://your-backend-domain.com"
}
EOF

# Install dependencies and build
npm install
quasar build
```

### 7. Configure Apache Web Server

```bash
# Enable required modules
a2enmod proxy proxy_http ssl rewrite

# Create frontend virtual host
cat > /etc/apache2/sites-available/frontend-domain.conf << EOF
<VirtualHost *:80>
ServerName frontend-domain.com
DocumentRoot /var/www/html/neo-ledger/dist/spa

    <Directory /var/www/html/neo-ledger/dist/spa>
        Options FollowSymLinks
        AllowOverride None
        Require all granted

        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} -f [OR]
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^ - [L]
        RewriteRule ^ index.html [L]
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/frontend-domain-error.log
    CustomLog \${APACHE_LOG_DIR}/frontend-domain-access.log combined

</VirtualHost>
EOF

# Create backend virtual host
cat > /etc/apache2/sites-available/backend-domain.conf << EOF
<VirtualHost *:80>
ServerName backend-domain.com

    ProxyPreserveHost On
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/

    ErrorLog \${APACHE_LOG_DIR}/backend-domain-error.log
    CustomLog \${APACHE_LOG_DIR}/backend-domain-access.log combined

</VirtualHost>
EOF

# Enable sites
a2ensite frontend-domain.conf
a2ensite backend-domain.conf
systemctl reload apache2
```

### 8. Setup SSL Certificates

```bash
# Obtain SSL certificates with certbot
certbot --apache -d frontend-domain.com --non-interactive --agree-tos --email admin@example.com --redirect
certbot --apache -d backend-domain.com --non-interactive --agree-tos --email admin@example.com --redirect

# Final restart of services
systemctl restart apache2
cd /var/www/html/sql-ledger-api && hypnotoad index.pl
```

After completing these steps, your NeoLedger installation should be accessible at https://frontend-domain.com with the API available at https://backend-domain.com.

## Google Drive Configuration for Document Management

### 1. Create a Google Cloud Project

1. Visit the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Navigate to "APIs & Services" > "Dashboard"

### 2. Enable Google Drive API

1. Click on "+ ENABLE APIS AND SERVICES"
2. Search for "Google Drive API" and select it
3. Click "Enable"

### 3. Configure OAuth Consent Screen

1. Go to "APIs & Services" > "OAuth consent screen"
2. Select the appropriate user type:
   - **Internal**: If restricting access to your organization only
   - **External**: If allowing access to any Google account
3. Fill in the required application information:
   - App name
   - User support email
   - Developer contact information
4. Add the necessary scopes for Google Drive access
5. Add test users if needed

### 4. Create OAuth Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth client ID"
3. Select "Web application" as the application type
4. Add a name for the OAuth client
5. Under "Authorized JavaScript origins", add your frontend URL (e.g., https://neoledger.example.com)
6. Under "Authorized redirect URIs", add your frontend URL with the callback path (e.g., https://neoledger.example.com/connection)
7. Click "Create"
8. Copy the generated Client ID and Client Secret

### 5. Update NeoLedger Configuration

Update your backend `.env` file with the Google credentials:

```bash
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_SECRET=your_client_secret
ALL_DRIVE=0
```

### 6. Understanding Drive Access Levels

Google Drive API access is controlled by the `ALL_DRIVE` setting:

- **ALL_DRIVE=0 (Default/Restricted Access)**:
  - The app can only access files created by the app itself or files explicitly shared with the app
  - Cannot access shared drives
  - Recommended for most deployments
- **ALL_DRIVE=1 (Unrestricted Access)**:
  - Required for accessing shared drives
  - Can access all user files
  - Requires either:
    - Restricting the app to your organization (internal user type)
    - Going through Google's verification process (for external user type)

For most deployments, restricted access (ALL_DRIVE=0) is recommended unless shared drive access is specifically required.

## System Updates

To update your NeoLedger installation to the latest version, run the following commands:

```bash
# Update frontend
cd /var/www/html/neo-ledger
git pull
npm install
quasar build

# Update backend
cd /var/www/html/sql-ledger-api
git pull
systemctl stop minion
hypnotoad index.pl
systemctl start minion
```

This will:

1. Pull the latest changes for the frontend
2. Install any new dependencies
3. Rebuild the frontend application
4. Pull the latest changes for the backend
5. Stop the Minion worker service
6. Restart the backend service with the new changes
7. Start the Minion worker service again

Make sure to check the logs after updating to ensure everything is working correctly:

```bash
tail -f /var/log/apache2/error.log
systemctl status minion
```
