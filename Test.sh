#!/bin/bash

# Enhanced Debrid Media Stack Setup Script
# 
# Features:
# - Cross-distribution compatibility
# - Backup & restore functionality
# - VPS detection and optimization
# - Improved error handling and validation
# - Advanced rclone deployment checks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if script is run as root
if [[ $(id -u) -ne 0 ]]; then
  error "This script must be run as root. Try: sudo $0"
  exit 1
fi

# Script banner
echo -e "${BOLD}${CYAN}"
echo "┌─────────────────────────────────────────────────────────┐"
echo "│       Enhanced Debrid Media Stack Setup Script          │"
echo "└─────────────────────────────────────────────────────────┘"
echo -e "${NC}"

# Detect system information
header "System Detection"

# OS detection
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

# Architecture detection
ARCHITECTURE=$(uname -m)
if [[ "$ARCHITECTURE" == "aarch64" || "$ARCHITECTURE" == "arm64" ]]; then
  ARCHITECTURE_TYPE="arm64"
else
  ARCHITECTURE_TYPE="amd64"
fi

log "System architecture: ${CYAN}$ARCHITECTURE${NC} (${CYAN}$ARCHITECTURE_TYPE${NC})"

# VPS detection
IS_VPS=false
# Check common VPS indicators
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
  
  # Get available memory
  TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
  log "Available memory: ${CYAN}${TOTAL_MEM}MB${NC}"
  
  # Get available CPU cores
  CPU_CORES=$(nproc)
  log "Available CPU cores: ${CYAN}${CPU_CORES}${NC}"
  
  # VPS-specific optimizations will be applied
else
  log "Detected environment: ${CYAN}Physical or Dedicated Server${NC}"
fi

# Function to check and install package manager commands
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
      # Default to apt for unknown distributions
      warning "Unknown distribution. Attempting to use APT."
      PKG_MANAGER="apt"
      PKG_UPDATE="apt update"
      PKG_INSTALL="apt install -y"
      ;;
  esac
}

# Function to install prerequisites based on the detected OS
install_prerequisites() {
  header "Installing Prerequisites"
  
  log "Updating package lists..."
  eval "$PKG_UPDATE" || warning "Failed to update package lists. Continuing anyway."
  
  # Common packages needed across distributions
  COMMON_PACKAGES="curl wget git"
  
  log "Installing common prerequisites..."
  eval "$PKG_INSTALL $COMMON_PACKAGES" || warning "Failed to install some common packages."
  
  # Check for existing FUSE setup
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
  
  # Distribution-specific packages
  case $OS_ID in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|deepin)
      log "Installing Debian/Ubuntu specific packages..."
      eval "$PKG_INSTALL apt-transport-https ca-certificates gnupg lsb-release" || warning "Failed to install some Debian/Ubuntu specific packages."
      
      # Only try to install FUSE3 if it's not already installed
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
      
      # Only try to install FUSE3 if it's not already installed
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
  
  # Ensure FUSE modules are loaded
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

# Function to install Docker
install_docker() {
  if command -v docker &>/dev/null; then
    success "Docker is already installed"
    return 0
  fi
  
  log "Installing Docker..."
  
  case $OS_ID in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|deepin)
      # Add Docker's official GPG key
      curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      
      # Set up the stable repository
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      # Update package lists
      apt update
      
      # Install Docker
      apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    fedora)
      # Add Docker repository
      dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      
      # Install Docker
      dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    centos|rhel|rocky|almalinux|ol|scientific|amazon)
      # Add Docker repository
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      
      # Install Docker
      dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    arch|manjaro|endeavouros)
      # Install Docker
      pacman -S --noconfirm docker docker-compose
      ;;
    opensuse*|suse|sles)
      # Install Docker
      zypper install -y docker docker-compose
      ;;
    alpine)
      # Install Docker
      apk add docker docker-compose
      ;;
    *)
      error "Unsupported distribution for Docker installation. Please install Docker manually."
      return 1
      ;;
  esac
  
  # Enable and start Docker service
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

