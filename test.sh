#!/bin/bash

# Simple Debrid Media Stack Setup Script
# This script sets up a media streaming stack using Real-Debrid

# Configuration
INSTALL_DIR="/opt/debrid-stack"
CONFIG_DIR="${INSTALL_DIR}/config"
LOG_DIR="${INSTALL_DIR}/logs"
MOUNT_DIR="/mnt/media"
SYMLINK_DIR="${MOUNT_DIR}/symlinked"

# Get system timezone or fallback to UTC
SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")

# Create log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Pull Docker image with retry logic
pull_docker_image() {
  local image="$1"
  local max_retries=10
  local retry_delay=5
  
  if docker inspect "$image" &>/dev/null; then
    log "Image '$image' already exists locally."
    return 0
  fi
  
  log "Pulling Docker image: $image"
  
  for ((i=1; i<=max_retries; i++)); do
    if docker pull "$image"; then
      log "Successfully pulled image: $image"
      return 0
    fi
    
    log "Pull attempt $i/$max_retries failed. Retrying in $retry_delay seconds..."
    sleep "$retry_delay"
  done
  
  log "Failed to pull image '$image' after $max_retries attempts."
  
  # Provide options to the user
  echo "Options:"
  echo "1) Retry pulling the image"
  echo "2) Continue without this image"
  echo "3) Exit setup"
  read -p "Select option [1]: " PULL_CHOICE
  PULL_CHOICE=${PULL_CHOICE:-1}
  
  case "$PULL_CHOICE" in
    1)
      log "Retrying image pull..."
      pull_docker_image "$image" $((max_retries + 5)) $((retry_delay + 5))
      ;;
    2)
      log "Continuing without image: $image"
      return 1
      ;;
    3|*)
      log "Exiting at user request."
      exit 1
      ;;
  esac
}

# Test rclone connection
test_rclone() {
  local max_retries=10
  local retry_delay=5
  
  log "Testing rclone connection to Zurg..."
  
  for ((i=1; i<=max_retries; i++)); do
    if rclone lsd zurg-wd: --verbose --retries 1 --timeout 10s 2>&1 | grep -v -- "Failed to create temp file"; then
      log "Rclone connection successful!"
      return 0
    fi
    
    log "Rclone connection test failed (attempt $i/$max_retries). Retrying..."
    sleep "$retry_delay"
  done
  
  log "Warning: Rclone connection failed after $max_retries attempts."
  return 1
}

# Check for existing containers and optionally remove them
check_existing_containers() {
  # Make sure Docker is installed before attempting to check containers
  if ! command -v docker &>/dev/null; then
    log "Docker not yet installed, skipping container check"
    return 0
  fi
  
  local containers=("zurg" "cli_debrid" "plex" "jellyfin" "emby" "overseerr" "jellyseerr")
  local found=false
  
  for container in "${containers[@]}"; do
    if docker ps -a -q -f name="$container" | grep -q .; then
      found=true
      break
    fi
  done
  
  if [[ "$found" == "true" ]]; then
    echo "Existing Docker containers from a previous installation detected."
    echo "Options:"
    echo "1) Remove all existing containers and start fresh"
    echo "2) Keep existing containers"
    read -p "Select option [1]: " CONTAINER_CHOICE
    CONTAINER_CHOICE=${CONTAINER_CHOICE:-1}
    
    if [[ "$CONTAINER_CHOICE" == "1" ]]; then
      log "Removing existing containers..."
      for container in "${containers[@]}"; do
        if docker ps -a -q -f name="$container" | grep -q .; then
          log "Stopping and removing container: $container"
          docker stop "$container" >/dev/null 2>&1
          docker rm "$container" >/dev/null 2>&1
        fi
      done
      log "All existing containers removed"
    else
      log "Keeping existing containers"
    fi
  fi
}

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root. Try: sudo $0"
  exit 1
fi

# Create directories
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
mkdir -p "$CONFIG_DIR/zurg" "$CONFIG_DIR/cli_debrid"
mkdir -p "$MOUNT_DIR" "$MOUNT_DIR/zurg" "$SYMLINK_DIR"
mkdir -p /root/.config/rclone

log "Created directory structure"

