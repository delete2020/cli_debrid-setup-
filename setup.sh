#!/bin/bash

# Zurg, cli_debrid, Plex, and Overseerr (optional) Setup Script
#
# Instructions:
# 1. Copy the entire script below.
# 2. Paste it into a new file on your server (e.g., `nano setup.sh`).
# 3. Make the script executable: `chmod +x setup.sh`
# 4. Run the script as root: `sudo ./setup.sh`
#
# This script will:
# - Install rclone, Docker, and Docker Compose.
# - Configure rclone for WebDAV access to Zurg.
# - Set up a systemd service for the rclone mount.
# - Install Portainer for easy Docker management.
# - Pull Docker images for Zurg, Plex, cli_debrid (dev recommended), and optionally Overseerr.
# - Create configuration files for Zurg and cli_debrid.
# - Provide a Docker Compose configuration for Portainer.
# - Test the Zurg API and rclone connection.

get_rd_key() {
  while true; do
    read -rs -p "Enter Real-Debrid API key: " key
    [[ -z "$key" ]] && { echo "API Key cannot be empty. Try again."; continue; }
    printf "%s" "$key"
    break
  done
}

get_valid_ip() {
  local ip=""
  while true; do
    read -rp "Enter IP (blank for auto-detect): " ip
    if [[ -z "$ip" ]]; then
      ip=$(ip route get 1 | awk '{print $(NF-2);exit}')
      echo "Detected IP: $ip" >&2
    fi
    if [[ -z "$ip" ]] ; then
      echo "Could not auto-detect IP. Enter manually." >&2
      continue
    fi
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ; then
      break
    else
      echo "Invalid IP. Use X.X.X.X format." >&2
    fi
  done
  echo "$ip"
}

pull_if_needed() {
  local image="$1"
  if docker inspect "$image" >/dev/null 2>&1; then
    echo "Image '$image' exists. Skipping pull."
    return 0
  fi
  echo "Pulling '$image'..."
  local retries=10
  local delay=5
  for i in $(seq 1 $retries); do
    docker pull "$image" && return 0
    echo "Image pull... still trying (Attempt $i/$retries).  Waiting $delay seconds..."
    sleep "$delay"
  done
  echo "Warning:  Couldn't pull image '$image' after $retries tries.  Moving on..."
  return 1
}

start_service_with_retry() {
  local service_name="$1"
  local action="$2"
  local retries=10
  local delay=2

  for i in $(seq 1 $retries); do
    echo "Attempting to $action $service_name (attempt $i/$retries)..."
    systemctl $action "$service_name" &>/dev/null
    if systemctl is-active --quiet "$service_name"; then
      echo "$service_name $action successful!."
      return 0
    fi
    sleep "$delay"
  done
  echo "Warning: $service_name didn't $action after $retries tries."
  return 1
}

# Combined safe_remove function with Docker container check
safe_remove() {
    local target="$1"
    if [[ -f "$target" ]]; then
        echo "Removing file: $target"
        rm -f "$target"
    elif [[ -d "$target" ]]; then
        echo "Removing directory: $target"
        rm -rf "$target"
    fi

    local containers=("zurg" "plex" "cli_debrid" "overseerr")
    for container in "${containers[@]}"; do
        if docker ps -a -q -f name="$container" | grep -q .; then
            read -rp "Docker container '$container' is already running.  Remove and start fresh? (y/n): " REMOVE_CONTAINER
            case "$REMOVE_CONTAINER" in
                [yY])
                    docker stop "$container" && docker rm "$container"
                    echo "Removed Docker container: $container"
                    ;;
                [nN])
                    echo "Keeping existing Docker container: $container"
                    ;;
                *)
                    echo "Invalid input.  Keeping existing Docker container: $container"
                    ;;
            esac
        fi
    done
}

[[ $(id -u) -ne 0 ]] && { echo "Run as root."; exit 1; }

# Recommend cli_debrid:dev
echo "It is recommended to use the 'dev' image for cli_debrid for the latest features and updates."
while true; do
  read -rp "Which cli_debrid image? (1) cli_main  (2) cli_debrid:dev (recommended) [1/2]: " CLI_DEBRID_CHOICE
  case "$CLI_DEBRID_CHOICE" in
    1)
      CLI_DEBRID_IMAGE="godver3/cli_debrid:main"
      break
      ;;
    2)
      CLI_DEBRID_IMAGE="godver3/cli_debrid:dev"
      break
      ;;
    *)
      echo "Invalid choice. Please enter 1 or 2."
      ;;
  esac
done

while true; do
  read -rp "Install Overseerr? (y/n): " OVERSEERR_CHOICE
  case "$OVERSEERR_CHOICE" in
    [yY])
      INSTALL_OVERSEERR=true
      break
      ;;
    [nN])
      INSTALL_OVERSEERR=false
      break
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

RD_API_KEY=$(get_rd_key)
LOCAL_IP=$(get_valid_ip)

# Perform a full system upgrade before installing packages
echo "Performing system update and upgrade..."
apt update && apt upgrade -y


for pkg in rclone docker docker-compose-plugin; do
  if ! command -v "$pkg" &>/dev/null; then
    echo "Installing $pkg..."
    case "$pkg" in
      rclone)                 curl https://rclone.org/install.sh | bash ;;
      docker)
        apt update && apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
        apt update && apt install -y docker-ce docker-ce-cli containerd.io
        ;;
      docker-compose-plugin) apt update; apt install -y docker-compose-plugin ;;
    esac
  fi
