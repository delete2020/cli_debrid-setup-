#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SERVER_IP=""
DISCORD_WEBHOOK_URL=""
AUTO_UPDATE_CONTAINERS=()

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*${NC}"
}

warning() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}"
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $*${NC}"
}

header() {
  echo -e "\n${BOLD}${MAGENTA}$*${NC}\n"
}

detect_server_ip() {
  if [[ -n "$SERVER_IP" ]]; then
    return 0
  fi
  
  log "Detecting server IP address..."
  
  if command -v ip &>/dev/null; then
    SERVER_IP=$(ip route get 1 | awk '{print $(NF-2);exit}' 2>/dev/null)
  fi
  
  if [[ -z "$SERVER_IP" ]] && command -v hostname &>/dev/null; then
    SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null)
  fi
  
  if [[ -z "$SERVER_IP" ]] && command -v ifconfig &>/dev/null; then
    SERVER_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
  fi
  
  if [[ -z "$SERVER_IP" ]]; then
    warning "Could not detect server IP. Using localhost."
    SERVER_IP="127.0.0.1"
  elif [[ ! "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    warning "Invalid IP format detected. Using localhost."
    SERVER_IP="127.0.0.1"
  else
    success "Detected IP: ${CYAN}$SERVER_IP${NC}"
  fi
  
  return 0
}

detect_timezone() {
  SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  log "Detected system timezone: ${CYAN}${SYSTEM_TIMEZONE}${NC}"
  TIMEZONE=$SYSTEM_TIMEZONE
  return 0
}

if [[ $(id -u) -ne 0 ]]; then 
  error "This script must be run as root. Try: sudo $0"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "┌─────────────────────────────────────────────────────────┐"
echo "│       Enhanced Debrid Media Stack Setup Script          │"
echo "└─────────────────────────────────────────────────────────┘"
echo -e "${NC}"

header "System Detection"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME=$NAME
  OS_ID=$ID
  OS_VERSION=$VERSION_ID
  OS_PRETTY_NAME=$PRETTY_NAME
elif type lsb_release >/dev/null 2>&1; then
  OS_NAME=$(lsb_release -si)
  OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
  OS_VERSION=$(lsb_release -sr)
  OS_PRETTY_NAME="$OS_NAME $OS_VERSION"
else
  OS_NAME=$(uname -s)
  OS_ID="unknown"
  OS_VERSION=$(uname -r)
  OS_PRETTY_NAME="$OS_NAME $OS_VERSION"
fi

log "Detected operating system: ${CYAN}$OS_PRETTY_NAME${NC}"

ARCHITECTURE=$(uname -m)
if [[ "$ARCHITECTURE" == "aarch64" || "$ARCHITECTURE" == "arm64" ]]; then
  ARCHITECTURE_TYPE="arm64"
else
  ARCHITECTURE_TYPE="amd64"
fi

log "System architecture: ${CYAN}$ARCHITECTURE${NC} (${CYAN}$ARCHITECTURE_TYPE${NC})"

IS_VPS=false
if [ -d /proc/vz ] || [ -d /proc/bc ] || [ -f /proc/user_beancounters ] || [ -d /proc/xen ]; then
  IS_VPS=true
elif [ -f /sys/hypervisor/type ]; then
  IS_VPS=true
elif [ -f /sys/class/dmi/id/product_name ]; then
  PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name)
  if [[ "$PRODUCT_NAME" == *"KVM"* ]] || [[ "$PRODUCT_NAME" == *"VMware"* ]] || [[ "$PRODUCT_NAME" == *"Virtual"* ]]; then
    IS_VPS=true
  fi
fi

if [ "$IS_VPS" = true ]; then
  log "Detected environment: ${CYAN}Virtual Private Server (VPS)${NC}"
  
  TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
  log "Available memory: ${CYAN}${TOTAL_MEM}MB${NC}"
  
  CPU_CORES=$(nproc)
  log "Available CPU cores: ${CYAN}${CPU_CORES}${NC}"
  
else
  log "Detected environment: ${CYAN}Physical or Dedicated Server${NC}"
fi

is_portainer_running() {
  if docker ps -q -f name=portainer | grep -q .; then
    return 0  # true
  else
    return 1  # false
  fi
}

setup_package_manager() {
  case $OS_ID in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|deepin)
      PKG_MANAGER="apt"
      PKG_UPDATE="apt update"
      PKG_INSTALL="apt install -y"
      success "Using APT package manager"
      ;;
    fedora|rhel|centos|rocky|almalinux|ol|scientific|amazon)
      PKG_MANAGER="dnf"
      PKG_UPDATE="dnf check-update"
      PKG_INSTALL="dnf install -y"
      success "Using DNF package manager"
      ;;
    arch|manjaro|endeavouros)
      PKG_MANAGER="pacman"
      PKG_UPDATE="pacman -Sy"
      PKG_INSTALL="pacman -S --noconfirm"
      success "Using Pacman package manager"
      ;;
    opensuse*|suse|sles)
      PKG_MANAGER="zypper"
      PKG_UPDATE="zypper refresh"
      PKG_INSTALL="zypper install -y"
      success "Using Zypper package manager"
      ;;
    alpine)
      PKG_MANAGER="apk"
      PKG_UPDATE="apk update"
      PKG_INSTALL="apk add"
      success "Using APK package manager"
      ;;
    *)
      warning "Unknown distribution. Attempting to use APT."
      PKG_MANAGER="apt"
      PKG_UPDATE="apt update"
      PKG_INSTALL="apt install -y"
      ;;
  esac
}

install_prerequisites() {
  header "Installing Prerequisites"
  
  log "Updating package lists..."
  eval "$PKG_UPDATE" || warning "Failed to update package lists. Continuing anyway."
  
  COMMON_PACKAGES="curl wget git"
  
  log "Installing common prerequisites..."
  eval "$PKG_INSTALL $COMMON_PACKAGES" || warning "Failed to install some common packages."
  
  FUSE3_INSTALLED=false
  FUSE_INSTALLED=false
  
  if command -v fusermount3 &>/dev/null || [ -f "/usr/lib/libfuse3.so.3" ] || [ -f "/usr/lib64/libfuse3.so.3" ]; then
    FUSE3_INSTALLED=true
    success "FUSE3 is already installed"
  fi
  
  if command -v fusermount &>/dev/null || [ -f "/usr/lib/libfuse.so.2" ] || [ -f "/usr/lib64/libfuse.so.2" ]; then
    FUSE_INSTALLED=true
    log "Legacy FUSE is installed"
  fi
  
  case $OS_ID in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|deepin)
      log "Installing Debian/Ubuntu specific packages..."
      eval "$PKG_INSTALL apt-transport-https ca-certificates gnupg lsb-release" || warning "Failed to install some Debian/Ubuntu specific packages."
      
      if [ "$FUSE3_INSTALLED" = false ]; then
        log "Attempting to install FUSE3..."
        if eval "$PKG_INSTALL fuse3"; then
          success "FUSE3 installed successfully"
          FUSE3_INSTALLED=true
        else
          warning "Could not install FUSE3. Will use existing FUSE if available."
        fi
      fi
      ;;
    fedora|rhel|centos|rocky|almalinux|ol|scientific|amazon)
      log "Installing RHEL/Fedora specific packages..."
      eval "$PKG_INSTALL dnf-plugins-core" || warning "Failed to install some RHEL/Fedora specific packages."
      
      if [ "$FUSE3_INSTALLED" = false ]; then
        eval "$PKG_INSTALL fuse3" || warning "Failed to install FUSE3. Will use existing FUSE if available."
      fi
      ;;
    arch|manjaro|endeavouros)
      log "Installing Arch specific packages..."
      if [ "$FUSE3_INSTALLED" = false ]; then
        eval "$PKG_INSTALL fuse3" || warning "Failed to install FUSE3. Will use existing FUSE if available."
      fi
      ;;
    opensuse*|suse|sles)
      log "Installing openSUSE specific packages..."
      if [ "$FUSE3_INSTALLED" = false ]; then
        eval "$PKG_INSTALL fuse3" || warning "Failed to install FUSE3. Will use existing FUSE if available."
      fi
      ;;
    alpine)
      log "Installing Alpine specific packages..."
      if [ "$FUSE3_INSTALLED" = false ]; then
        eval "$PKG_INSTALL fuse3" || warning "Failed to install FUSE3. Will use existing FUSE if available."
      fi
      ;;
  esac
  
  if ! lsmod | grep -q fuse; then
    log "Loading FUSE kernel module..."
    modprobe fuse 2>/dev/null || warning "Could not load FUSE kernel module. May need reboot or kernel support."
  fi
  
  if [ "$FUSE3_INSTALLED" = true ]; then
    log "Using FUSE3 for optimal performance"
  elif [ "$FUSE_INSTALLED" = true ]; then
    warning "Using legacy FUSE. Consider upgrading to FUSE3 for better performance."
  else
    error "No FUSE system detected. Mount functionality may not work correctly."
  fi
  
  success "Base prerequisites installed"
}

install_docker() {
  if command -v docker &>/dev/null; then
    success "Docker is already installed"
    return 0
  fi
  
  log "Installing Docker..."
  
  case $OS_ID in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|deepin)
      curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      apt update
      
      apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    fedora)
      dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      
      dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    centos|rhel|rocky|almalinux|ol|scientific|amazon)
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      
      dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    arch|manjaro|endeavouros)
      pacman -S --noconfirm docker docker-compose
      ;;
    opensuse*|suse|sles)
      zypper install -y docker docker-compose
      ;;
    alpine)
      apk add docker docker-compose
      ;;
    *)
      error "Unsupported distribution for Docker installation. Please install Docker manually."
      return 1
      ;;
  esac
  
  systemctl enable docker
  systemctl start docker
  
  if command -v docker &>/dev/null; then
    success "Docker installed successfully"
    return 0
  else
    error "Docker installation failed"
    return 1
  fi
}

install_rclone() {
  if command -v rclone &>/dev/null; then
    local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
    success "rclone ${CYAN}$RCLONE_VERSION${NC} is already installed"
    return 0
  fi
  
  log "Installing rclone..."
  
  if curl -s https://rclone.org/install.sh | bash; then
    if command -v rclone &>/dev/null; then
      local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
      success "rclone ${CYAN}$RCLONE_VERSION${NC} installed successfully via install script"
      return 0
    fi
  fi
  
  warning "rclone install script failed. Trying package manager installation..."
  eval "$PKG_INSTALL rclone"
  
  if command -v rclone &>/dev/null; then
    local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
    success "rclone ${CYAN}$RCLONE_VERSION${NC} installed successfully via package manager"
    return 0
  fi
  
  warning "Package manager installation failed. Trying manual installation..."
  
  local RCLONE_URL="https://downloads.rclone.org/rclone-current-linux-${ARCHITECTURE_TYPE}.zip"
  local TEMP_DIR=$(mktemp -d)
  
  curl -s -L "$RCLONE_URL" -o "$TEMP_DIR/rclone.zip"
  unzip -q "$TEMP_DIR/rclone.zip" -d "$TEMP_DIR"
  cd "$TEMP_DIR"
  cd rclone-*
  cp rclone /usr/bin/
  chmod 755 /usr/bin/rclone
  mkdir -p /usr/local/share/man/man1
  cp rclone.1 /usr/local/share/man/man1/
  
  if command -v rclone &>/dev/null; then
    local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
    success "rclone ${CYAN}$RCLONE_VERSION${NC} installed successfully via manual installation"
    rm -rf "$TEMP_DIR"
    return 0
  else
    error "rclone installation failed after multiple attempts"
    rm -rf "$TEMP_DIR"
    return 1
  fi
}