# Install Docker if not installed
log "Checking for Docker..."
if ! command -v docker &>/dev/null; then
  log "Docker not found. Installing Docker..."
  apt update
  apt install -y curl apt-transport-https ca-certificates gnupg lsb-release
  
  # Add Docker repository
  log "Adding Docker repository..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install Docker
  log "Installing Docker packages..."
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  
  # Start and enable Docker service
  log "Starting Docker service..."
  systemctl start docker
  systemctl enable docker
  
  # Verify Docker installation
  sleep 5
  if ! command -v docker &>/dev/null; then
    log "Failed to install Docker. Exiting."
    exit 1
  fi
  
  if ! systemctl is-active --quiet docker; then
    log "Docker service not running. Starting..."
    systemctl start docker
    sleep 5
    
    if ! systemctl is-active --quiet docker; then
      log "Failed to start Docker service. Exiting."
      exit 1
    fi
  fi
  
  log "Docker installed and running"
else
  log "Docker is already installed"
  
  # Ensure Docker service is running
  if ! systemctl is-active --quiet docker; then
    log "Docker service not running. Starting..."
    systemctl start docker
    sleep 5
    
    if ! systemctl is-active --quiet docker; then
      log "Failed to start Docker service. Exiting."
      exit 1
    fi
  fi
fi

# Check for existing Docker containers
check_existing_containers

# Detect system architecture
ARCHITECTURE=$(uname -m)
if [[ "$ARCHITECTURE" == "aarch64" || "$ARCHITECTURE" == "arm64" ]]; then
  ARCHITECTURE_TYPE="arm64"
else
  ARCHITECTURE_TYPE="amd64"
fi

log "System architecture detected: $ARCHITECTURE ($ARCHITECTURE_TYPE)"

# Select cli_debrid image
echo "It is recommended to use the 'dev' image for cli_debrid for the latest features."
echo "1) Standard (main)"
echo "2) Development (dev) - Recommended"
read -p "Select option [2]: " CLI_CHOICE
CLI_CHOICE=${CLI_CHOICE:-2}

if [[ "$CLI_CHOICE" == "1" ]]; then
  if [[ "$ARCHITECTURE_TYPE" == "arm64" ]]; then
    CLI_DEBRID_IMAGE="godver3/cli_debrid:main-arm64"
    log "Selected ARM64 main image: godver3/cli_debrid:main-arm64"
  else
    CLI_DEBRID_IMAGE="godver3/cli_debrid:main"
    log "Selected AMD64 main image: godver3/cli_debrid:main"
  fi
else
  if [[ "$ARCHITECTURE_TYPE" == "arm64" ]]; then
    CLI_DEBRID_IMAGE="godver3/cli_debrid:dev-arm64"
    log "Selected ARM64 dev image: godver3/cli_debrid:dev-arm64"
  else
    CLI_DEBRID_IMAGE="godver3/cli_debrid:dev"
    log "Selected AMD64 dev image: godver3/cli_debrid:dev"
  fi
fi

# Select media server
echo "Choose a media server to install:"
echo "1) Plex"
echo "2) Jellyfin"
echo "3) Emby"
echo "4) Skip (don't install any media server)"
read -p "Select option [1]: " MEDIA_CHOICE
MEDIA_CHOICE=${MEDIA_CHOICE:-1}

case "$MEDIA_CHOICE" in
  1)
    MEDIA_SERVER="plex"
    MEDIA_SERVER_IMAGE="lscr.io/linuxserver/plex:latest"
    MEDIA_SERVER_PORT="32400"
    log "Selected media server: Plex"
    ;;
  2)
    MEDIA_SERVER="jellyfin"
    MEDIA_SERVER_IMAGE="lscr.io/linuxserver/jellyfin:latest"
    MEDIA_SERVER_PORT="8096"
    log "Selected media server: Jellyfin"
    ;;
  3)
    MEDIA_SERVER="emby"
    MEDIA_SERVER_IMAGE="lscr.io/linuxserver/emby:latest" 
    MEDIA_SERVER_PORT="8096"
    log "Selected media server: Emby"
    ;;
  *)
    MEDIA_SERVER="none"
    log "Skipping media server installation"
    ;;
esac

# Select request manager
echo "Choose a request manager to install:"
echo "1) Overseerr (works best with Plex)"
echo "2) Jellyseerr (works best with Jellyfin)"
echo "3) Skip (don't install any request manager)"
read -p "Select option [1]: " REQUEST_CHOICE
REQUEST_CHOICE=${REQUEST_CHOICE:-1}