# Function to install rclone with fallback mechanisms
install_rclone() {
  if command -v rclone &>/dev/null; then
    local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
    success "rclone ${CYAN}$RCLONE_VERSION${NC} is already installed"
    return 0
  fi
  
  log "Installing rclone..."
  
  # Try the official install script first
  if curl -s https://rclone.org/install.sh | bash; then
    if command -v rclone &>/dev/null; then
      local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
      success "rclone ${CYAN}$RCLONE_VERSION${NC} installed successfully via install script"
      return 0
    fi
  fi
  
  # Fallback to package manager
  warning "rclone install script failed. Trying package manager installation..."
  eval "$PKG_INSTALL rclone"
  
  if command -v rclone &>/dev/null; then
    local RCLONE_VERSION=$(rclone --version | head -n 1 | awk '{print $2}')
    success "rclone ${CYAN}$RCLONE_VERSION${NC} installed successfully via package manager"
    return 0
  fi
  
  # Last resort: manual binary download
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

# Function to create directories and basic structure
setup_directories() {
  log "Creating directory structure..."
  
  mkdir -p /user/logs /user/config /user/db_content
  mkdir -p /mnt/zurg /mnt/symlinked
  mkdir -p /jackett/config
  mkdir -p /root/.config/rclone
  touch /user/logs/debug.log
  
  # Create backup directory
  mkdir -p /backup/config
  
  success "Created directory structure"
}

# Backup functionality
backup_system() {
  header "Creating System Backup"
  
  local BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
  local BACKUP_DIR="/backup/backup_${BACKUP_DATE}"
  
  mkdir -p "$BACKUP_DIR"
  
  log "Backing up configuration files..."
  
  # Backup config files
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
  
  # Backup docker compose file if it exists
  if [ -f /tmp/docker-compose.yml ]; then
    cp /tmp/docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
  fi
  
  # Create backup manifest
  cat > "$BACKUP_DIR/backup_info.txt" <<EOF
Debrid Media Stack Backup
Date: $(date)
System: $OS_PRETTY_NAME
Architecture: $ARCHITECTURE ($ARCHITECTURE_TYPE)
VPS: $IS_VPS

Backed up files:
$(find "$BACKUP_DIR" -type f | grep -v backup_info.txt)
EOF

  # Create archive
  tar -czf "/backup/debrid_backup_${BACKUP_DATE}.tar.gz" -C "/backup" "backup_${BACKUP_DATE}"
  
  # Remove temporary directory
  rm -rf "$BACKUP_DIR"
  
  success "Backup created: ${CYAN}/backup/debrid_backup_${BACKUP_DATE}.tar.gz${NC}"
  
  # List available backups
  echo "Available backups:"
  ls -lh /backup/debrid_backup_*.tar.gz 2>/dev/null || echo "No previous backups found."
}

# Restore functionality
restore_system() {
  header "System Restore"
  
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
  
  # Extract backup
  mkdir -p "$RESTORE_DIR"
  tar -xzf "$SELECTED_BACKUP" -C "$RESTORE_DIR"
  
  local EXTRACTED_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "backup_*" | head -n 1)
  
  if [ -z "$EXTRACTED_DIR" ]; then
    error "Failed to extract backup properly."
    rm -rf "$RESTORE_DIR"
    return 1
  fi
  
  # Stop services and containers
  log "Stopping services..."
  systemctl stop zurg-rclone.service 2>/dev/null
  
  # Stop all relevant containers
  if command -v docker &>/dev/null; then
    log "Stopping Docker containers..."
    docker stop zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr 2>/dev/null
  fi
  
  # Restore files
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
  
  # Clean up
  rm -rf "$RESTORE_DIR"
  
  success "Restore completed successfully"
  log "You may need to restart services and containers manually."
  
  return 0
}