setup_directories() {
  log "Creating directory structure..."
  
  mkdir -p /user/logs /user/config /user/db_content
  mkdir -p /mnt/zurg /mnt/symlinked
  mkdir -p /jackett/config
  mkdir -p /root/.config/rclone
  touch /user/logs/debug.log
  
  mkdir -p /backup/config
  
  success "Created directory structure"
}

backup_system() {
  header "Creating System Backup"
  
  local BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
  local BACKUP_DIR="/backup/backup_${BACKUP_DATE}"
  
  mkdir -p "$BACKUP_DIR"
  
  log "Backing up configuration files..."
  
  if [ -f /home/config.yml ]; then
    cp /home/config.yml "$BACKUP_DIR/config.yml"
  fi
  
  if [ -f /home/plex_update.sh ]; then
    cp /home/plex_update.sh "$BACKUP_DIR/plex_update.sh"
  fi
  
  if [ -f /user/config/settings.json ]; then
    cp /user/config/settings.json "$BACKUP_DIR/settings.json"
  fi
  
  if [ -f /root/.config/rclone/rclone.conf ]; then
    cp /root/.config/rclone/rclone.conf "$BACKUP_DIR/rclone.conf"
  fi
  
  if [ -f /etc/systemd/system/zurg-rclone.service ]; then
    cp /etc/systemd/system/zurg-rclone.service "$BACKUP_DIR/zurg-rclone.service"
  fi
  
  if [ -f /tmp/docker-compose.yml ]; then
    cp /tmp/docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
  fi
  
  BASE_DIR="/home/$(id -un)/docker"
  if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
    cp "${BASE_DIR}/docker-compose.yml" "$BACKUP_DIR/dmb-docker-compose.yml"
  fi
  
  cat > "$BACKUP_DIR/backup_info.txt" <<EOF
Debrid Media Stack Backup
Date: $(date)
System: $OS_PRETTY_NAME
Architecture: $ARCHITECTURE ($ARCHITECTURE_TYPE)
VPS: $IS_VPS

Backed up files:
$(find "$BACKUP_DIR" -type f | grep -v backup_info.txt)
EOF

  tar -czf "/backup/debrid_backup_${BACKUP_DATE}.tar.gz" -C "/backup" "backup_${BACKUP_DATE}"
  
  rm -rf "$BACKUP_DIR"
  
  success "Backup created: ${CYAN}/backup/debrid_backup_${BACKUP_DATE}.tar.gz${NC}"
  
  echo "Available backups:"
  ls -lh /backup/debrid_backup_*.tar.gz 2>/dev/null || echo "No previous backups found."
}