case "$REQUEST_CHOICE" in
  1)
    REQUEST_MANAGER="overseerr"
    REQUEST_MANAGER_IMAGE="lscr.io/linuxserver/overseerr:latest"
    REQUEST_MANAGER_PORT="5055"
    log "Selected request manager: Overseerr"
    ;;
  2)
    REQUEST_MANAGER="jellyseerr"
    REQUEST_MANAGER_IMAGE="fallenbagel/jellyseerr:latest"
    REQUEST_MANAGER_PORT="5055"
    log "Selected request manager: Jellyseerr"
    ;;
  *)
    REQUEST_MANAGER="none"
    log "Skipping request manager installation"
    ;;
esac

# Ask about Portainer installation
echo "Do you want to install Portainer for Docker management?"
read -p "Y/n: " PORTAINER_CHOICE
PORTAINER_CHOICE=${PORTAINER_CHOICE:-y}

if [[ "${PORTAINER_CHOICE,,}" == "y" || "${PORTAINER_CHOICE,,}" == "yes" ]]; then
  INSTALL_PORTAINER=true
  log "Portainer will be installed"
else
  INSTALL_PORTAINER=false
  log "Skipping Portainer installation"
fi

# Set timezone
echo "Current system timezone: $SYSTEM_TIMEZONE"
read -p "Enter timezone (leave blank for system timezone): " CUSTOM_TIMEZONE
TIMEZONE=${CUSTOM_TIMEZONE:-$SYSTEM_TIMEZONE}
log "Using timezone: $TIMEZONE"

# Get Real-Debrid API key
echo "Enter Real-Debrid API key (will remain on your system): "
read -s RD_API_KEY
log "Real-Debrid API key received"

# Get server IP
IP=""
read -p "Enter server IP (blank for auto-detect): " IP
if [[ -z "$IP" ]]; then
  IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
  log "Detected IP: $IP"
fi

# Check IP format
if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  log "Invalid IP format. Using localhost."
  IP="127.0.0.1"
fi

log "Using server IP: $IP"

# Install Docker if not installed
if ! command -v docker &>/dev/null; then
  log "Installing Docker..."
  apt update
  apt install -y curl apt-transport-https ca-certificates gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

if ! command -v docker &>/dev/null; then
  log "Failed to install Docker. Exiting."
  exit 1
fi

log "Docker is installed"

# Install rclone if not installed
if ! command -v rclone &>/dev/null; then
  log "Installing rclone..."
  curl https://rclone.org/install.sh | bash
  
  if ! command -v rclone &>/dev/null; then
    log "Rclone install script failed. Trying apt installation..."
    apt update && apt install -y rclone
  fi
fi

if ! command -v rclone &>/dev/null; then
  log "Failed to install rclone. Exiting."
  exit 1
fi

log "rclone is installed"

# Pull required Docker images
log "Pulling required Docker images..."
pull_docker_image "ghcr.io/debridmediamanager/zurg-testing:latest"
pull_docker_image "$CLI_DEBRID_IMAGE"

if [[ "$MEDIA_SERVER" != "none" ]]; then
  pull_docker_image "$MEDIA_SERVER_IMAGE"
fi

if [[ "$REQUEST_MANAGER" != "none" ]]; then
  pull_docker_image "$REQUEST_MANAGER_IMAGE"
fi

# Install Portainer if requested
if [[ "$INSTALL_PORTAINER" == "true" ]]; then
  if ! docker ps -q -f name=portainer | grep -q .; then
    log "Installing Portainer..."
    docker volume create portainer_data
    pull_docker_image "portainer/portainer-ce:latest"
    docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data portainer/portainer-ce:latest
    
    if docker ps -q -f name=portainer | grep -q .; then
      log "Portainer installed successfully at https://${IP}:9443"
    else 
      log "Failed to start Portainer"
    fi
  else
    log "Portainer is already running"
  fi
fi

# Configure rclone
cat > "/root/.config/rclone/rclone.conf" <<EOF
[zurg-wd]
type = webdav
url = http://127.0.0.1:9999/dav/
vendor = other
pacer_min_sleep = 10ms
pacer_burst = 0
EOF

