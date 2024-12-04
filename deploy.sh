#!/bin/bash 

DB_NAME=""
DB_USER=""
DB_PASSWORD=""
DB_HOST=$(hostname -I | awk '{print $1}')
DB_PORT=""
APP_DIR=$(pwd)
GITHUB_URL=""
ALLOWED_IPS=()
APP_ENTRY=""
SERVER_PORT=""
while [ "$#" -gt 0 ]; do
    case $1 in
        --dbname) DB_NAME="$2";shift ;;
        --user) DB_USER="$2"; shift ;;
        --password) DB_PASSWORD="$2"; shift ;;
        --host) DB_HOST="$2"; shift ;;
        --port) DB_PORT="$2"; shift ;;
        --allowed_ips) IFS=',' read -r -a ALLOWED_IPS <<< "$2"; shift ;;
        --appdir) APP_DIR="$2"; shift ;;
        --entry_point) APP_ENTRY="$2"; shift ;;
        --server_port) SERVER_PORT="$2"; shift ;;
        --github-url) GITHUB_URL="$2"; shift ;;
        *) echo "Unknown Option $1"; exit ;;
    esac
    shift
done

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "Error: Missing Required Arguments"
    echo "Required Arguments: --dbname --user --password"
    echo "Optional Arguments: --host --port --appdir --github-url --allowed-ips"
    exit 1
fi
if [ -z "$DB_PORT" ];then 
    DB_PORT=5432
    echo "No DB Port Porvided, Using Default PostgreSQL Port $DB_PORT"
fi
if [ -z "$SERVER_PORT" ]; then
    SERVER_PORT=5000
    echo "No Server Port Provided,  Using Default Flask Port $SERVER_PORT"
fi
if ! command -v git &> /dev/null;then
    echo "Git not installed."
    echo "Installing Git"
    sudo apt update && apt install -y  git
    echo "Git Installed"
else
    echo "Git Already Installed"
fi
if [ -n "$GITHUB_URL" ];then
    echo "Cloning Git Repo"
    git clone "$GITHUB_URL" "$APP_DIR"
    echo "Repo Cloned into: $APP_DIR"
    REPO_NAME=$(basename "$GITHUB_URL" .git)
    echo "Repo Name: $REPO_NAME"
fi
echo "Application Directory: $APP_DIR"

if ! command -v psql &> /dev/null; then 
    echo "Postgres Not Installed"
    echo "Installing Postgress"
    sudo apt update && apt install -y postgresql postgresql-contrib
    echo "Postgress Installed"
else
    echo "Postgress Already Installed"
fi
echo "Configuring PostgreSQL To Allow Only The Whitelisted IP Addresses" 
sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '$DB_HOST'/g" /etc/postgresql/*/main/postgresql.conf
if [ ${#ALLOWED_IPS[@]} -gt 0 ]; then
    echo "Configuing PostgrSQL To Allow Only The Whitelisted IP Addresses"
    for IP in "${ALLOWED_IPS[@]}"; do
        echo "host  all all $IP/32  md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    done
else
    echo "No Whitelisted IPs Provided, Default will be this machine's IP"
fi
echo "New IP's Configured"
echo "Restarting PostgreSQL"
sudo systemctl restart postgresql

if ! command -v python3 &> /dev/null; then
    echo "Python3 Not Installed"
    echo "Installing Python3"
    sudo apt update && apt install -y python3 python3-pip
    echo "Python3 installed"
else
    echo "Python3 Already Installed"
fi
echo "Setting Up Python Enviroment"
python3 -m venv "$APP_DIR/venv" 
source "$APP_DIR/venv/bin/activate"

if [ -f "$APP_DIR/$REPO_NAME/requirements.txt" ]; then 
    echo "Installing Project Requirements"
    pip3 install --upgrade pip
    pip3 install -r "$APP_DIR/$REPO_NAME/requirements.txt" 
    echo "Dependancies Installed"
else
    echo "No Requirements file found" 
    echo "You Will Need To Manualy Install The Dependancies"
fi 

echo "Building Database"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
echo "Database Setup Complete" 
echo "DB NAME: $DB_NAME"
echo "DB USER: $DB_USER"
echo "DB PASSWORD: $DB_PASSWORD"
echo "DB HOST: $DB_HOST"
echo "DB PORT: $DB_PORT"

cd "$APP_DIR/$REPO_NAME" 
if [ -z "$APP_ENTRY" ]; then
    echo 'No entry point was set you will need to start the server yourself'
else
    export FLASK_APP=$APP_ENTRY
    echo "Starting Flask Server with Gunicorn"
    gunicorn --workers 4 --bind 0.0.0.0:"$SERVER_PORT" "$APP_ENTRY":app
fi