# Function to get Real-Debrid API key
get_rd_api_key() {
  # Check for existing API key in config files
  local EXISTING_KEY=""
  
  # Try to extract from Zurg config.yml
  if [ -f "/home/config.yml" ]; then
    EXISTING_KEY=$(grep -oP 'token: \K.*' /home/config.yml 2>/dev/null)
  fi
  
  # If not found, try cli_debrid settings.json
  if [ -z "$EXISTING_KEY" ] && [ -f "/user/config/settings.json" ]; then
    EXISTING_KEY=$(grep -oP '"api_key": "\K[^"]*' /user/config/settings.json 2>/dev/null)
  fi
  
  # If an existing key was found, ask if user wants to use it
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
  
  # No existing key or user wants to enter a new one
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
  
  # Get server IP address
  IP=""
  read -p "Enter server IP (blank for auto-detect): " IP
  if [[ -z "$IP" ]]; then
    # Try multiple methods to detect IP
    if command -v ip &>/dev/null; then
      IP=$(ip route get 1 | awk '{print $(NF-2);exit}' 2>/dev/null)
    fi
    
    if [[ -z "$IP" ]] && command -v hostname &>/dev/null; then
      IP=$(hostname -I | awk '{print $1}' 2>/dev/null)
    fi
    
    if [[ -z "$IP" ]] && command -v ifconfig &>/dev/null; then
      IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    fi
    
    success "Detected IP: ${CYAN}$IP${NC}"
  fi
  
  if [[ ! "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    warning "Invalid IP format. Using localhost."
    IP="127.0.0.1"
  fi
  
  log "Using server IP: ${CYAN}$IP${NC}"
  
  # Get timezone
  SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  echo -e "Current system timezone: ${CYAN}${SYSTEM_TIMEZONE}${NC}"
  read -p "Enter timezone (leave blank for system timezone): " CUSTOM_TIMEZONE
  TIMEZONE=${CUSTOM_TIMEZONE:-$SYSTEM_TIMEZONE}
  log "Using timezone: ${CYAN}${TIMEZONE}${NC}"
  
  # Configure update script
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
  
  # Configure Zurg
  # VPS-specific optimizations if needed
  local CONCURRENT_WORKERS=64
  local CHECK_INTERVAL=10
  
  if [ "$IS_VPS" = true ] && [ $TOTAL_MEM -lt 2048 ]; then
    # Lower resource settings for VPS with less than 2GB RAM
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
  
  # Configure cli_debrid
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
  
  # Configure rclone
  cat > "/root/.config/rclone/rclone.conf" <<EOF
[zurg-wd]
type = webdav
url = http://127.0.0.1:9999/dav/
vendor = other
pacer_min_sleep = 10ms
pacer_burst = 0
EOF
  
  # Create systemd service for rclone with appropriate FUSE version
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

  # Add FUSE3-specific options if available
  if [ "$FUSE3_INSTALLED" = true ]; then
    cat >> "/etc/systemd/system/zurg-rclone.service" <<EOF
  --async-read=true \\
  --use-mmap \\
  --fuse-flag=sync_read \\
EOF
  fi

  # Complete the service file
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
  
  # Apply VPS-specific optimizations to rclone if needed
  if [ "$IS_VPS" = true ] && [ $TOTAL_MEM -lt 2048 ]; then
    log "Applying VPS-optimized rclone settings..."
    
    # Replace the existing ExecStart with optimized settings
    sed -i 's/--vfs-cache-max-size=2G/--vfs-cache-max-size=512M/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--buffer-size 64M/--buffer-size 32M/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--transfers 16/--transfers 8/g' /etc/systemd/system/zurg-rclone.service
    sed -i 's/--checkers 16/--checkers 8/g' /etc/systemd/system/zurg-rclone.service
  fi
  
  success "Configuration files created"
}

# Container management functions
check_existing_containers() {
  if command -v docker &>/dev/null; then
    log "Checking for existing containers..."
    
    local containers=("zurg" "cli_debrid" "plex" "jellyfin" "emby" "overseerr" "jellyseerr" "jackett" "flaresolverr")
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

# Function to pull Docker images with better error handling
pull_docker_image() {
  local image="$1"
  local max_retries=5
  local retry_delay=5
  
  if docker inspect "$image" &>/dev/null; then
    log "Image '${CYAN}$image${NC}' exists. Skipping pull."
    return 0
  fi
  
  log "Pulling Docker image: ${CYAN}$image${NC}"
  
  for ((i=1; i<=max_retries; i++)); do
    if docker pull "$image"; then
      success "Successfully pulled image: ${CYAN}$image${NC}"
      return 0
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

# Function to validate rclone setup
validate_rclone_setup() {
  log "Validating rclone configuration..."
  
  # Check if rclone config exists
  if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    error "rclone configuration file is missing"
    return 1
  fi
  
  # Check if rclone service exists
  if [ ! -f "/etc/systemd/system/zurg-rclone.service" ]; then
    error "rclone service file is missing"
    return 1
  fi
  
  # Check if rclone service is enabled
  if ! systemctl is-enabled zurg-rclone.service &>/dev/null; then
    warning "rclone service is not enabled. Enabling now..."
    systemctl enable zurg-rclone.service
  fi
  
  # Test rclone configuration
  log "Testing rclone configuration..."
  if rclone lsd zurg-wd: --verbose 2>&1 | grep -q "Failed to create"; then
    warning "rclone test failed - this is expected if Zurg is not running yet"
  else
    success "rclone configuration validated"
  fi
  
  return 0
}

# Enhanced test and diagnostic function for Zurg connectivity
test_zurg_connection() {
  log "Testing Zurg connectivity..."
  
  # Check if Zurg container is running
  if ! docker ps | grep -q zurg; then
    warning "Zurg container is not running. Start Docker containers first."
    return 1
  fi
  
  # Check if Zurg API is responding
  if ! curl -s http://localhost:9999/ping >/dev/null; then
    warning "Zurg API is not responding. Checking container logs..."
    docker logs zurg --tail 20
    return 1
  fi
  
  # Test rclone connection to Zurg
  log "Testing rclone connection to Zurg..."
  
  # Try to list directories
  if rclone lsd zurg-wd: --verbose 2>&1; then
    success "Zurg connectivity test passed successfully"
    return 0
  else
    warning "rclone connection test failed. Restarting services..."
    
    # Restart Zurg container
    docker restart zurg
    sleep 5
    
    # Restart rclone service
    systemctl restart zurg-rclone.service
    sleep 5
    
    # Try again
    if rclone lsd zurg-wd: --verbose 2>&1; then
      success "Zurg connectivity successful after restart"
      return 0
    else
      error "Zurg connectivity test failed even after restart"
      
      # Diagnostic information
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

# Main menu function
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
        install_new_setup
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
    
    # Ask if user wants to continue with the menu or exit
    echo
    read -p "Return to main menu? (y/N): " CONTINUE_MENU
    CONTINUE_MENU=${CONTINUE_MENU:-n}
    
    if [[ "${CONTINUE_MENU,,}" != "y" && "${CONTINUE_MENU,,}" != "yes" ]]; then
      log "Exiting setup script"
      exit 0
    fi
  done
}

# Install new setup
install_new_setup() {
  header "New Installation"
  
  # Setup package manager
  setup_package_manager
  
  # Install prerequisites
  install_prerequisites
  
  # Create directory structure
  setup_directories
  
  # Install Docker
  if ! install_docker; then
    error "Docker installation failed. Cannot continue."
    return 1
  fi
  
  # Install rclone
  if ! install_rclone; then
    error "rclone installation failed. Cannot continue."
    return 1
  fi
  
  # Check for existing containers
  check_existing_containers
  
  # Media server selection
  select_media_components
  
  # Setup config files
  setup_configs
  
  # Pull Docker images
  pull_required_images
  
  # Generate Docker compose file
  generate_docker_compose
  
  # Deploy containers
  deploy_containers
  
  # Enable and start rclone service
  log "Enabling and starting rclone service..."
  systemctl daemon-reload
  systemctl enable zurg-rclone.service
  systemctl start zurg-rclone.service
  
  # Wait for containers to start
  echo "Waiting for Docker containers to initialize..."
  sleep 10
  
  # Test connection
  test_zurg_connection
  
  # Create a backup of the fresh installation
  backup_system
  
  # Display completion message
  display_completion_info
}

# Update existing setup
update_existing_setup() {
  header "Update Existing Setup"
  
  # Get Real-Debrid API key
  if ! get_rd_api_key; then
    return 1
  fi
  
  # Backup current setup
  backup_system
  
  # Check if Zurg container exists
  if ! docker ps -a -q -f name="zurg" | grep -q .; then
    error "Zurg container not found. This doesn't appear to be an existing setup."
    return 1
  fi
  
  # Stop services
  log "Stopping services..."
  systemctl stop zurg-rclone.service 2>/dev/null
  
  # Stop Docker containers
  log "Stopping Docker containers..."
  docker stop zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr 2>/dev/null
  
  # Update Docker images
  log "Updating Docker images..."
  docker pull ghcr.io/debridmediamanager/zurg-testing:latest
  
  # Get the currently used CLI image
  CLI_CURRENT_IMAGE=$(docker inspect --format='{{.Config.Image}}' cli_debrid 2>/dev/null)
  if [ -n "$CLI_CURRENT_IMAGE" ]; then
    docker pull "$CLI_CURRENT_IMAGE"
  else
    warning "Could not determine current CLI image. User selection required."
    select_cli_image
  fi
  
  # Update other containers if they exist
  for container in "plex" "jellyfin" "emby" "overseerr" "jellyseerr" "jackett" "flaresolverr"; do
    if docker ps -a -q -f name="$container" | grep -q .; then
      CONTAINER_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
      if [ -n "$CONTAINER_IMAGE" ]; then
        log "Updating $container image..."
        docker pull "$CONTAINER_IMAGE"
      fi
    fi
  done
  
  # Start containers again
  log "Starting Docker containers..."
  if [ -f "/tmp/docker-compose.yml" ]; then
    cd /tmp && docker compose -f docker-compose.yml up -d
  else
    warning "Docker Compose file not found. Starting containers individually..."
    docker start zurg cli_debrid plex jellyfin emby overseerr jellyseerr jackett flaresolverr 2>/dev/null
  fi
  
  # Start rclone service
  log "Starting rclone service..."
  systemctl start zurg-rclone.service
  
  # Test connection
  test_zurg_connection
  
  success "Update completed successfully"
}

# Repair installation
repair_installation() {
  header "Repairing Installation"
  
  # Get Real-Debrid API key
  if ! get_rd_api_key; then
    return 1
  fi
  
  # Check Docker
  if ! command -v docker &>/dev/null; then
    warning "Docker is not installed. Trying to install..."
    install_docker
  else
    success "Docker is installed"
  fi
  
  # Check rclone
  if ! command -v rclone &>/dev/null; then
    warning "rclone is not installed. Trying to install..."
    install_rclone
  else
    success "rclone is installed"
  fi
  
  # Validate rclone setup
  validate_rclone_setup
  
  # Check Docker containers
  log "Checking Docker containers..."
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
  
  # Check mount points
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
  
  # Test Zurg connection
  test_zurg_connection
  
  success "Repair process completed"
}

# Media component selection functions
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

select_media_components() {
  # Select CLI image
  select_cli_image
  
  # Media server selection
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
  
  # Request manager selection
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
  
  # Torrent indexer setup
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
  
  # Docker management
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
}

pull_required_images() {
  header "Pulling Docker Images"
  log "Pulling required Docker images..."
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
  
  if [[ "$INSTALL_PORTAINER" == "true" ]]; then
    if ! docker ps -q -f name=portainer | grep -q .; then
      log "Installing Portainer..."
      pull_docker_image "portainer/portainer-ce:latest"
      docker volume create portainer_data
      docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data portainer/portainer-ce:latest
      
      if docker ps -q -f name=portainer | grep -q .; then
        success "Portainer installed successfully at ${CYAN}https://${IP}:9443${NC}"
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
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9999/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

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
    depends_on:
      zurg:
        condition: service_healthy
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
    depends_on:
      cli_debrid:
        condition: service_started
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
    depends_on:
      - ${MEDIA_SERVER}
EOF
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
      - TZ=${TIMEZONE}
      - AUTO_UPDATE=true
EOF
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
      - TZ=${TIMEZONE}
      - CAPTCHA_SOLVER=none
EOF
  fi
  
  success "Docker Compose file generated"
  
  echo -e "\n${CYAN}${BOLD}Docker Compose Configuration:${NC}"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
  cat "$DOCKER_COMPOSE_FILE"
  echo -e "${MAGENTA}-----------------------------------------------------------------------${NC}"
}

deploy_containers() {
  header "Deploying Containers"
  if [[ "$INSTALL_PORTAINER" == "true" ]]; then
    echo -e "Please go to Portainer in your web browser: ${CYAN}https://${IP}:9443${NC}"
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

display_completion_info() {
  echo
  echo -e "${BOLD}${GREEN}=========================================================================${NC}"
  echo -e "${BOLD}${CYAN}                      Setup Complete!                                   ${NC}"
  echo -e "${BOLD}${GREEN}=========================================================================${NC}"
  echo
  echo -e "${BOLD}Service Access Information:${NC}"
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  echo -e "Zurg:                  ${CYAN}http://${IP}:9999/dav/${NC}"
  echo -e "cli_debrid:            ${CYAN}http://${IP}:5000${NC}"
  
  if [[ "$MEDIA_SERVER" == "plex" ]]; then
    echo -e "Plex:                  ${CYAN}http://${IP}:32400/web${NC}"
  elif [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo -e "Jellyfin:              ${CYAN}http://${IP}:8096${NC}"
  elif [[ "$MEDIA_SERVER" == "emby" ]]; then
    echo -e "Emby:                  ${CYAN}http://${IP}:8096${NC}"
  fi
  
  if [[ "$REQUEST_MANAGER" != "none" ]]; then
    echo -e "${REQUEST_MANAGER^}:           ${CYAN}http://${IP}:5055${NC}"
  fi
  
  if [[ "$INSTALL_JACKETT" == "true" ]]; then
    echo -e "Jackett:               ${CYAN}http://${IP}:9117${NC}"
  fi
  
  if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
    echo -e "FlareSolverr:          ${CYAN}http://${IP}:8191${NC}"
  fi
  
  if [[ "$INSTALL_PORTAINER" == "true" ]]; then
    echo -e "Portainer:             ${CYAN}https://${IP}:9443${NC}"
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
  echo -e "${MAGENTA}-------------------------------------------------------------------------${NC}"
  echo -e "${YELLOW}NOTE: It may take some time for media to appear. Please be patient.${NC}"
  if [[ "$INSTALL_JACKETT" == "true" ]]; then
    echo -e "${YELLOW}NOTE: Configure Jackett at http://${IP}:9117${NC}"
    echo -e "      - Get the API Key from the Jackett web interface"
    echo -e "      - Configure your preferred indexers in Jackett"
    echo -e "      - Use the API Key to connect your media applications to Jackett"
    
    if [[ "$INSTALL_FLARESOLVERR" == "true" ]]; then
      echo -e "      - In Jackett, go to Settings and set FlareSolverr API URL to: ${CYAN}http://${IP}:8191${NC}"
      echo -e "      - This allows Jackett to bypass Cloudflare protection on supported indexers"
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

# Execute main function
show_main_menu