# Create rclone mount service
cat > "/etc/systemd/system/zurg-rclone.service" <<EOF
[Unit]
Description=Rclone mount for zurg
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount \\
  --allow-non-empty \\
  --vfs-cache-mode full \\
  --vfs-read-chunk-size 1M \\
  --vfs-read-chunk-size-limit 32M \\
  --vfs-read-wait 40ms \\
  --vfs-read-ahead 64M \\
  --transfers 16 \\
  --checkers 16 \\
  --multi-thread-streams 0 \\
  --attr-timeout 3600s \\
  --buffer-size 64M \\
  --bwlimit off:100M \\
  --vfs-cache-max-age=5h \\
  --vfs-cache-max-size=2G \\
  --vfs-fast-fingerprint \\
  --cache-dir=/dev/shm \\
  --allow-other \\
  --poll-interval 60s \\
  --vfs-cache-poll-interval 30s \\
  --dir-cache-time=120s \\
  --exclude="**sample**" \\
  zurg-wd: ${MOUNT_DIR}/zurg
ExecStop=/bin/bash -c '/bin/fusermount -uz ${MOUNT_DIR}/zurg'
Restart=on-abort
RestartSec=1
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zurg-rclone.service

# Configure Zurg
cat > "${CONFIG_DIR}/zurg/webhook.sh" <<EOF
#!/bin/bash

webhook_url="http://${IP}:5000/webhook/rclone"

for arg in "\$@"; do
  arg_clean=\$(echo "\$arg" | sed 's/\\//g')
  echo "Notifying webhook for: \$arg_clean"
  encoded_webhook_arg=\$(echo -n "\$arg_clean" | python3 -c "import sys, urllib.parse as ul; print(ul.quote(sys.stdin.read()))")
  curl -s -X GET "\$webhook_url?file=\$encoded_webhook_arg"
done

echo "Updates completed!"
EOF

chmod +x "${CONFIG_DIR}/zurg/webhook.sh"

# Create Zurg configuration file
cat > "${CONFIG_DIR}/zurg/config.yml" <<EOF
zurg: v1

token: ${RD_API_KEY}
port: 9999
concurrent_workers: 64
check_for_changes_every_secs: 10
enable_repair: false
cache_network_test_results: true
serve_from_rclone: false
rar_action: none
retain_folder_name_extension: true
retain_rd_torrent_name: true
hide_broken_torrents: true
retry_503_errors: true
delete_error_torrents: true
on_library_update: sh ./webhook.sh "\$@"
directories:
  shows:
    group_order: 15
    group: media
    filters:
      - has_episodes: true
  movies:
    group_order: 25
    group: media
    filters:
      - regex: /.*/
EOF

# Create legacy compatibility symlinks for Zurg
log "Creating compatibility symlinks for Zurg configuration..."
# First, make sure destination files don't exist
rm -f /home/config.yml /home/plex_update.sh

# Create symlinks
ln -sf "${CONFIG_DIR}/zurg/config.yml" /home/config.yml
ln -sf "${CONFIG_DIR}/zurg/webhook.sh" /home/plex_update.sh

# Verify symlinks were created
if [[ -L "/home/config.yml" && -L "/home/plex_update.sh" ]]; then
  log "Compatibility symlinks created successfully"
else
  log "Warning: Failed to create compatibility symlinks. This may cause issues with Zurg."
fi

# Configure cli_debrid
mkdir -p "${CONFIG_DIR}/cli_debrid/logs"
mkdir -p "${CONFIG_DIR}/cli_debrid/db_content"
touch "${CONFIG_DIR}/cli_debrid/logs/debug.log"

cat > "${CONFIG_DIR}/cli_debrid/settings.json" <<EOF
{
    "general": {
        "disable_media_scan": true,
        "disable_webservice": false
    },
    "debrid": {
        "provider": "realdebrid",
        "api_key": "${RD_API_KEY}"
    },
    "download": {
        "path": "${MOUNT_DIR}",
        "path_style": "original",
        "seed_time": 0,
        "max_connections": 4
    },
    "system": {
        "log_level": "debug"
    }
}
EOF

# Generate Docker Compose file
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

cat > "$COMPOSE_FILE" <<EOF
version: "3.8"