restore_system() {
  header "System Restore"
  
  detect_server_ip
  
  local USING_PORTAINER=false
  if is_portainer_running; then
    log "Detected active Portainer instance"
    USING_PORTAINER=true
  fi
  
  local BACKUPS=($(ls /backup/debrid_backup_*.tar.gz 2>/dev/null))
  
  if [ ${#BACKUPS[@]} -eq 0 ]; then
    error "No backups found in /backup/"
    return 1
  fi
  
  echo "Available backups:"
  for i in "${!BACKUPS[@]}"; do
    echo "$((i+1))) ${BACKUPS[$i]} ($(date -r ${BACKUPS[$i]} "+%Y-%m-%d %H:%M:%S"))"
  done
  
  read -p "Select backup to restore [1-${#BACKUPS[@]}] or 'c' to cancel: " BACKUP_CHOICE
  
  if [[ "$BACKUP_CHOICE" == "c" || "$BACKUP_CHOICE" == "C" ]]; then
    log "Restore cancelled."
    return 0
  fi
  
  if ! [[ "$BACKUP_CHOICE" =~ ^[0-9]+$ ]] || [ "$BACKUP_CHOICE" -lt 1 ] || [ "$BACKUP_CHOICE" -gt ${#BACKUPS[@]} ]; then
    error "Invalid selection. Restore cancelled."
    return 1
  fi
  
  local SELECTED_BACKUP="${BACKUPS[$((BACKUP_CHOICE-1))]}"
  local RESTORE_DIR="/backup/restore_tmp"
  
  log "Restoring from backup: ${CYAN}$SELECTED_BACKUP${NC}"
  
  mkdir -p "$RESTORE_DIR"
  tar -xzf "$SELECTED_BACKUP" -C "$RESTORE_DIR"
  
  local EXTRACTED_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "backup_*" | head -n 1)
  
  if [ -z "$EXTRACTED_DIR" ]; then
    error "Failed to extract backup properly."
    rm -rf "$RESTORE_DIR"
    return 1
  fi
  
  local IS_DMB_BACKUP=false
  if [ -f "$EXTRACTED_DIR/dmb-docker-compose.yml" ]; then
    IS_DMB_BACKUP=true
    log "Detected DMB backup type"
  else
    log "Detected CLI-based backup type"
  fi
  
  log "Stopping services..."
  systemctl stop zurg-rclone.service 2>/dev/null
  
  if command -v docker &>/dev/null; then
    log "Stopping Docker containers..."
    if [ "$IS_DMB_BACKUP" = true ]; then
      docker stop DMB plex watchtower 2>/dev/null
    else
      docker stop zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr watchtower 2>/dev/null
    fi
  fi
  
  if [ "$IS_DMB_BACKUP" = true ]; then
    BASE_DIR="/home/$(id -un)/docker"
    mkdir -p ${BASE_DIR}
    
    if [ -f "$EXTRACTED_DIR/dmb-docker-compose.yml" ]; then
      cp "$EXTRACTED_DIR/dmb-docker-compose.yml" "${BASE_DIR}/docker-compose.yml"
      success "Restored DMB docker-compose.yml"
    fi
  else
    log "Restoring configuration files..."
    
    if [ -f "$EXTRACTED_DIR/config.yml" ]; then
      cp "$EXTRACTED_DIR/config.yml" /home/config.yml
    fi
    
    if [ -f "$EXTRACTED_DIR/plex_update.sh" ]; then
      cp "$EXTRACTED_DIR/plex_update.sh" /home/plex_update.sh
      chmod +x /home/plex_update.sh
    fi
    
    if [ -f "$EXTRACTED_DIR/settings.json" ]; then
      mkdir -p /user/config
      cp "$EXTRACTED_DIR/settings.json" /user/config/settings.json
    fi
    
    if [ -f "$EXTRACTED_DIR/rclone.conf" ]; then
      mkdir -p /root/.config/rclone
      cp "$EXTRACTED_DIR/rclone.conf" /root/.config/rclone/rclone.conf
    fi
    
    if [ -f "$EXTRACTED_DIR/zurg-rclone.service" ]; then
      cp "$EXTRACTED_DIR/zurg-rclone.service" /etc/systemd/system/zurg-rclone.service
      systemctl daemon-reload
    fi
    
    if [ -f "$EXTRACTED_DIR/docker-compose.yml" ]; then
      cp "$EXTRACTED_DIR/docker-compose.yml" /tmp/docker-compose.yml
    fi
  fi
  
  rm -rf "$RESTORE_DIR"
  
  if [ "$USING_PORTAINER" = true ]; then
    echo -e "${YELLOW}IMPORTANT: Portainer detected${NC}"
    echo -e "Please go to Portainer at ${CYAN}https://${SERVER_IP}:9443${NC} and:"
    
    if [ "$IS_DMB_BACKUP" = true ]; then
      echo "1. Update your DMB stack with the restored Docker Compose configuration"
      echo "2. Redeploy the DMB stack through Portainer interface"
      echo -e "${CYAN}Here is the restored Docker Compose configuration:${NC}"
      cat "${BASE_DIR}/docker-compose.yml"
    else
      if [ -f "/tmp/docker-compose.yml" ]; then
        echo "1. Update your stack with the restored Docker Compose configuration"
        echo "2. Redeploy the stack through Portainer interface"
        echo -e "${CYAN}Here is the restored Docker Compose configuration:${NC}"
        cat /tmp/docker-compose.yml
      else 
        echo "1. Verify your stack configuration"
        echo "2. Redeploy the stack through Portainer interface"
      fi
    fi
    read -p "Press Enter once you've updated and redeployed the stack in Portainer..."
  else
    if [ "$IS_DMB_BACKUP" = true ]; then
      log "Deploying restored DMB Docker Compose stack..."
      cd "${BASE_DIR}" && docker compose up -d
    else
      if [ -f "/tmp/docker-compose.yml" ]; then
        log "Deploying restored Docker Compose stack..."
        cd /tmp && docker compose -f docker-compose.yml up -d
      else
        log "Starting containers individually..."
        docker start zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr watchtower 2>/dev/null
      fi
      
      log "Starting rclone service..."
      systemctl start zurg-rclone.service
    fi
  fi
  
  success "Restore completed successfully"
  return 0
}

get_rd_api_key() {
  local EXISTING_KEY=""
  
  if [ -f "/home/config.yml" ]; then
    EXISTING_KEY=$(grep -oP 'token: \K.*' /home/config.yml 2>/dev/null)
  fi
  
  if [ -z "$EXISTING_KEY" ] && [ -f "/user/config/settings.json" ]; then
    EXISTING_KEY=$(grep -oP '"api_key": "\K[^"]*' /user/config/settings.json 2>/dev/null)
  fi
  
  BASE_DIR="/home/$(id -un)/docker"
  if [ -z "$EXISTING_KEY" ] && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
    EXISTING_KEY=$(grep -oP 'ZURG_INSTANCES_REALDEBRID_API_KEY=\K[^"]*' "${BASE_DIR}/docker-compose.yml" 2>/dev/null)
  fi
  
  if [ -n "$EXISTING_KEY" ]; then
    echo -e "${CYAN}Existing Real-Debrid API key found.${NC}"
    read -p "Use existing key? (Y/n): " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-y}
    
    if [[ "${USE_EXISTING,,}" == "y" || "${USE_EXISTING,,}" == "yes" ]]; then
      RD_API_KEY="$EXISTING_KEY"
      success "Using existing Real-Debrid API key"
      return 0
    fi
  fi
  
  echo -e "${YELLOW}Enter Real-Debrid API key${NC} (will remain on your system): "
  read -s RD_API_KEY
  echo
  
  if [ -z "$RD_API_KEY" ]; then
    error "API key cannot be empty"
    return 1
  fi
  
  success "Real-Debrid API key received"
  return 0
}

setup_configs() {
  header "Setting Up Configuration Files"
  
  detect_server_ip
  
  echo -e "Current server IP: ${CYAN}${SERVER_IP}${NC}"
  read -p "Enter different server IP (leave blank to use current): " CUSTOM_IP
  if [[ -n "$CUSTOM_IP" ]]; then
    if [[ "$CUSTOM_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      SERVER_IP="$CUSTOM_IP"
      success "Using custom IP: ${CYAN}$SERVER_IP${NC}"
    else
      warning "Invalid IP format. Using detected IP instead."
    fi
  fi
  
  SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  echo -e "Current system timezone: ${CYAN}${SYSTEM_TIMEZONE}${NC}"
  read -p "Enter timezone (leave blank for system timezone): " CUSTOM_TIMEZONE
  TIMEZONE=${CUSTOM_TIMEZONE:-$SYSTEM_TIMEZONE}
  log "Using timezone: ${CYAN}${TIMEZONE}${NC}"
  
  cat > "/home/plex_update.sh" <<EOF
#!/bin/bash

webhook_url="http://${SERVER_IP}:5000/webhook/rclone"

for arg in "\$@"; do
  arg_clean=\$(echo "\$arg" | sed 's/\\//g')
  echo "Notifying webhook for: \$arg_clean"
  encoded_webhook_arg=\$(echo -n "\$arg_clean" | python3 -c "import sys, urllib.parse as ul; print(ul.quote(sys.stdin.read()))")
  curl -s -X GET "\$webhook_url?file=\$encoded_webhook_arg"
done

echo "Updates completed!"
EOF
  chmod +x /home/plex_update.sh
  
  local CONCURRENT_WORKERS=64
  local CHECK_INTERVAL=10
  
  if [ "$IS_VPS" = true ] && [ $TOTAL_MEM -lt 2048 ]; then
    CONCURRENT_WORKERS=16
    CHECK_INTERVAL=30
    log "Applied VPS optimization for low memory environment"
  fi
  
  cat > "/home/config.yml" <<EOF
zurg: v1

token: ${RD_API_KEY}
port: 9999
concurrent_workers: ${CONCURRENT_WORKERS}
check_for_changes_every_secs: ${CHECK_INTERVAL}
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
After=network-online.target docker.service
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
EOF

  if [ "$FUSE3_INSTALLED" = true ]; then
    cat >> "/etc/systemd/system/zurg-rclone.service" <<EOF
  --async-read=true \\
  --use-mmap \\
  --fuse-flag=sync_read \\
EOF
  fi

  cat >> "/etc/systemd/system/zurg-rclone.service" <<EOF
  zurg-wd: /mnt/zurg
ExecStop=/bin/bash -c 'fusermount3 -uz /mnt/zurg 2>/dev/null || fusermount -uz /mnt/zurg 2>/dev/null || umount -l /mnt/zurg'
Restart=on-abort
RestartSec=1
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
  
  if [ "$IS_VPS" = true ] && [ $TOTAL_MEM -lt 2048 ]; then
    log "Applying VPS-optimized rclone settings..."
    
    sed -i 's/--vfs-cache-max-size=2G/--vfs-cache-max-size=512M/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--buffer-size 64M/--buffer-size 32M/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--transfers 16/--transfers 8/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--checkers 16/--checkers 8/g' /etc/systemd/system/zurg-rclone.service
  fi
  
  success "Configuration files created"
}

check_existing_containers() {
  if command -v docker &>/dev/null; then
    log "Checking for existing containers..."
    
    local containers=("zurg" "cli_debrid" "plex" "jellyfin" "emby" "overseerr" "jellyseerr" "jackett" "flaresolverr" "watchtower" "DMB")
    for container in "${containers[@]}"; do
      if docker ps -a -q -f name="$container" | grep -q .; then
        echo -e "Container '${CYAN}$container${NC}' already exists."
        read -p "Remove it? (y/n): " REMOVE
        if [[ "${REMOVE,,}" == "y" ]]; then
          docker stop "$container" 2>/dev/null
          docker rm "$container" 2>/dev/null
          success "Removed container: $container"
        else
          log "Keeping container: $container"
        fi
      fi
    done
  fi
}

pull_docker_image() {
  local image="$1"
  local max_retries=5
  local retry_delay=5
  local wait_for_completion=true
  
  if docker inspect "$image" &>/dev/null; then
    log "Image '${CYAN}$image${NC}' exists. Skipping pull."
    return 0
  fi
  
  log "Pulling Docker image: ${CYAN}$image${NC}"
  
  for ((i=1; i<=max_retries; i++)); do
    if docker pull "$image"; then
      success "Successfully pulled image: ${CYAN}$image${NC}"
      if docker inspect "$image" &>/dev/null; then
        return 0
      else
        warning "Image pull reported success but verification failed. Retrying..."
      fi
    else
      warning "Pull attempt $i/$max_retries failed. Retrying in $retry_delay seconds..."
      sleep "$retry_delay"
    fi
  done
  
  warning "Failed to pull image '${CYAN}$image${NC}' after $max_retries attempts."
  echo -e "${YELLOW}Options:${NC}"
  echo "1) Continue anyway"
  echo "2) Retry pulling the image"
  echo "3) Exit setup"
  read -p "Select option [1]: " PULL_CHOICE
  PULL_CHOICE=${PULL_CHOICE:-1}
  
  case "$PULL_CHOICE" in
    1)
      log "Continuing without image: ${CYAN}$image${NC}"
      return 1
      ;;
    2)
      log "Retrying image pull..."
      max_retries=$((max_retries + 5))
      retry_delay=$((retry_delay + 5))
      pull_docker_image "$image"
      ;;
    3|*)
      error "Exiting at user request."
      exit 1
      ;;
  esac
}

validate_rclone_setup() {
  log "Validating rclone configuration..."
  
  if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    error "rclone configuration file is missing"
    return 1
  fi
  
  if [ ! -f "/etc/systemd/system/zurg-rclone.service" ]; then
    error "rclone service file is missing"
    return 1
  fi
  
  if ! systemctl is-enabled zurg-rclone.service &>/dev/null; then
    warning "rclone service is not enabled. Enabling now..."
    systemctl enable zurg-rclone.service
  fi
  
  log "Testing rclone configuration..."
  if rclone lsd zurg-wd: --verbose 2>&1 | grep -q "Failed to create"; then
    warning "rclone test failed - this is expected if Zurg is not running yet"
  else
    success "rclone configuration validated"
  fi
  
  return 0
}

test_zurg_connection() {
  log "Testing Zurg connectivity..."
  
  if ! docker ps | grep -q zurg; then
    warning "Zurg container is not running. Start Docker containers first."
    return 1
  fi
  
  if ! curl -s http://localhost:9999/ping >/dev/null; then
    warning "Zurg API is not responding. Checking container logs..."
    docker logs zurg --tail 20
    return 1
  fi
  
  log "Testing rclone connection to Zurg..."
  
  if rclone lsd zurg-wd: --verbose 2>&1; then
    success "Zurg connectivity test passed successfully"
    return 0
  else
    warning "rclone connection test failed. Restarting services..."
    
    docker restart zurg
    sleep 5
    
    systemctl restart zurg-rclone.service
    sleep 5
    
    if rclone lsd zurg-wd: --verbose 2>&1; then
      success "Zurg connectivity successful after restart"
      return 0
    else
      error "Zurg connectivity test failed even after restart"
      
      echo -e "${YELLOW}Diagnostic Information:${NC}"
      echo "1. Docker container status:"
      docker ps -a | grep zurg
      
      echo -e "\n2. Zurg container logs:"
      docker logs zurg --tail 20
      
      echo -e "\n3. rclone service status:"
      systemctl status zurg-rclone.service
      
      echo -e "\n4. rclone mount point:"
      ls -la /mnt/zurg
      
      echo -e "\n5. Network connectivity:"
      curl -v http://localhost:9999/ping 2>&1 | grep -v "^{" | grep -v "^}"
      
      return 1
    fi
  fi
}

select_cli_image() {
  header "CLI Debrid Image Selection"
  echo -e "It is recommended to use the '${BOLD}dev${NC}' image for cli_debrid for the latest features."
  echo "1) Standard (main)"
  echo "2) Development (dev) - Recommended"
  read -p "Select option [2]: " CLI_CHOICE
  CLI_CHOICE=${CLI_CHOICE:-2}
  
  if [[ "$CLI_CHOICE" == "1" ]]; then
    if [[ "$ARCHITECTURE_TYPE" == "arm64" ]]; then
      CLI_DEBRID_IMAGE="godver3/cli_debrid:main-arm64"
      success "Selected ARM64 main image: ${CYAN}godver3/cli_debrid:main-arm64${NC}"
    else
      CLI_DEBRID_IMAGE="godver3/cli_debrid:main"
      success "Selected AMD64 main image: ${CYAN}godver3/cli_debrid:main${NC}"
    fi
  else
    if [[ "$ARCHITECTURE_TYPE" == "arm64" ]]; then
      CLI_DEBRID_IMAGE="godver3/cli_debrid:dev-arm64"
      success "Selected ARM64 dev image: ${CYAN}godver3/cli_debrid:dev-arm64${NC}"
    else
      CLI_DEBRID_IMAGE="godver3/cli_debrid:dev"
      success "Selected AMD64 dev image: ${CYAN}godver3/cli_debrid:dev${NC}"
    fi
  fi
}

select_auto_update_containers() {
  header "Select Containers for Auto-Updates"
  
  echo "Choose which containers you want Watchtower to automatically update:"
  
  local all_containers=()
  
  if [[ "$INSTALL_TYPE" == "dmb" ]]; then
    all_containers+=("DMB")
    if [[ "$DEPLOY_PLEX" == "true" ]]; then
      all_containers+=("plex")
    fi
  else
    all_containers+=("zurg" "cli_debrid")
    
    if [[ "$MEDIA_SERVER" != "none" ]]; then
      all_containers+=("$MEDIA_SERVER")
    fi
    
    if [[ "$REQUEST_MANAGER" != "none" ]]; then
      all_containers+=("$REQUEST_MANAGER")
    fi
    
    if [[ "$INSTALL_JACKETT" == "true" ]]; then
      all_containers+=("jackett")
    fi
    
    if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
      all_containers+=("flaresolverr")
    fi
  fi
  
  all_containers+=("watchtower")
  
  AUTO_UPDATE_CONTAINERS=()
  
  for container in "${all_containers[@]}"; do
    read -p "Auto-update ${container}? (Y/n): " UPDATE_CHOICE
    UPDATE_CHOICE=${UPDATE_CHOICE:-y}
    
    if [[ "${UPDATE_CHOICE,,}" == "y" || "${UPDATE_CHOICE,,}" == "yes" ]]; then
      AUTO_UPDATE_CONTAINERS+=("$container")
      success "Added ${CYAN}${container}${NC} to auto-update list"
    else
      log "Excluded ${container} from auto-updates"
    fi
  done
  
  echo "Final auto-update list: ${AUTO_UPDATE_CONTAINERS[*]}"
  
  if [ ${#AUTO_UPDATE_CONTAINERS[@]} -eq 0 ]; then
    warning "No containers selected for auto-updates. Watchtower will be installed but won't update any containers."
  else
    success "${#AUTO_UPDATE_CONTAINERS[@]} containers will be auto-updated"
  fi
}

setup_discord_notifications() {
  header "Discord Webhook Notifications for Watchtower"
  
  echo "Do you want to receive Discord notifications when containers are updated?"
  read -p "Y/n: " DISCORD_CHOICE
  DISCORD_CHOICE=${DISCORD_CHOICE:-y}
  
  if [[ "${DISCORD_CHOICE,,}" == "y" || "${DISCORD_CHOICE,,}" == "yes" ]]; then
    echo -e "${YELLOW}To set up Discord notifications, you need to:${NC}"
    echo "1. Open your Discord server settings"
    echo "2. Go to Integrations → Webhooks"
    echo "3. Create a new webhook and copy the webhook URL"
    echo -e "${YELLOW}Please enter your Discord webhook URL:${NC}"
    read -p "> " DISCORD_WEBHOOK_URL
    
    if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
      warning "No webhook URL provided. Discord notifications will not be enabled."
    elif [[ ! "$DISCORD_WEBHOOK_URL" == *"discord.com/api/webhooks/"* ]]; then
      warning "Invalid Discord webhook URL format. Notifications will not be enabled."
      DISCORD_WEBHOOK_URL=""
    else
      success "Discord webhook notifications will be enabled"
    fi
  else
    log "Skipping Discord notifications setup"
  fi
}

select_media_components() {
  select_cli_image
  
  header "Media Server Selection"
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
      success "Selected media server: ${CYAN}Plex${NC}"
      ;;
    2)
      MEDIA_SERVER="jellyfin"
      MEDIA_SERVER_IMAGE="lscr.io/linuxserver/jellyfin:latest"
      MEDIA_SERVER_PORT="8096"
      success "Selected media server: ${CYAN}Jellyfin${NC}"
      ;;
    3)
      MEDIA_SERVER="emby"
      MEDIA_SERVER_IMAGE="lscr.io/linuxserver/emby:latest"
      MEDIA_SERVER_PORT="8096"
      success "Selected media server: ${CYAN}Emby${NC}"
      ;;
    *)
      MEDIA_SERVER="none"
      log "Skipping media server installation"
      ;;
  esac
  
  header "Request Manager Selection"
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
      success "Selected request manager: ${CYAN}Overseerr${NC}"
      ;;
    2)
      REQUEST_MANAGER="jellyseerr"
      REQUEST_MANAGER_IMAGE="fallenbagel/jellyseerr:latest"
      REQUEST_MANAGER_PORT="5055"
      success "Selected request manager: ${CYAN}Jellyseerr${NC}"
      ;;
    *)
      REQUEST_MANAGER="none"
      log "Skipping request manager installation"
      ;;
  esac
  
  header "Torrent Indexer Setup"
  echo "Do you want to install Jackett for torrent indexer integration?"
  read -p "Y/n: " JACKETT_CHOICE
  JACKETT_CHOICE=${JACKETT_CHOICE:-y}
  
  if [[ "${JACKETT_CHOICE,,}" == "y" || "${JACKETT_CHOICE,,}" == "yes" ]]; then
    INSTALL_JACKETT=true
    success "Jackett will be installed"
    
    echo "Do you want to install FlareSolverr to help Jackett access Cloudflare-protected sites?"
    read -p "Y/n: " FLARESOLVERR_CHOICE
    FLARESOLVERR_CHOICE=${FLARESOLVERR_CHOICE:-y}
    
    if [[ "${FLARESOLVERR_CHOICE,,}" == "y" || "${FLARESOLVERR_CHOICE,,}" == "yes" ]]; then
      INSTALL_FLARESOLVERR=true
      success "FlareSolverr will be installed"
    else
      INSTALL_FLARESOLVERR=false
      log "Skipping FlareSolverr installation"
    fi
  else
    INSTALL_JACKETT=false
    INSTALL_FLARESOLVERR=false
    log "Skipping Jackett installation"
  fi
  
  header "Docker Management"
  echo "Do you want to install Portainer for Docker management?"
  read -p "Y/n: " PORTAINER_CHOICE
  PORTAINER_CHOICE=${PORTAINER_CHOICE:-y}
  
  if [[ "${PORTAINER_CHOICE,,}" == "y" || "${PORTAINER_CHOICE,,}" == "yes" ]]; then
    INSTALL_PORTAINER=true
    success "Portainer will be installed"
  else
    INSTALL_PORTAINER=false
    log "Skipping Portainer installation"
  fi
  
  header "Automatic Updates"
  echo "Do you want to enable automatic updates using Watchtower?"
  read -p "Y/n: " WATCHTOWER_CHOICE
  WATCHTOWER_CHOICE=${WATCHTOWER_CHOICE:-y}
  
  if [[ "${WATCHTOWER_CHOICE,,}" == "y" || "${WATCHTOWER_CHOICE,,}" == "yes" ]]; then
    INSTALL_WATCHTOWER=true
    
    echo "How often do you want to check for updates?"
    echo "1) Daily (recommended)"
    echo "2) Weekly"
    echo "3) Custom schedule (cron format)"
    read -p "Select option [1]: " UPDATE_SCHEDULE_CHOICE
    UPDATE_SCHEDULE_CHOICE=${UPDATE_SCHEDULE_CHOICE:-1}
    
    case "$UPDATE_SCHEDULE_CHOICE" in
      1)
        WATCHTOWER_SCHEDULE="0 3 * * *"
        ;;
      2)
        WATCHTOWER_SCHEDULE="0 3 * * 0"
        ;;
      3)
        echo "Enter custom cron schedule (e.g., '0 3 * * *' for daily at 3:00 AM):"
        read -p "> " WATCHTOWER_SCHEDULE
        if [[ -z "$WATCHTOWER_SCHEDULE" ]]; then
          WATCHTOWER_SCHEDULE="0 3 * * *"
          log "Using default schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC} (daily at 3:00 AM)"
        fi
        ;;
      *)
        WATCHTOWER_SCHEDULE="0 3 * * *"
        ;;
    esac
    
    select_auto_update_containers
    
    setup_discord_notifications
    
    success "Watchtower will be installed with schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC}"
  else
    INSTALL_WATCHTOWER=false
    log "Skipping Watchtower installation"
  fi
}