done

safe_remove "dummy_target" # Call the combined function

for image in ghcr.io/debridmediamanager/zurg-testing:latest lscr.io/linuxserver/plex:latest "$CLI_DEBRID_IMAGE"; do
  pull_if_needed "$image"
done
if [[ "$INSTALL_OVERSEERR" == "true" ]]; then
  pull_if_needed "lscr.io/linuxserver/overseerr:latest"
fi

docker ps -q -f name=portainer | grep -q . || { echo "Installing Portainer..."; docker volume create portainer_data; docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest; }

mkdir -p /user/logs /user/config /user/db_content /mnt/zurg /root/.config/rclone
touch /user/logs/debug.log

cat > /home/config.yml <<EOF
zurg: v1

token: $RD_API_KEY
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

cat > /user/config/settings.json <<EOF
{
    "general": {
        "disable_media_scan": true,
        "disable_webservice": false
    },
    "debrid": {
        "provider": "realdebrid",
        "api_key": "$RD_API_KEY"
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

cat > /home/plex_update.sh <<EOF
#!/bin/bash

webhook_url="http://$LOCAL_IP:5000/webhook/rclone"

for arg in "\$@"; do
  arg_clean=\$(echo "\$arg" | sed 's/\\//g')
  echo "Notifying webhook for: \$arg_clean"
  encoded_webhook_arg=\$(echo -n "\$arg_clean" | python3 -c "import sys, urllib.parse as ul; print(ul.quote(sys.stdin.read()))")
  curl -s -X GET "\$webhook_url?file=\$encoded_webhook_arg"
done

echo "Updates completed!"
EOF
chmod +x /home/plex_update.sh

cat > /root/.config/rclone/rclone.conf <<EOF
[zurg-wd]
type = webdav
url = http://127.0.0.1:9999/dav/
vendor = other
pacer_min_sleep = 10ms
pacer_burst = 0
EOF

cat > /etc/systemd/system/zurg-rclone.service <<EOF
[Unit]
Description=Rclone mount for zurg
After=network-online.target

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
systemctl daemon-reload

echo "----------------------"
cat <<EOF
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
  plex:
    image: lscr.io/linuxserver/plex:latest
    container_name: plex
    restart: unless-stopped
    network_mode: host
    environment:
      - PUID=0
      - PGID=0
    volumes:
      - /mnt:/mnt
    devices:
      - "/dev/dri:/dev/dri"
  cli_debrid:
    image: $CLI_DEBRID_IMAGE
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
      - TZ=Europe/London
EOF
if [[ "$INSTALL_OVERSEERR" == "true" ]]; then
  cat <<EOF
  overseerr:
    image: lscr.io/linuxserver/overseerr:latest
    container_name: overseerr
    volumes:
      - ./config:/config
    ports:
      - "5055:5055"
    restart: unless-stopped
    environment:
      - TZ=Europe/London
EOF
fi

cat <<EOF
EOF
echo "----------------------"
echo "Go to Portainer in your web browser: https://$LOCAL_IP:9443"
echo "Create a new stack and paste the following configuration into the web editor:"
echo "Copy everything between the dashed lines:"
read -r -p "Once the stack is deployed in Portainer, press Enter to continue..."

start_service_with_retry "zurg-rclone" "start"
systemctl enable zurg-rclone.service

start_service_with_retry "zurg-rclone" "restart"

test_api() {
  local retries=30
  for i in $(seq 1 "$retries"); do
    state=$(docker inspect --format='{{.State.Status}}' zurg 2>/dev/null)
    if [[ "$state" == "running" ]] && curl --silent --fail --output /dev/null http://localhost:9999/dav/; then
      printf 'Zurg is up and the API is ready!\n'
      return 0
    fi
    echo "Zurg: $state (attempt $i/$retries). Waiting..."
    sleep 5
  done
    printf "Error: Zurg isn't running or the API is unreachable.\n"
  return 1
}

test_rclone() {
  local retries=30
  for i in $(seq 1 "$retries"); do
    if rclone lsd zurg-wd: --verbose --retries 1 --timeout 10s 2>&1 | grep -v -- "Failed to create temp file"; then
      printf 'Rclone connection successful!\n'
      return 0
    fi
    echo "Rclone connection test failed (attempt $i/$retries).  Trying again..."
    sleep 5
  done
  printf "Error: Rclone connection failed.\n" >&2
  return 1
}

test_api || exit 1

if test_rclone; then
  printf "Setup complete! It may take some time to populate, be patient. It's a good idea to reboot your system now.\n"
else
  printf "Setup finished, but the rclone mount test failed. Check the logs!\n"
fi

printf 'Access your services:\n'
printf '  Zurg: http://%s:9999/dav/\n' "$LOCAL_IP"
if [[ "$INSTALL_OVERSEERR" == "true" ]]; then
    printf '  Overseerr: http://%s:5055\n' "$LOCAL_IP"
fi
printf '  cli_debrid: http://%s:5000\n' "$LOCAL_IP"
printf '  Plex Media Directory: /mnt\n'