services:
  zurg:
    image: ghcr.io/debridmediamanager/zurg-testing:latest
    container_name: zurg
    restart: unless-stopped
    ports:
      - "9999:9999"
    volumes:
      - /home/config.yml:/app/config.yml
      - /home/plex_update.sh:/app/webhook.sh
    environment:
      - TZ=${TIMEZONE}

  cli_debrid:
    image: ${CLI_DEBRID_IMAGE}
    pull_policy: always
    container_name: cli_debrid
    ports:
      - "5000:5000"
      - "5001:5001"
    restart: unless-stopped
    tty: true
    stdin_open: true
    volumes:
      - ${CONFIG_DIR}/cli_debrid:/user
      - ${MOUNT_DIR}:${MOUNT_DIR}
    environment:
      - TZ=${TIMEZONE}
EOF

# Add media server if selected
if [[ "$MEDIA_SERVER" != "none" ]]; then
  if [[ "$MEDIA_SERVER" == "plex" ]]; then
    cat >> "$COMPOSE_FILE" <<EOF

  plex:
    image: ${MEDIA_SERVER_IMAGE}
    container_name: plex
    restart: unless-stopped
    network_mode: host
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - ${MOUNT_DIR}:${MOUNT_DIR}
      - ${CONFIG_DIR}/plex:/config
    devices:
      - "/dev/dri:/dev/dri"
EOF
  else
    cat >> "$COMPOSE_FILE" <<EOF

  ${MEDIA_SERVER}:
    image: ${MEDIA_SERVER_IMAGE}
    container_name: ${MEDIA_SERVER}
    restart: unless-stopped
    ports:
      - "${MEDIA_SERVER_PORT}:${MEDIA_SERVER_PORT}"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - ${MOUNT_DIR}:${MOUNT_DIR}
      - ${CONFIG_DIR}/${MEDIA_SERVER}:/config
    devices:
      - "/dev/dri:/dev/dri"
EOF
  fi
fi

# Add request manager if selected
if [[ "$REQUEST_MANAGER" != "none" ]]; then
  cat >> "$COMPOSE_FILE" <<EOF

  ${REQUEST_MANAGER}:
    image: ${REQUEST_MANAGER_IMAGE}
    container_name: ${REQUEST_MANAGER}
    restart: unless-stopped
    ports:
      - "${REQUEST_MANAGER_PORT}:${REQUEST_MANAGER_PORT}"
    volumes:
      - ${CONFIG_DIR}/${REQUEST_MANAGER}:/config
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
EOF
fi

log "Docker Compose configuration saved to ${COMPOSE_FILE}"

# Display Docker Compose file
echo 
echo "Docker Compose Configuration:"
echo "-----------------------------------------------------------------------"
cat "$COMPOSE_FILE"
echo "-----------------------------------------------------------------------"

# Start rclone mount
log "Starting rclone mount service..."
systemctl start zurg-rclone.service
sleep 5

# Test rclone connection
log "Testing rclone mount..."
if ! test_rclone; then
  log "Warning: Rclone mount test failed. This might cause issues with Docker containers."
  echo "Do you want to:"
  echo "1) Continue anyway"
  echo "2) Retry starting rclone"
  echo "3) Exit setup"
  read -p "Select option [2]: " RCLONE_CHOICE
  RCLONE_CHOICE=${RCLONE_CHOICE:-2}
  
  case "$RCLONE_CHOICE" in
    1)
      log "Continuing despite rclone mount issues..."
      ;;
    2)
      log "Retrying rclone mount..."
      systemctl restart zurg-rclone.service
      sleep 10
      if ! test_rclone; then
        log "Rclone mount still failing. You may need to troubleshoot manually."
      else
        log "Rclone mount now working!"
      fi
      ;;
    3|*)
      log "Exiting at user request."
      exit 1
      ;;
  esac
fi

# Deploy containers
if [[ "$INSTALL_PORTAINER" == "true" ]]; then
  echo
  echo "Please go to Portainer in your web browser: https://${IP}:9443"
  echo "Create a new stack and import the Docker Compose configuration."
  
  # Disable rclone service temporarily if it exists
  if systemctl is-active --quiet zurg-rclone; then
    log "Temporarily stopping rclone service until Docker deployment is confirmed..."
    systemctl stop zurg-rclone
  fi
  
  read -p "Press Enter once you've deployed the stack in Portainer..."
  
  # Explicit confirmation to ensure Zurg is running
  echo "Is the Zurg container running in Portainer now? (Please verify before continuing)"
  read -p "y/N: " ZURG_RUNNING
  if [[ "${ZURG_RUNNING,,}" != "y" && "${ZURG_RUNNING,,}" != "yes" ]]; then
    log "Please make sure Zurg is running before continuing. Exiting."
    exit 1
  fi
