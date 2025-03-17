#!/bin/bash
# Debrid Media Stack Setup Script
# This script sets up a complete media streaming stack using Real-Debrid

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root. Try: sudo $0"
  exit 1
fi

mkdir -p /user/logs /user/config /user/db_content
mkdir -p /mnt/zurg /mnt/symlinked
mkdir -p /root/.config/rclone
touch /user/logs/debug.log

log "Created directory structure"

if command -v docker &>/dev/null; then
  containers=("zurg" "cli_debrid" "plex" "jellyfin" "emby" "overseerr" "jellyseerr")
  for container in "${containers[@]}"; do
    if docker ps -a -q -f name="$container" | grep -q .; then
      echo "Container '$container' already exists."
      read -p "Remove it? (y/n): " REMOVE
      if [[ "${REMOVE,,}" == "y" ]]; then
        docker stop "$container" 2>/dev/null
        docker rm "$container" 2>/dev/null
        log "Removed container: $container"
      else
        log "Keeping container: $container"
      fi
    fi
  done
fi

ARCHITECTURE=$(uname -m)
if [[ "$ARCHITECTURE" == "aarch64" || "$ARCHITECTURE" == "arm64" ]]; then
  ARCHITECTURE_TYPE="arm64"
else
  ARCHITECTURE_TYPE="amd64"
fi

log "System architecture detected: $ARCHITECTURE ($ARCHITECTURE_TYPE)"

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

SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
echo "Current system timezone: $SYSTEM_TIMEZONE"
read -p "Enter timezone (leave blank for system timezone): " CUSTOM_TIMEZONE
TIMEZONE=${CUSTOM_TIMEZONE:-$SYSTEM_TIMEZONE}
log "Using timezone: $TIMEZONE"

echo "Enter Real-Debrid API key (will remain on your system): "
read -s RD_API_KEY
echo
log "Real-Debrid API key received"

IP=""
read -p "Enter server IP (blank for auto-detect): " IP
if [[ -z "$IP" ]]; then
  IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
  log "Detected IP: $IP"
fi

if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  log "Invalid IP format. Using localhost."
  IP="127.0.0.1"
fi

log "Using server IP: $IP"

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

log "Configuring rclone..."
cat > "/root/.config/rclone/rclone.conf" <<EOF
[zurg-wd]
type = webdav
url = http://127.0.0.1:9999/dav/
vendor = other
pacer_min_sleep = 10ms
pacer_burst = 0
EOF

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
  zurg-wd: /mnt/zurg
ExecStop=/bin/bash -c '/bin/fusermount -uz /mnt/zurg'
Restart=on-abort
RestartSec=1
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

log "Enabling and starting rclone service..."
systemctl daemon-reload
systemctl enable zurg-rclone.service
systemctl start zurg-rclone.service
log "Rclone service started (will connect once Zurg is running)"

log "Configuring Zurg..."
cat > "/home/plex_update.sh" <<EOF
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
chmod +x /home/plex_update.sh

cat > "/home/config.yml" <<EOF
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
on_library_update: sh ./plex_update.sh "\$@"
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

log "Configuring cli_debrid..."
cat > "/user/config/settings.json" <<EOF
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
        "path": "/mnt",
        "path_style": "original",
        "seed_time": 0,
        "max_connections": 4
    },
    "system": {
        "log_level": "debug"
    }
}
EOF

pull_docker_image() {
  local image="$1"
  local max_retries=10
  local retry_delay=5
  
  if docker inspect "$image" &>/dev/null; then
    log "Image '$image' exists. Skipping pull."
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
  
  log "Warning: Failed to pull image '$image' after $max_retries attempts."
  echo "Options:"
  echo "1) Continue anyway"
  echo "2) Retry pulling the image"
  echo "3) Exit setup"
  read -p "Select option [1]: " PULL_CHOICE
  PULL_CHOICE=${PULL_CHOICE:-1}
  
  case "$PULL_CHOICE" in
    1)
      log "Continuing without image: $image"
      return 1
      ;;
    2)
      log "Retrying image pull..."
      pull_docker_image "$image" $((max_retries + 5)) $((retry_delay + 5))
      ;;
    3|*)
      log "Exiting at user request."
      exit 1
      ;;
  esac
}

log "Pulling required Docker images..."
pull_docker_image "ghcr.io/debridmediamanager/zurg-testing:latest"
pull_docker_image "$CLI_DEBRID_IMAGE"

if [[ "$MEDIA_SERVER" != "none" ]]; then
  pull_docker_image "$MEDIA_SERVER_IMAGE"
fi

if [[ "$REQUEST_MANAGER" != "none" ]]; then
  pull_docker_image "$REQUEST_MANAGER_IMAGE"
fi

if [[ "$INSTALL_PORTAINER" == "true" ]]; then
  if ! docker ps -q -f name=portainer | grep -q .; then
    log "Installing Portainer..."
    pull_docker_image "portainer/portainer-ce:latest"
    docker volume create portainer_data
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