pull_required_images() {
  header "Pulling Docker Images"
  
  if [[ "$INSTALL_TYPE" == "dmb" ]]; then
    log "Pulling required DMB Docker images..."
    pull_docker_image "iampuid0/dmb:latest"
    
    if [[ "$DEPLOY_PLEX" == "true" ]]; then
      pull_docker_image "plexinc/pms-docker:latest"
    fi
    
    if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
      pull_docker_image "containrrr/watchtower:latest"
    fi
  else
    log "Pulling required CLI-based Docker images..."
    pull_docker_image "ghcr.io/debridmediamanager/zurg-testing:latest"
    pull_docker_image "$CLI_DEBRID_IMAGE"
    
    if [[ "$MEDIA_SERVER" != "none" ]]; then
      pull_docker_image "$MEDIA_SERVER_IMAGE"
    fi
    
    if [[ "$REQUEST_MANAGER" != "none" ]]; then
      pull_docker_image "$REQUEST_MANAGER_IMAGE"
    fi
    
    if [[ "$INSTALL_JACKETT" == "true" ]]; then
      pull_docker_image "linuxserver/jackett:latest"
    fi
    
    if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
      pull_docker_image "ghcr.io/flaresolverr/flaresolverr:latest"
    fi
    
    if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
      pull_docker_image "containrrr/watchtower:latest"
    fi
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
        success "Portainer installed successfully at ${CYAN}https://${SERVER_IP}:9443${NC}"
      else 
        error "Failed to start Portainer"
      fi
    else
      log "Portainer is already running"
    fi
  fi
}

generate_docker_compose() {
  header "Generating Docker Compose Configuration"
  log "Generating Docker Compose file..."
  DOCKER_COMPOSE_FILE="/tmp/docker-compose.yml"
  
  detect_server_ip

  if [[ -z "$TIMEZONE" ]]; then
    detect_timezone
  fi

  if [[ -z "$TIMEZONE" ]]; then
    TIMEZONE="Etc/UTC"
    warning "No timezone detected. Using UTC as default."
  fi

  echo "Using timezone: ${TIMEZONE} for Docker Compose"
  
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
      - TZ="${TIMEZONE:-Etc/UTC}"
EOF

  if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" zurg "* ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
  else
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
  fi

  cat >> "$DOCKER_COMPOSE_FILE" <<EOF

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
      - TZ="${TIMEZONE:-Etc/UTC}"
    depends_on:
      - zurg
EOF

  if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" cli_debrid "* ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
  else
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
  fi
  
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
      - TZ="${TIMEZONE:-Etc/UTC}"
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
    depends_on:
      cli_debrid:
        condition: service_started
EOF

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" $MEDIA_SERVER "* ]]; then
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
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
      - TZ="${TIMEZONE:-Etc/UTC}"
    depends_on:
      - ${MEDIA_SERVER}
EOF

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" $REQUEST_MANAGER "* ]]; then
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi
  
  if [[ "$INSTALL_JACKETT" == "true" ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  jackett:
    image: linuxserver/jackett:latest
    container_name: jackett
    restart: unless-stopped
    ports:
      - "9117:9117"
    volumes:
      - /jackett/config:/config
    environment:
      - PUID=1000
      - PGID=1000
      - TZ="${TIMEZONE:-Etc/UTC}"
      - AUTO_UPDATE=true
EOF

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" jackett "* ]]; then
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi
  
  if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    restart: unless-stopped
    ports:
      - "8191:8191"
    environment:
      - LOG_LEVEL=info
      - TZ="${TIMEZONE:-Etc/UTC}"
      - CAPTCHA_SOLVER=none
EOF

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" flaresolverr "* ]]; then
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi

  if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ="${TIMEZONE:-Etc/UTC}"
      - WATCHTOWER_SCHEDULE=${WATCHTOWER_SCHEDULE:-"0 3 * * *"}
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_REMOVE_VOLUMES=false
      - WATCHTOWER_INCLUDE_STOPPED=true
      - WATCHTOWER_LABEL_ENABLE=true
      - WATCHTOWER_ROLLING_RESTART=true
EOF

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
      if [[ "$DISCORD_WEBHOOK_URL" =~ discord.com/api/webhooks/([0-9]+)/([a-zA-Z0-9_-]+) ]]; then
        WEBHOOK_ID="${BASH_REMATCH[1]}"
        WEBHOOK_TOKEN="${BASH_REMATCH[2]}"
        
        cat >> "$DOCKER_COMPOSE_FILE" <<EOF
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=discord://${WEBHOOK_TOKEN}@${WEBHOOK_ID}
EOF
      else
        warning "Invalid Discord webhook URL format. Notifications will not be enabled."
      fi
    fi

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" watchtower "* ]]; then
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DOCKER_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi
  
  success "Docker Compose file generated"
  
  echo -e "\n${CYAN}${BOLD}Docker Compose Configuration:${NC}"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
  cat "$DOCKER_COMPOSE_FILE"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
}