else
  # Deploy with Docker Compose
  echo "Do you want to deploy the Docker Compose stack now?"
  read -p "Y/n: " DEPLOY_CHOICE
  DEPLOY_CHOICE=${DEPLOY_CHOICE:-y}
  
  if [[ "${DEPLOY_CHOICE,,}" == "y" || "${DEPLOY_CHOICE,,}" == "yes" ]]; then
    log "Deploying Docker Compose stack..."
    cd "$INSTALL_DIR" && docker compose up -d
    
    if [ $? -eq 0 ]; then
      log "Docker Compose stack deployed successfully"
    else
      log "Failed to deploy Docker Compose stack"
      echo "To deploy manually, run: cd $INSTALL_DIR && docker compose up -d"
      read -p "Press Enter to continue..."
    fi
  else
    echo "To deploy manually, run: cd $INSTALL_DIR && docker compose up -d"
    
    # Disable rclone service temporarily if it exists
    if systemctl is-active --quiet zurg-rclone; then
      log "Temporarily stopping rclone service until Docker deployment is confirmed..."
      systemctl stop zurg-rclone
    fi
    
    read -p "Press Enter once you've deployed the containers..."
    
    # Explicit confirmation to ensure Zurg is running
    echo "Is the Zurg container running now? (Please verify before continuing)"
    read -p "y/N: " ZURG_RUNNING
    if [[ "${ZURG_RUNNING,,}" != "y" && "${ZURG_RUNNING,,}" != "yes" ]]; then
      log "Please make sure Zurg is running before continuing. Exiting."
      exit 1
    fi
  fi
fi

# Deploy containers
if [[ "$INSTALL_PORTAINER" == "true" ]]; then
  echo
  echo "Please go to Portainer in your web browser: https://${IP}:9443"
  echo "Create a new stack and import the Docker Compose configuration."
  read -p "Press Enter once you've deployed the stack in Portainer..."
else
  # Deploy with Docker Compose
  echo "Do you want to deploy the Docker Compose stack now?"
  read -p "Y/n: " DEPLOY_CHOICE
  DEPLOY_CHOICE=${DEPLOY_CHOICE:-y}
  
  if [[ "${DEPLOY_CHOICE,,}" == "y" || "${DEPLOY_CHOICE,,}" == "yes" ]]; then
    log "Deploying Docker Compose stack..."
    cd "$INSTALL_DIR" && docker compose up -d
    
    if [ $? -eq 0 ]; then
      log "Docker Compose stack deployed successfully"
    else
      log "Failed to deploy Docker Compose stack"
      echo "To deploy manually, run: cd $INSTALL_DIR && docker compose up -d"
      read -p "Press Enter to continue..."
    fi
  else
    echo "To deploy manually, run: cd $INSTALL_DIR && docker compose up -d"
    read -p "Press Enter once you've deployed the containers..."
  fi
fi

# Wait for Docker containers to initialize, particularly Zurg
log "Waiting for Docker containers to initialize..."
sleep 10

# Now that Docker containers are running and confirmed, start the rclone mount
log "Now that Zurg is running, starting rclone mount service..."
systemctl start zurg-rclone.service
log "Waiting for rclone to initialize..."
sleep 15  # Longer wait to ensure rclone is fully initialized

# Test rclone connection
log "Testing rclone connection..."
if ! test_rclone; then
  log "Warning: Rclone connection test failed."
  echo "This could indicate that Zurg isn't properly running or the WebDAV endpoint isn't accessible."
  echo "Options:"
  echo "1) Continue anyway (media might not be accessible)"
  echo "2) Retry rclone mount"
  echo "3) Exit and troubleshoot"
  read -p "Select option [2]: " RCLONE_CHOICE
  RCLONE_CHOICE=${RCLONE_CHOICE:-2}
  
  case "$RCLONE_CHOICE" in
    1)
      log "Continuing despite rclone mount issues..."
      ;;
    2)
      log "Retrying rclone mount..."
      systemctl restart zurg-rclone.service
      sleep 15
      if ! test_rclone; then
        log "Rclone mount still failing. You may need to troubleshoot manually."
        echo "Common issues:"
        echo "- Zurg container not running"
        echo "- Zurg WebDAV endpoint not accessible"
        echo "- Real-Debrid API key issues"
        echo "You can check: docker logs zurg"
      else
        log "Rclone mount now working!"
      fi
      ;;
    3)
      log "Exiting at user request for troubleshooting."
      exit 1
      ;;
  esac