log "Generating Docker Compose file..."
DOCKER_COMPOSE_FILE="/tmp/docker-compose.yml"

cat > "$DOCKER_COMPOSE_FILE" <<EOF
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
      - /home/plex_update.sh:/app/plex_update.sh
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
      - /user:/user
      - /mnt:/mnt
    environment:
      - TZ=${TIMEZONE}
EOF

if [[ "$MEDIA_SERVER" != "none" ]]; then
  cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  ${MEDIA_SERVER}:
    image: ${MEDIA_SERVER_IMAGE}
    container_name: ${MEDIA_SERVER}
    restart: unless-stopped
EOF
  
  if [[ "$MEDIA_SERVER" == "plex" ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    network_mode: host
EOF
  else
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    ports:
      - "${MEDIA_SERVER_PORT}:${MEDIA_SERVER_PORT}"
EOF
  fi
  
  cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - /mnt:/mnt
EOF
  
  if [[ "$MEDIA_SERVER" == "plex" ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
      - ./config:/config
EOF
  else
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
      - ./config:/config
EOF
  fi
  
  cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    devices:
      - "/dev/dri:/dev/dri"
EOF
fi

if [[ "$REQUEST_MANAGER" != "none" ]]; then
  cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  ${REQUEST_MANAGER}:
    image: ${REQUEST_MANAGER_IMAGE}
    container_name: ${REQUEST_MANAGER}
    restart: unless-stopped
    ports:
      - "${REQUEST_MANAGER_PORT}:${REQUEST_MANAGER_PORT}"
    volumes:
      - ./config:/config
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
EOF
fi

log "Docker Compose file generated"

echo 
echo "Docker Compose Configuration:"
echo "-----------------------------------------------------------------------"
cat "$DOCKER_COMPOSE_FILE"
echo "-----------------------------------------------------------------------"

if [[ "$INSTALL_PORTAINER" == "true" ]]; then
  echo "Please go to Portainer in your web browser: https://${IP}:9443"
  echo "Create a new stack and import the Docker Compose configuration shown above."
  read -p "Press Enter once you've deployed the stack in Portainer..."
else
  echo "Do you want to deploy the Docker Compose stack now?"
  read -p "Y/n: " DEPLOY_CHOICE
  DEPLOY_CHOICE=${DEPLOY_CHOICE:-y}
  
  if [[ "${DEPLOY_CHOICE,,}" == "y" || "${DEPLOY_CHOICE,,}" == "yes" ]]; then
    log "Deploying Docker Compose stack..."
    cd /tmp && docker compose -f docker-compose.yml up -d
    
    if [ $? -eq 0 ]; then
      log "Docker Compose stack deployed successfully"
    else
      log "Failed to deploy Docker Compose stack"
      echo "To deploy manually, copy the Docker Compose config and run it with docker compose"
    fi
  else
    echo "To deploy manually, copy the Docker Compose configuration and create a docker-compose.yml file"
    read -p "Press Enter once you've deployed the containers manually..."
  fi
fi

echo "Waiting for Docker containers to initialize..."
sleep 10

log "Testing rclone connection to Zurg..."
if rclone lsd zurg-wd: --verbose 2>&1; then
  log "Rclone connection successful!"
else
  log "Rclone connection test failed. Restarting service..."
  systemctl restart zurg-rclone.service
  sleep 5
  
  if rclone lsd zurg-wd: --verbose 2>&1; then
    log "Rclone connection successful after restart!"
  else
    log "Rclone connection still failing. You may need to troubleshoot:"
    log "- Check if Zurg container is running: docker ps | grep zurg"
    log "- Check Zurg logs: docker logs zurg"
    log "- Try restarting rclone manually: systemctl restart zurg-rclone"
  fi
fi

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
echo "Media Directory:        /mnt"
echo "Mounted Content:        /mnt/zurg"
echo "Symlinked Directory:    /mnt/symlinked"
echo "Configuration Paths:"
echo "  Zurg Config:          /home/config.yml"
echo "  Webhook Script:       /home/plex_update.sh"
echo "  cli_debrid Config:    /user/config/settings.json" 
echo "  cli_debrid Logs:      /user/logs/debug.log"
echo "-------------------------------------------------------------------------"
echo "NOTE: It may take some time for media to appear. Please be patient."
echo "========================================================================"

echo "Would you like to reboot your system now?"
read -p "y/N: " REBOOT_CHOICE
REBOOT_CHOICE=${REBOOT_CHOICE:-n}

if [[ "${REBOOT_CHOICE,,}" == "y" || "${REBOOT_CHOICE,,}" == "yes" ]]; then
  log "Rebooting system..."
  reboot
else
  log "Reboot skipped. You may need to reboot manually for all changes to take effect."
fi