generate_dmb_docker_compose() {
  header "Generating DMB Docker Compose Configuration"
  
  detect_server_ip
  
  CURRENT_UID=$(id -u)
  CURRENT_GID=$(id -g)
  
  log "Creating DMB directory structure..."
  
  BASE_DIR="/home/$(id -un)/docker"
  mkdir -p ${BASE_DIR}/DMB/config
  mkdir -p ${BASE_DIR}/DMB/log
  mkdir -p ${BASE_DIR}/DMB/Zurg/RD
  mkdir -p ${BASE_DIR}/DMB/Zurg/mnt
  mkdir -p ${BASE_DIR}/DMB/Riven/data
  mkdir -p ${BASE_DIR}/DMB/Riven/mnt
  mkdir -p ${BASE_DIR}/DMB/PostgreSQL/data
  mkdir -p ${BASE_DIR}/DMB/pgAdmin4/data
  mkdir -p ${BASE_DIR}/DMB/Zilean/data
  mkdir -p ${BASE_DIR}/DMB/plex_debrid
  
  success "Created DMB directory structure at ${CYAN}${BASE_DIR}/DMB${NC}"
  
  log "Creating Docker Compose file for DMB..."
  DMB_COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
  
  cat > "$DMB_COMPOSE_FILE" <<EOF
version: "3"
services:
  DMB:
    container_name: DMB
    image: iampuid0/dmb:latest
    stop_grace_period: 30s
    shm_size: 128mb
    stdin_open: true
    tty: true
    volumes:
      - ${BASE_DIR}/DMB/config:/config
      - ${BASE_DIR}/DMB/log:/log
      - ${BASE_DIR}/DMB/Zurg/RD:/zurg/RD
      - ${BASE_DIR}/DMB/Zurg/mnt:/data:rshared
      - ${BASE_DIR}/DMB/Riven/data:/riven/backend/data
      - ${BASE_DIR}/DMB/Riven/mnt:/mnt
      - ${BASE_DIR}/DMB/PostgreSQL/data:/postgres_data
      - ${BASE_DIR}/DMB/pgAdmin4/data:/pgadmin/data
      - ${BASE_DIR}/DMB/Zilean/data:/zilean/app/data
      - ${BASE_DIR}/DMB/plex_debrid:/plex_debrid/config
    environment:
      - TZ="${TIMEZONE:-Etc/UTC}"
      - PUID=${CURRENT_UID}
      - PGID=${CURRENT_GID}
      - DMB_LOG_LEVEL=INFO
      - ZURG_INSTANCES_REALDEBRID_API_KEY=${RD_API_KEY}
      - RIVEN_FRONTEND_ENV_ORIGIN=http://${SERVER_IP}:3000
    ports:
      - "3005:3005"
      - "3000:3000"
      - "5050:5050"
    devices:
      - /dev/fuse:/dev/fuse:rwm
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
      - no-new-privileges
    restart: unless-stopped
EOF

  if [[ "$INSTALL_WATCHTOWER" == "true" && " ${AUTO_UPDATE_CONTAINERS[*]} " == *" DMB "* ]]; then
    cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
  elif [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
    cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
  fi

  if [[ "$DEPLOY_PLEX" == "true" ]]; then
    mkdir -p ${BASE_DIR}/plex/library
    mkdir -p ${BASE_DIR}/plex/transcode
    
    cat >> "$DMB_COMPOSE_FILE" <<EOF

  plex:
    image: plexinc/pms-docker:latest
    container_name: plex
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - ${BASE_DIR}/plex/library:/config
      - ${BASE_DIR}/plex/transcode:/transcode
      - ${BASE_DIR}/DMB/Zurg/mnt:/data
      - ${BASE_DIR}/DMB/Riven/mnt:/mnt
    environment:
      - TZ="${TIMEZONE:-Etc/UTC}"
      - PLEX_UID=${CURRENT_UID}
      - PLEX_GID=${CURRENT_GID}
      - PLEX_CLAIM=${PLEX_CLAIM}
    ports:
      - "32400:32400"
    depends_on:
      - DMB
    restart: unless-stopped
EOF

    if [[ "$INSTALL_WATCHTOWER" == "true" && " ${AUTO_UPDATE_CONTAINERS[*]} " == *" plex "* ]]; then
      cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    elif [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
      cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi

  if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
    cat >> "$DMB_COMPOSE_FILE" <<EOF

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ="${TIMEZONE:-Etc/UTC}"
      - WATCHTOWER_SCHEDULE=${WATCHTOWER_SCHEDULE:-"0 3 * * *"}
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_REMOVE_VOLUMES=false
      - WATCHTOWER_INCLUDE_STOPPED=true
      - WATCHTOWER_LABEL_ENABLE=true
EOF

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
      if [[ "$DISCORD_WEBHOOK_URL" =~ discord.com/api/webhooks/([0-9]+)/([a-zA-Z0-9_-]+) ]]; then
        WEBHOOK_ID="${BASH_REMATCH[1]}"
        WEBHOOK_TOKEN="${BASH_REMATCH[2]}"
        
        cat >> "$DMB_COMPOSE_FILE" <<EOF
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=discord://${WEBHOOK_TOKEN}@${WEBHOOK_ID}
EOF
      else
        warning "Invalid Discord webhook URL format. Notifications will not be enabled."
      fi
    fi

    if [[ " ${AUTO_UPDATE_CONTAINERS[*]} " == *" watchtower "* ]]; then
      cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
EOF
    else
      cat >> "$DMB_COMPOSE_FILE" <<EOF
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
EOF
    fi
  fi

  success "Docker Compose file for DMB created at ${CYAN}${DMB_COMPOSE_FILE}${NC}"
  
  echo -e "\n${CYAN}${BOLD}DMB Docker Compose Configuration:${NC}"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
  cat "$DMB_COMPOSE_FILE"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
  
  return 0
}

deploy_containers() {
  header "Deploying Containers"
  
  detect_server_ip
  
  log "Verifying Docker images..."
  
  if [[ "$INSTALL_TYPE" == "dmb" ]]; then
    if ! docker image inspect iampuid0/dmb:latest &>/dev/null; then
      warning "DMB image doesn't appear to be fully pulled yet"
      echo "Attempting to pull DMB image again to ensure it's complete..."
      docker pull iampuid0/dmb:latest
      
      if ! docker image inspect iampuid0/dmb:latest &>/dev/null; then
        error "Failed to verify DMB image. Please check your internet connection."
        echo "You may need to run 'docker pull iampuid0/dmb:latest' manually before proceeding."
        read -p "Press Enter to continue anyway or Ctrl+C to abort..."
      fi
    fi
    
    if [[ "$DEPLOY_PLEX" == "true" ]] && ! docker image inspect plexinc/pms-docker:latest &>/dev/null; then
      warning "Plex image doesn't appear to be fully pulled yet"
      echo "Attempting to pull Plex image again to ensure it's complete..."
      docker pull plexinc/pms-docker:latest
    fi
  else
    if ! docker image inspect ghcr.io/debridmediamanager/zurg-testing:latest &>/dev/null; then
      warning "Zurg image doesn't appear to be fully pulled yet"
      echo "Attempting to pull Zurg image again to ensure it's complete..."
      docker pull ghcr.io/debridmediamanager/zurg-testing:latest
    fi
    
    if ! docker image inspect "$CLI_DEBRID_IMAGE" &>/dev/null; then
      warning "CLI Debrid image doesn't appear to be fully pulled yet"
      echo "Attempting to pull CLI Debrid image again to ensure it's complete..."
      docker pull "$CLI_DEBRID_IMAGE"
    fi
  fi
  
  if is_portainer_running; then
    echo -e "Portainer detected running at: ${CYAN}https://${SERVER_IP}:9443${NC}"
    echo "Please go to Portainer and:"
    echo "1. Create a new stack (or update existing)"
    echo "2. Import the Docker Compose configuration shown above"
    echo "3. Deploy the stack through Portainer interface"
    read -p "Press Enter once you've deployed the stack in Portainer..."
  else
    echo "Do you want to deploy the Docker Compose stack now?"
    read -p "Y/n: " DEPLOY_CHOICE
    DEPLOY_CHOICE=${DEPLOY_CHOICE:-y}
    
    if [[ "${DEPLOY_CHOICE,,}" == "y" || "${DEPLOY_CHOICE,,}" == "yes" ]]; then
      if [[ "$INSTALL_TYPE" == "dmb" ]]; then
        log "Deploying DMB Docker Compose stack..."
        cd "${BASE_DIR}" && docker compose up -d
      else
        log "Deploying Docker Compose stack..."
        cd /tmp && docker compose -f docker-compose.yml up -d
      fi
      
      if [ $? -eq 0 ]; then
        success "Docker Compose stack deployed successfully"
      else
        error "Failed to deploy Docker Compose stack"
        echo "To deploy manually, copy the Docker Compose config and run it with docker compose"
      fi
    else
      echo "To deploy manually, copy the Docker Compose configuration and create a docker-compose.yml file"
      read -p "Press Enter once you've deployed the containers manually..."
    fi
  fi
}

update_existing_setup() {
  AUTO_UPDATE_CONTAINERS=()
  header "Update Existing Setup"
  
  detect_server_ip
  detect_timezone
  
  local USING_PORTAINER=false
  if is_portainer_running; then
    log "Detected active Portainer instance"
    USING_PORTAINER=true
  fi
  
  local IS_DMB_SETUP=false
  if docker ps -a -q -f name="DMB" | grep -q .; then
    IS_DMB_SETUP=true
    log "Detected DMB-based setup"
  else
    log "Detected CLI-based setup"
  fi
  
  if ! get_rd_api_key; then
    return 1
  fi
  
  backup_system
  
  if [ "$IS_DMB_SETUP" = true ]; then
    if ! docker ps -a -q -f name="DMB" | grep -q .; then
      error "DMB container not found. This doesn't appear to be an existing DMB setup."
      return 1
    fi
    
    BASE_DIR="/home/$(id -un)/docker"
    if [ ! -f "${BASE_DIR}/docker-compose.yml" ]; then
      warning "DMB docker-compose.yml not found at expected location. Creating new one."
    fi
    
    log "Stopping DMB containers..."
    docker stop DMB plex watchtower 2>/dev/null
    
    log "Updating DMB Docker images..."
    docker pull iampuid0/dmb:latest
    
    if ! docker image inspect iampuid0/dmb:latest &>/dev/null; then
      warning "DMB image doesn't appear to be fully pulled yet"
      echo "Attempting to pull DMB image again to ensure it's complete..."
      docker pull iampuid0/dmb:latest
      
      if ! docker image inspect iampuid0/dmb:latest &>/dev/null; then
        error "Failed to verify DMB image. Please check your internet connection."
        echo "You may need to run 'docker pull iampuid0/dmb:latest' manually before proceeding."
        read -p "Press Enter to continue anyway or Ctrl+C to abort..."
      fi
    else
      success "DMB image updated successfully"
    fi
    
    if docker ps -a -q -f name="plex" | grep -q .; then
      docker pull plexinc/pms-docker:latest
      
      if ! docker image inspect plexinc/pms-docker:latest &>/dev/null; then
        warning "Plex image doesn't appear to be fully pulled yet"
        echo "Attempting to pull Plex image again to ensure it's complete..."
        docker pull plexinc/pms-docker:latest
      else
        success "Plex image updated successfully"
      fi
      
      DEPLOY_PLEX=true
    else
      DEPLOY_PLEX=false
    fi
    
    if docker ps -a -q -f name="watchtower" | grep -q .; then
      INSTALL_WATCHTOWER=true
      log "Watchtower exists. Will update it."
      
      echo "Do you want to select which containers Watchtower should automatically update?"
      read -p "y/N: " SELECT_CONTAINERS
      SELECT_CONTAINERS=${SELECT_CONTAINERS:-n}
      
      if [[ "${SELECT_CONTAINERS,,}" == "y" || "${SELECT_CONTAINERS,,}" == "yes" ]]; then
        AUTO_UPDATE_CONTAINERS=("DMB")
        
        if [ "$DEPLOY_PLEX" = true ]; then
          AUTO_UPDATE_CONTAINERS+=("plex")
        fi
        
        AUTO_UPDATE_CONTAINERS+=("watchtower")
        
        select_auto_update_containers
      fi
      
      echo "Do you want to set up Discord notifications for Watchtower updates?"
      read -p "y/N: " SETUP_DISCORD
      SETUP_DISCORD=${SETUP_DISCORD:-n}
      
      if [[ "${SETUP_DISCORD,,}" == "y" || "${SETUP_DISCORD,,}" == "yes" ]]; then
        setup_discord_notifications
      fi
      
      docker pull containrrr/watchtower:latest
    else
      echo "Do you want to add Watchtower for automatic updates?"
      read -p "y/N: " ADD_WATCHTOWER
      ADD_WATCHTOWER=${ADD_WATCHTOWER:-n}
      
      if [[ "${ADD_WATCHTOWER,,}" == "y" || "${ADD_WATCHTOWER,,}" == "yes" ]]; then
        INSTALL_WATCHTOWER=true
        
        echo "How often do you want to check for updates?"
        echo "1) Daily (recommended)"
        echo "2) Weekly"
        echo "3) Custom schedule (cron format)"
        read -p "Select option [1]: " UPDATE_SCHEDULE_CHOICE
        UPDATE_SCHEDULE_CHOICE=${UPDATE_SCHEDULE_CHOICE:-1}
        
        case "$UPDATE_SCHEDULE_CHOICE" in
          1)
            WATCHTOWER_SCHEDULE="0 3 * * *"
            ;;
          2)
            WATCHTOWER_SCHEDULE="0 3 * * 0"
            ;;
          3)
            echo "Enter custom cron schedule (e.g., '0 3 * * *' for daily at 3:00 AM):"
            read -p "> " WATCHTOWER_SCHEDULE
            ;;
          *)
            WATCHTOWER_SCHEDULE="0 3 * * *"
            ;;
        esac
        
        AUTO_UPDATE_CONTAINERS=("DMB")
        
        if [ "$DEPLOY_PLEX" = true ]; then
          AUTO_UPDATE_CONTAINERS+=("plex")
        fi
        
        AUTO_UPDATE_CONTAINERS+=("watchtower")
        
        select_auto_update_containers
        
        setup_discord_notifications
        
        success "Watchtower will be installed with schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC}"
        docker pull containrrr/watchtower:latest
      else
        INSTALL_WATCHTOWER=false
      fi
    fi
    
    generate_dmb_docker_compose
    
  else
    if ! docker ps -a -q -f name="zurg" | grep -q .; then
      error "Zurg container not found. This doesn't appear to be an existing CLI setup."
      return 1
    fi
    
    log "Stopping services..."
    systemctl stop zurg-rclone.service 2>/dev/null
    
    log "Stopping Docker containers..."
    docker stop zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr watchtower 2>/dev/null
    
    log "Updating Docker images..."
    docker pull ghcr.io/debridmediamanager/zurg-testing:latest
    
    if ! docker image inspect ghcr.io/debridmediamanager/zurg-testing:latest &>/dev/null; then
      warning "Zurg image doesn't appear to be fully pulled yet"
      echo "Attempting to pull Zurg image again to ensure it's complete..."
      docker pull ghcr.io/debridmediamanager/zurg-testing:latest
      
      if ! docker image inspect ghcr.io/debridmediamanager/zurg-testing:latest &>/dev/null; then
        error "Failed to verify Zurg image. Please check your internet connection."
        echo "You may need to run 'docker pull ghcr.io/debridmediamanager/zurg-testing:latest' manually before proceeding."
        read -p "Press Enter to continue anyway or Ctrl+C to abort..."
      else
        success "Zurg image updated successfully"
      fi
    else
      success "Zurg image updated successfully"
    fi
    
    CLI_CURRENT_IMAGE=$(docker inspect --format='{{.Config.Image}}' cli_debrid 2>/dev/null)
    if [ -n "$CLI_CURRENT_IMAGE" ]; then
      docker pull "$CLI_CURRENT_IMAGE"
      
      if ! docker image inspect "$CLI_CURRENT_IMAGE" &>/dev/null; then
        warning "CLI Debrid image doesn't appear to be fully pulled yet"
        echo "Attempting to pull CLI Debrid image again to ensure it's complete..."
        docker pull "$CLI_CURRENT_IMAGE"
        
        if ! docker image inspect "$CLI_CURRENT_IMAGE" &>/dev/null; then
          error "Failed to verify CLI Debrid image. Please check your internet connection."
          echo "You may need to run 'docker pull ${CLI_CURRENT_IMAGE}' manually before proceeding."
          read -p "Press Enter to continue anyway or Ctrl+C to abort..."
        else
          success "CLI Debrid image updated successfully"
        fi
      else
        success "CLI Debrid image updated successfully"
      fi
      
      CLI_DEBRID_IMAGE="$CLI_CURRENT_IMAGE"  # Set this for use in docker-compose generation
      success "Using existing CLI image: ${CYAN}$CLI_DEBRID_IMAGE${NC}"
    else
      warning "Could not determine current CLI image. User selection required."
      select_cli_image
    fi
    
    AUTO_UPDATE_CONTAINERS=()
    if docker ps -a -q -f name="watchtower" | grep -q .; then
      INSTALL_WATCHTOWER=true
      log "Watchtower exists. Will update it."
      
      echo "Do you want to select which containers Watchtower should automatically update?"
      read -p "y/N: " SELECT_CONTAINERS
      SELECT_CONTAINERS=${SELECT_CONTAINERS:-n}
      
      if [[ "${SELECT_CONTAINERS,,}" == "y" || "${SELECT_CONTAINERS,,}" == "yes" ]]; then
        if docker ps -a -q -f name="zurg" | grep -q .; then
          AUTO_UPDATE_CONTAINERS+=("zurg")
        fi
        
        if docker ps -a -q -f name="cli_debrid" | grep -q .; then
          AUTO_UPDATE_CONTAINERS+=("cli_debrid")
        fi
        
        if docker ps -a -q -f name="plex" | grep -q .; then
          MEDIA_SERVER="plex"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' plex 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("plex")
        elif docker ps -a -q -f name="jellyfin" | grep -q .; then
          MEDIA_SERVER="jellyfin"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyfin 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("jellyfin")
        elif docker ps -a -q -f name="emby" | grep -q .; then
          MEDIA_SERVER="emby"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' emby 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("emby")
        else
          MEDIA_SERVER="none"
        fi
        
        if docker ps -a -q -f name="overseerr" | grep -q .; then
          REQUEST_MANAGER="overseerr"
          REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' overseerr 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("overseerr")
        elif docker ps -a -q -f name="jellyseerr" | grep -q .; then
          REQUEST_MANAGER="jellyseerr"
          REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyseerr 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("jellyseerr")
        else
          REQUEST_MANAGER="none"
        fi
        
        if docker ps -a -q -f name="jackett" | grep -q .; then
          INSTALL_JACKETT=true
          AUTO_UPDATE_CONTAINERS+=("jackett")
        else
          INSTALL_JACKETT=false
        fi
        
        if docker ps -a -q -f name="flaresolverr" | grep -q .; then
          INSTALL_FLARESOLVERR=true
          AUTO_UPDATE_CONTAINERS+=("flaresolverr")
        else
          INSTALL_FLARESOLVERR=false
        fi
        
        AUTO_UPDATE_CONTAINERS+=("watchtower")
        
        select_auto_update_containers
      fi
      
      echo "Do you want to set up Discord notifications for Watchtower updates?"
      read -p "y/N: " SETUP_DISCORD
      SETUP_DISCORD=${SETUP_DISCORD:-n}
      
      if [[ "${SETUP_DISCORD,,}" == "y" || "${SETUP_DISCORD,,}" == "yes" ]]; then
        setup_discord_notifications
      fi
      
      docker pull containrrr/watchtower:latest
    else
      echo "Do you want to add Watchtower for automatic updates?"
      read -p "y/N: " ADD_WATCHTOWER
      ADD_WATCHTOWER=${ADD_WATCHTOWER:-n}
      
      if [[ "${ADD_WATCHTOWER,,}" == "y" || "${ADD_WATCHTOWER,,}" == "yes" ]]; then
        INSTALL_WATCHTOWER=true
        
        echo "How often do you want to check for updates?"
        echo "1) Daily (recommended)"
        echo "2) Weekly"
        echo "3) Custom schedule (cron format)"
        read -p "Select option [1]: " UPDATE_SCHEDULE_CHOICE
        UPDATE_SCHEDULE_CHOICE=${UPDATE_SCHEDULE_CHOICE:-1}
        
        case "$UPDATE_SCHEDULE_CHOICE" in
          1)
            WATCHTOWER_SCHEDULE="0 3 * * *"
            ;;
          2)
            WATCHTOWER_SCHEDULE="0 3 * * 0"
            ;;
          3)
            echo "Enter custom cron schedule (e.g., '0 3 * * *' for daily at 3:00 AM):"
            read -p "> " WATCHTOWER_SCHEDULE
            ;;
          *)
            WATCHTOWER_SCHEDULE="0 3 * * *"
            ;;
        esac
        
        if docker ps -a -q -f name="zurg" | grep -q .; then
          AUTO_UPDATE_CONTAINERS+=("zurg")
        fi
        
        if docker ps -a -q -f name="cli_debrid" | grep -q .; then
          AUTO_UPDATE_CONTAINERS+=("cli_debrid")
        fi
        
        if docker ps -a -q -f name="plex" | grep -q .; then
          MEDIA_SERVER="plex"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' plex 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("plex")
        elif docker ps -a -q -f name="jellyfin" | grep -q .; then
          MEDIA_SERVER="jellyfin"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyfin 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("jellyfin")
        elif docker ps -a -q -f name="emby" | grep -q .; then
          MEDIA_SERVER="emby"
          MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' emby 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("emby")
        else
          MEDIA_SERVER="none"
        fi
        
        if docker ps -a -q -f name="overseerr" | grep -q .; then
          REQUEST_MANAGER="overseerr"
          REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' overseerr 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("overseerr")
        elif docker ps -a -q -f name="jellyseerr" | grep -q .; then
          REQUEST_MANAGER="jellyseerr"
          REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyseerr 2>/dev/null)
          AUTO_UPDATE_CONTAINERS+=("jellyseerr")
        else
          REQUEST_MANAGER="none"
        fi
        
        if docker ps -a -q -f name="jackett" | grep -q .; then
          INSTALL_JACKETT=true
          AUTO_UPDATE_CONTAINERS+=("jackett")
        else
          INSTALL_JACKETT=false
        fi
        
        if docker ps -a -q -f name="flaresolverr" | grep -q .; then
          INSTALL_FLARESOLVERR=true
          AUTO_UPDATE_CONTAINERS+=("flaresolverr")
        else
          INSTALL_FLARESOLVERR=false
        fi
        
        AUTO_UPDATE_CONTAINERS+=("watchtower")
        
        select_auto_update_containers
        
        setup_discord_notifications
        
        success "Watchtower will be installed with schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC}"
        docker pull containrrr/watchtower:latest
      else
        INSTALL_WATCHTOWER=false
      fi
    fi
    
    for container in "plex" "jellyfin" "emby" "overseerr" "jellyseerr" "jackett" "flaresolverr"; do
      if docker ps -a -q -f name="$container" | grep -q .; then
        CONTAINER_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
        if [ -n "$CONTAINER_IMAGE" ]; then
          log "Updating $container image..."
          docker pull "$CONTAINER_IMAGE"
        fi
      fi
    done
    
    log "Regenerating Docker Compose file..."
    if docker ps -a -q -f name="plex" | grep -q .; then
      MEDIA_SERVER="plex"
      MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' plex 2>/dev/null)
      MEDIA_SERVER_PORT="32400"
    elif docker ps -a -q -f name="jellyfin" | grep -q .; then
      MEDIA_SERVER="jellyfin"
      MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyfin 2>/dev/null)
      MEDIA_SERVER_PORT="8096"
    elif docker ps -a -q -f name="emby" | grep -q .; then
      MEDIA_SERVER="emby"
      MEDIA_SERVER_IMAGE=$(docker inspect --format='{{.Config.Image}}' emby 2>/dev/null)
      MEDIA_SERVER_PORT="8096"
    else
      MEDIA_SERVER="none"
    fi
    
    if docker ps -a -q -f name="overseerr" | grep -q .; then
      REQUEST_MANAGER="overseerr"
      REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' overseerr 2>/dev/null)
      REQUEST_MANAGER_PORT="5055"
    elif docker ps -a -q -f name="jellyseerr" | grep -q .; then
      REQUEST_MANAGER="jellyseerr"
      REQUEST_MANAGER_IMAGE=$(docker inspect --format='{{.Config.Image}}' jellyseerr 2>/dev/null)
      REQUEST_MANAGER_PORT="5055"
    else
      REQUEST_MANAGER="none"
    fi
    
    INSTALL_JACKETT=false
    INSTALL_FLARESOLVERR=false
    
    if docker ps -a -q -f name="jackett" | grep -q .; then
      INSTALL_JACKETT=true
    fi
    
    if docker ps -a -q -f name="flaresolverr" | grep -q .; then
      INSTALL_FLARESOLVERR=true
    fi
    
    generate_docker_compose
  fi
  
  if [ "$USING_PORTAINER" = true ]; then
    echo -e "${YELLOW}IMPORTANT: Portainer detected${NC}"
    echo -e "Please go to Portainer at ${CYAN}https://${SERVER_IP}:9443${NC} and:"
    
    if [ "$IS_DMB_SETUP" = true ]; then
      echo "1. Update your DMB stack with the new Docker Compose configuration"
      echo "2. Redeploy the stack through the Portainer interface"
      echo -e "${CYAN}Here is the updated Docker Compose configuration:${NC}"
      cat "${BASE_DIR}/docker-compose.yml"
    else
      echo "1. Update your existing stack with the new Docker Compose configuration"
      echo "2. Redeploy the stack through the Portainer interface"
      echo -e "${CYAN}Here is the updated Docker Compose configuration:${NC}"
      cat /tmp/docker-compose.yml
    fi
    
    read -p "Press Enter once you've updated and redeployed the stack in Portainer..."
  else
    log "Starting Docker containers..."
    
    if [ "$IS_DMB_SETUP" = true ]; then
      if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        cd "${BASE_DIR}" && docker compose up -d
      else
        warning "DMB Docker Compose file not found. Starting containers individually..."
        docker start DMB plex watchtower 2>/dev/null
      fi
    else
      if [ -f "/tmp/docker-compose.yml" ]; then
        cd /tmp && docker compose -f docker-compose.yml up -d
      else
        warning "Docker Compose file not found. Starting containers individually..."
        docker start zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr watchtower 2>/dev/null
      fi
      
      log "Starting rclone service..."
      systemctl start zurg-rclone.service
      
      test_zurg_connection
    fi
  fi
  
  success "Update completed successfully"
}