else
  log "Rclone connection successful!"
fi

# Start rclone mount
systemctl start zurg-rclone.service
sleep 5

# Display information
echo
echo "========================================================================"
echo "                      Setup Complete!                                   "
echo "========================================================================"
echo
echo "Service Access Information:"
echo "-------------------------------------------------------------------------"
echo "Zurg:                  http://${IP}:9999/dav/"
echo "cli_debrid:            http://${IP}:5000"

if [[ "$MEDIA_SERVER" == "plex" ]]; then
  echo "Plex:                  http://${IP}:32400/web"
elif [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
  echo "Jellyfin:              http://${IP}:8096"
elif [[ "$MEDIA_SERVER" == "emby" ]]; then
  echo "Emby:                  http://${IP}:8096"
fi

if [[ "$REQUEST_MANAGER" != "none" ]]; then
  echo "${REQUEST_MANAGER^}:           http://${IP}:5055"
fi

echo "-------------------------------------------------------------------------"
echo "Media Directory:        ${MOUNT_DIR}"
echo "Mounted Content:        ${MOUNT_DIR}/zurg"
echo "Symlinked Directory:    ${SYMLINK_DIR}"
echo "Configuration:          ${CONFIG_DIR}"
echo "Logs:                   ${LOG_DIR}"
echo "-------------------------------------------------------------------------"
echo
echo "NOTE: It may take some time for media to appear. Please be patient."
echo

# Ask user if they want to test the rclone connection
echo "Do you want to test the rclone connection to Zurg now?"
read -p "Y/n: " TEST_RCLONE
TEST_RCLONE=${TEST_RCLONE:-y}

if [[ "${TEST_RCLONE,,}" == "y" || "${TEST_RCLONE,,}" == "yes" ]]; then
  # Define test_rclone function
  test_rclone() {
    local max_retries=5
    local retry_delay=5
    
    log "Testing rclone connection to Zurg..."
    
    for ((i=1; i<=max_retries; i++)); do
      if rclone lsd zurg-wd: --verbose --retries 1 --timeout 10s 2>&1 | grep -v -- "Failed to create temp file"; then
        log "Rclone connection successful!"
        return 0
      fi
      
      log "Rclone connection test failed (attempt $i/$max_retries). Retrying..."
      sleep "$retry_delay"
    done
    
    log "Warning: Rclone connection failed after $max_retries attempts."
    return 1
  }

  if ! test_rclone; then
    log "Warning: Rclone connection test failed."
    echo "This could indicate that Zurg isn't properly running or the WebDAV endpoint isn't accessible."
    echo "Options:"
    echo "1) Continue anyway (media might not be accessible)"
    echo "2) Retry rclone mount"
    echo "3) Exit and troubleshoot"
    read -p "Select option [2]: " RCLONE_CHOICE
    RCLONE_CHOICE=${RCLONE_CHOICE:-2}
    
    case "$RCLONE_CHOICE" in
      1)
        log "Continuing despite rclone mount issues..."
        ;;
      2)
        log "Retrying rclone mount..."
        systemctl restart zurg-rclone.service
        sleep 15
        if ! test_rclone; then
          log "Rclone mount still failing. You may need to troubleshoot manually."
          echo "Common issues:"
          echo "- Zurg container not running"
          echo "- Zurg WebDAV endpoint not accessible"
          echo "- Real-Debrid API key issues"
          echo "You can check: docker logs zurg"
        else
          log "Rclone mount now working!"
        fi
        ;;
      3)
        log "Exiting at user request for troubleshooting."
        exit 1
        ;;
    esac
  else
    log "Rclone mount verified and working with Zurg!"
  fi
else
  log "Skipping rclone connection test."
fi

echo "========================================================================"

# Ask about reboot
echo "Would you like to reboot your system now?"
read -p "y/N: " REBOOT_CHOICE
REBOOT_CHOICE=${REBOOT_CHOICE:-n}

if [[ "${REBOOT_CHOICE,,}" == "y" || "${REBOOT_CHOICE,,}" == "yes" ]]; then
  log "Rebooting system..."
  reboot
else
  log "Reboot skipped. You may need to reboot manually for all changes to take effect."
fi