repair_installation() {
  header "Repairing Installation"
  
  detect_server_ip
  
  local USING_PORTAINER=false
  if is_portainer_running; then
    log "Detected active Portainer instance"
    USING_PORTAINER=true
  fi
  
  local IS_DMB_SETUP=false
  if docker ps -a -q -f name="DMB" | grep -q .; then
    IS_DMB_SETUP=true
    log "Detected DMB-based setup"
  else
    log "Detected CLI-based setup"
  fi
  
  if ! get_rd_api_key; then
    return 1
  fi
  
  if ! command -v docker &>/dev/null; then
    warning "Docker is not installed. Trying to install..."
    install_docker
  else
    success "Docker is installed"
  fi
  
  if [ "$IS_DMB_SETUP" = true ]; then
    log "Checking DMB Docker containers..."
    if [ "$USING_PORTAINER" = true ]; then
      if ! docker ps -q | grep -q DMB; then
        warning "DMB container is not running."
        echo -e "${YELLOW}IMPORTANT: Portainer detected${NC}"
        echo -e "Please go to Portainer at ${CYAN}https://${SERVER_IP}:9443${NC} and:"
        echo "1. Check your DMB stack status"
        echo "2. Redeploy the stack if necessary"
        read -p "Press Enter when you've verified containers are running in Portainer..."
      else
        success "DMB container appears to be running"
      fi
    else
      if ! docker ps -q -f name="DMB" | grep -q .; then
        if docker ps -a -q -f name="DMB" | grep -q .; then
          warning "DMB container exists but is not running. Starting..."
          docker start DMB
        else
          error "DMB container does not exist"
        fi
      else
        success "DMB container is running"
      fi
      
      if docker ps -a -q -f name="plex" | grep -q .; then
        if ! docker ps -q -f name="plex" | grep -q .; then
          warning "Plex container exists but is not running. Starting..."
          docker start plex
        else
          success "Plex container is running"
        fi
      fi
    fi
    
    success "DMB repair process completed"
  else
    if ! command -v rclone &>/dev/null; then
      warning "rclone is not installed. Trying to install..."
      install_rclone
    else
      success "rclone is installed"
    fi
    
    validate_rclone_setup
    
    log "Checking Docker containers..."
    if [ "$USING_PORTAINER" = true ]; then
      if ! docker ps -q | grep -q zurg || ! docker ps -q | grep -q cli_debrid; then
        warning "Some containers are not running."
        echo -e "${YELLOW}IMPORTANT: Portainer detected${NC}"
        echo -e "Please go to Portainer at ${CYAN}https://${SERVER_IP}:9443${NC} and:"
        echo "1. Check your stack status"
        echo "2. Redeploy the stack if necessary"
        read -p "Press Enter when you've verified containers are running in Portainer..."
      else
        success "Core containers appear to be running"
      fi
    else
      for container in "zurg" "cli_debrid"; do
        if ! docker ps -q -f name="$container" | grep -q .; then
          if docker ps -a -q -f name="$container" | grep -q .; then
            warning "Container $container exists but is not running. Starting..."
            docker start "$container"
          else
            error "Container $container does not exist"
          fi
        else
          success "Container $container is running"
        fi
      done
    fi
    
    log "Checking mount points..."
    if ! mountpoint -q /mnt/zurg; then
      warning "Zurg mount point is not mounted. Restarting rclone service..."
      systemctl restart zurg-rclone.service
      sleep 5
      
      if ! mountpoint -q /mnt/zurg; then
        error "Failed to mount Zurg. Check logs for details."
        systemctl status zurg-rclone.service
      fi
    else
      success "Zurg mount point is mounted correctly"
    fi
    
    test_zurg_connection
    
    success "CLI-based repair process completed"
  fi
}

install_dmb() {
  header "Installing RIVEN/DMB"
  
  detect_server_ip
  
  setup_package_manager
  
  install_prerequisites
  
  if ! install_docker; then
    error "Docker installation failed. Cannot continue."
    return 1
  fi
  
  CURRENT_UID=$(id -u)
  CURRENT_GID=$(id -g)
  
  if ! get_rd_api_key; then
    return 1
  fi
  
  SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  echo -e "Current system timezone: ${CYAN}${SYSTEM_TIMEZONE}${NC}"
  read -p "Enter timezone (leave blank for system timezone): " CUSTOM_TIMEZONE
  TIMEZONE=${CUSTOM_TIMEZONE:-$SYSTEM_TIMEZONE}
  log "Using timezone: ${CYAN}${TIMEZONE}${NC}"
  
  echo "Do you want to deploy a Plex container to work with RIVEN/DMB?"
  read -p "Y/n: " DEPLOY_PLEX_CHOICE
  DEPLOY_PLEX_CHOICE=${DEPLOY_PLEX_CHOICE:-y}
  
  if [[ "${DEPLOY_PLEX_CHOICE,,}" == "y" || "${DEPLOY_PLEX_CHOICE,,}" == "yes" ]]; then
    DEPLOY_PLEX=true
    
    echo -e "${YELLOW}Enter Plex claim token${NC} (from https://www.plex.tv/claim/): "
    read PLEX_CLAIM
    
    success "Plex will be installed with RIVEN/DMB"
  else
    DEPLOY_PLEX=false
    log "Skipping Plex installation"
  fi
  
  echo "Do you want to add Watchtower for automatic container updates?"
  read -p "Y/n: " ADD_WATCHTOWER
  ADD_WATCHTOWER=${ADD_WATCHTOWER:-y}
  
  if [[ "${ADD_WATCHTOWER,,}" == "y" || "${ADD_WATCHTOWER,,}" == "yes" ]]; then
    INSTALL_WATCHTOWER=true
    
    echo "How often do you want to check for updates?"
    echo "1) Daily (recommended)"
    echo "2) Weekly"
    echo "3) Custom schedule (cron format)"
    read -p "Select option [1]: " UPDATE_SCHEDULE_CHOICE
    UPDATE_SCHEDULE_CHOICE=${UPDATE_SCHEDULE_CHOICE:-1}
    
    case "$UPDATE_SCHEDULE_CHOICE" in
      1)
        WATCHTOWER_SCHEDULE="0 3 * * *"
        ;;
      2)
        WATCHTOWER_SCHEDULE="0 3 * * 0"
        ;;
      3)
        echo "Enter custom cron schedule (e.g., '0 3 * * *' for daily at 3:00 AM):"
        read -p "> " WATCHTOWER_SCHEDULE
        if [[ -z "$WATCHTOWER_SCHEDULE" ]]; then
          WATCHTOWER_SCHEDULE="0 3 * * *"
          log "Using default schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC} (daily at 3:00 AM)"
        fi
        ;;
      *)
        WATCHTOWER_SCHEDULE="0 3 * * *"
        ;;
    esac
    
    AUTO_UPDATE_CONTAINERS=("DMB")
    if [ "$DEPLOY_PLEX" = true ]; then
      AUTO_UPDATE_CONTAINERS+=("plex")
    fi
    AUTO_UPDATE_CONTAINERS+=("watchtower")
    
    select_auto_update_containers
    
    setup_discord_notifications
    
    success "Watchtower will be installed with schedule: ${CYAN}${WATCHTOWER_SCHEDULE}${NC}"
  else
    INSTALL_WATCHTOWER=false
    log "Skipping Watchtower installation"
  fi
  
  log "Pulling required Docker images for RIVEN/DMB..."
  pull_docker_image "iampuid0/dmb:latest"
  
  if [ "$DEPLOY_PLEX" = true ]; then
    pull_docker_image "plexinc/pms-docker:latest"
  fi
  
  if [ "$INSTALL_WATCHTOWER" = true ]; then
    pull_docker_image "containrrr/watchtower:latest"
  fi
  
  generate_dmb_docker_compose
  
  deploy_containers
  
  echo
  echo -e "${BOLD}${GREEN}=========================================================================${NC}"
  echo -e "${BOLD}${CYAN}                 RIVEN/DMB Setup Complete!                                ${NC}"
  echo -e "${BOLD}${GREEN}=========================================================================${NC}"
  echo
  echo -e "${BOLD}Service Access Information:${NC}"
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  echo -e "DMB Dashboard:         ${CYAN}http://${SERVER_IP}:3005${NC}"
  echo -e "RIVEN Interface:       ${CYAN}http://${SERVER_IP}:3000${NC}"
  echo -e "pgAdmin 4:             ${CYAN}http://${SERVER_IP}:5050${NC}"
  
  if [ "$DEPLOY_PLEX" = true ]; then
    echo -e "Plex:                  ${CYAN}http://${SERVER_IP}:32400/web${NC}"
  fi
  
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  echo -e "DMB Data Location:     ${CYAN}${BASE_DIR}/DMB${NC}"
  echo -e "Docker Compose File:   ${CYAN}${BASE_DIR}/docker-compose.yml${NC}"
  
  if [ "$DEPLOY_PLEX" = true ]; then
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}IMPORTANT PLEX SETUP INFORMATION:${NC}"
    echo -e "- When adding libraries to Plex, use the ${CYAN}/mnt${NC} folder (not /data)"
    echo -e "- The /data mount point should NOT be added to your Plex libraries"
  fi
  
  if [ "$INSTALL_WATCHTOWER" = true ]; then
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}Automatic Updates:${NC}"
    echo -e "Watchtower is configured to automatically update containers using schedule:"
    echo -e "  ${CYAN}${WATCHTOWER_SCHEDULE}${NC} (cron format)"
    echo -e "Auto-updated containers:"
    for container in "${AUTO_UPDATE_CONTAINERS[@]}"; do
      echo -e "  - ${CYAN}${container}${NC}"
    done
    
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
      echo -e "Discord notifications are enabled for updates"
    fi
  fi
  
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  echo -e "${YELLOW}NOTE: It may take some time for the RIVEN/DMB services to fully initialize${NC}"
  echo -e "${YELLOW}TIP: Check the logs with: docker logs DMB${NC}"
  echo -e "${MAGENTA}==========================================================================${NC}"
  
  echo -e "\n${YELLOW}Would you like to reboot your system now?${NC}"
  read -p "y/N: " REBOOT_CHOICE
  REBOOT_CHOICE=${REBOOT_CHOICE:-n}
  
  if [[ "${REBOOT_CHOICE,,}" == "y" || "${REBOOT_CHOICE,,}" == "yes" ]]; then
    log "Rebooting system..."
    reboot
  else
    log "Reboot skipped. You may need to reboot manually for all changes to take effect."
  fi
  
  return 0
}

install_new_setup() {
  header "New CLI-based Installation"
  
  setup_package_manager
  
  install_prerequisites
  
  setup_directories
  
  if ! install_docker; then
    error "Docker installation failed. Cannot continue."
    return 1
  fi
  
  if ! install_rclone; then
    error "rclone installation failed. Cannot continue."
    return 1
  fi
  
  check_existing_containers
  
  if ! get_rd_api_key; then
    return 1
  fi
  
  select_media_components
  
  setup_configs
  
  log "Pulling required Docker images for CLI-based setup..."
  pull_docker_image "ghcr.io/debridmediamanager/zurg-testing:latest"
  pull_docker_image "$CLI_DEBRID_IMAGE"
  
  if [[ "$MEDIA_SERVER" != "none" ]]; then
    pull_docker_image "$MEDIA_SERVER_IMAGE"
  fi
  
  if [[ "$REQUEST_MANAGER" != "none" ]]; then
    pull_docker_image "$REQUEST_MANAGER_IMAGE"
  fi
  
  if [[ "$INSTALL_JACKETT" == "true" ]]; then
    pull_docker_image "linuxserver/jackett:latest"
  fi
  
  if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
    pull_docker_image "ghcr.io/flaresolverr/flaresolverr:latest"
  fi
  
  if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
    pull_docker_image "containrrr/watchtower:latest"
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
        success "Portainer installed successfully at ${CYAN}https://${SERVER_IP}:9443${NC}"
      else 
        error "Failed to start Portainer"
      fi
    else
      log "Portainer is already running"
    fi
  fi
  
  generate_docker_compose
  
  deploy_containers
  
  log "Enabling and starting rclone service..."
  systemctl daemon-reload
  systemctl enable zurg-rclone.service
  systemctl start zurg-rclone.service
  
  echo "Waiting for Docker containers to initialize..."
  sleep 10
  
  test_zurg_connection
  
  backup_system
  
  display_completion_info
}

display_completion_info() {
  detect_server_ip
  
  local IS_DMB_SETUP=false
  if [[ "$INSTALL_TYPE" == "dmb" ]] || docker ps -a -q -f name="DMB" | grep -q .; then
    IS_DMB_SETUP=true
  fi
  
  echo
  echo -e "${BOLD}${GREEN}=========================================================================${NC}"
  
  if [ "$IS_DMB_SETUP" = true ]; then
    echo -e "${BOLD}${CYAN}                      RIVEN/DMB Setup Complete!                         ${NC}"
    
    echo -e "${BOLD}${GREEN}=========================================================================${NC}"
    echo
    echo -e "${BOLD}Service Access Information:${NC}"
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "DMB Dashboard:         ${CYAN}http://${SERVER_IP}:3005${NC}"
    echo -e "RIVEN Interface:       ${CYAN}http://${SERVER_IP}:3000${NC}"
    echo -e "pgAdmin 4:             ${CYAN}http://${SERVER_IP}:5050${NC}"
    
    if [[ "$DEPLOY_PLEX" == "true" ]] || docker ps -a -q -f name="plex" | grep -q .; then
      echo -e "Plex:                  ${CYAN}http://${SERVER_IP}:32400/web${NC}"
    fi
    
    if [[ "$INSTALL_PORTAINER" == "true" ]] || is_portainer_running; then
      echo -e "Portainer:             ${CYAN}https://${SERVER_IP}:9443${NC}"
    fi
    
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    BASE_DIR="/home/$(id -un)/docker"
    echo -e "DMB Data Location:     ${CYAN}${BASE_DIR}/DMB${NC}"
    echo -e "Docker Compose File:   ${CYAN}${BASE_DIR}/docker-compose.yml${NC}"
    
    if [[ "$DEPLOY_PLEX" == "true" ]] || docker ps -a -q -f name="plex" | grep -q .; then
      echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
      echo -e "${YELLOW}IMPORTANT PLEX SETUP INFORMATION:${NC}"
      echo -e "- When adding libraries to Plex, use the ${CYAN}/mnt${NC} folder (not /data)"
      echo -e "- The /data mount point should NOT be added to your Plex libraries"
    fi
  else
    echo -e "${BOLD}${CYAN}                      CLI-based Setup Complete!                        ${NC}"
    
    echo -e "${BOLD}${GREEN}=========================================================================${NC}"
    echo
    echo -e "${BOLD}Service Access Information:${NC}"
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "Zurg:                  ${CYAN}http://${SERVER_IP}:9999/dav/${NC}"
    echo -e "cli_debrid:            ${CYAN}http://${SERVER_IP}:5000${NC}"
    
    if [[ "$MEDIA_SERVER" == "plex" ]]; then
      echo -e "Plex:                  ${CYAN}http://${SERVER_IP}:32400/web${NC}"
    elif [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
      echo -e "Jellyfin:              ${CYAN}http://${SERVER_IP}:8096${NC}"
    elif [[ "$MEDIA_SERVER" == "emby" ]]; then
      echo -e "Emby:                  ${CYAN}http://${SERVER_IP}:8096${NC}"
    fi
    
    if [[ "$REQUEST_MANAGER" != "none" ]]; then
      echo -e "${REQUEST_MANAGER^}:           ${CYAN}http://${SERVER_IP}:5055${NC}"
    fi
    
    if [[ "$INSTALL_JACKETT" == "true" ]]; then
      echo -e "Jackett:               ${CYAN}http://${SERVER_IP}:9117${NC}"
    fi
    
    if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
      echo -e "FlareSolverr:          ${CYAN}http://${SERVER_IP}:8191${NC}"
    fi
    
    if [[ "$INSTALL_PORTAINER" == "true" ]] || is_portainer_running; then
      echo -e "Portainer:             ${CYAN}https://${SERVER_IP}:9443${NC}"
    fi
    
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "Media Directory:        ${CYAN}/mnt${NC}"
    echo -e "Mounted Content:        ${CYAN}/mnt/zurg${NC}"
    echo -e "Symlinked Directory:    ${CYAN}/mnt/symlinked${NC}"
    echo -e "Configuration Paths:"
    echo -e "  Zurg Config:          ${CYAN}/home/config.yml${NC}"
    echo -e "  Webhook Script:       ${CYAN}/home/plex_update.sh${NC}"
    echo -e "  cli_debrid Config:    ${CYAN}/user/config/settings.json${NC}" 
    echo -e "  cli_debrid Logs:      ${CYAN}/user/logs/debug.log${NC}"
    if [[ "$INSTALL_JACKETT" == "true" ]]; then
      echo -e "  Jackett Config:       ${CYAN}/jackett/config${NC}"
    fi
    echo -e "  Backup Directory:     ${CYAN}/backup${NC}"
  fi
  
  if [[ "$INSTALL_WATCHTOWER" == "true" ]]; then
    echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}Automatic Updates:${NC}"
    echo -e "Watchtower is configured to automatically update containers using schedule:"
    echo -e "  ${CYAN}${WATCHTOWER_SCHEDULE}${NC} (cron format)"
    echo -e "Auto-updated containers:"
    for container in "${AUTO_UPDATE_CONTAINERS[@]}"; do
      echo -e "  - ${CYAN}${container}${NC}"
    done
    
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
      echo -e "Discord notifications are enabled for updates"
    fi
  fi
  
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  
  if [ "$IS_DMB_SETUP" = true ]; then
    echo -e "${YELLOW}NOTE: It may take some time for the RIVEN/DMB services to fully initialize${NC}"
    echo -e "${YELLOW}TIP: Check the logs with: docker logs DMB${NC}"
  else
    echo -e "${YELLOW}NOTE: It may take some time for media to appear. Please be patient.${NC}"
    if [[ "$INSTALL_JACKETT" == "true" ]]; then
      echo -e "${YELLOW}NOTE: Configure Jackett at http://${SERVER_IP}:9117${NC}"
      echo -e "      - Get the API Key from the Jackett web interface"
      echo -e "      - Configure your preferred indexers in Jackett"
      echo -e "      - Use the API Key to connect your media applications to Jackett"
      
      if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
        echo -e "      - In Jackett, go to Settings and set FlareSolverr API URL to: ${CYAN}http://${SERVER_IP}:8191${NC}"
        echo -e "      - This allows Jackett to bypass Cloudflare protection on supported indexers"
      fi
    fi
  fi
  
  echo -e "${MAGENTA}==========================================================================${NC}"
  
  echo -e "\n${YELLOW}Would you like to reboot your system now?${NC}"
  read -p "y/N: " REBOOT_CHOICE
  REBOOT_CHOICE=${REBOOT_CHOICE:-n}
  
  if [[ "${REBOOT_CHOICE,,}" == "y" || "${REBOOT_CHOICE,,}" == "yes" ]]; then
    log "Rebooting system..."
    reboot
  else
    log "Reboot skipped. You may need to reboot manually for all changes to take effect."
  fi
}

select_installation_type() {
  header "Installation Type Selection"
  echo "Choose the type of installation:"
  echo "1) CLI-based (Zurg, cli_debrid, etc. separately)"
  echo "2) RIVEN/DMB All-in-One (Includes RIVEN, Zurg, plex_debrid, etc.)"
  
  read -p "Select option [1]: " INSTALL_TYPE_CHOICE
  INSTALL_TYPE_CHOICE=${INSTALL_TYPE_CHOICE:-1}
  
  if [[ "$INSTALL_TYPE_CHOICE" == "2" ]]; then
    INSTALL_TYPE="dmb"
    success "Selected installation type: ${CYAN}RIVEN/DMB All-in-One${NC}"
  else
    INSTALL_TYPE="individual"
    success "Selected installation type: ${CYAN}CLI-based${NC}"
  fi
}

show_main_menu() {
  while true; do
    header "Debrid Media Stack Setup"
    echo "1) Install a new setup"
    echo "2) Update existing setup"
    echo "3) Backup system configuration"
    echo "4) Restore from backup"
    echo "5) Repair/check installation"
    echo "6) Exit"
   
    read -p "Select an option [1]: " MENU_CHOICE
    MENU_CHOICE=${MENU_CHOICE:-1}
    
    case "$MENU_CHOICE" in
      1)
        select_installation_type
        if [[ "$INSTALL_TYPE" == "dmb" ]]; then
          install_dmb
        else
          install_new_setup
        fi
        ;;
      2)
        update_existing_setup
        ;;
      3)
        backup_system
        ;;
      4)
        restore_system
        ;;
      5)
        repair_installation
        ;;
      6)
        log "Exiting setup script"
        exit 0
        ;;
      *)
        warning "Invalid option. Please select a valid option."
        ;;
    esac
    
    echo
    echo -e "${YELLOW}Returning to main menu in 3 seconds...${NC}"
    sleep 3
  done
}

detect_server_ip

setup_package_manager
show_main_menu
