# Debrid Media Stack Setup Script

This script automates the setup of a complete media streaming stack using Real-Debrid, featuring Zurg, cli_debrid, and your choice of media servers and request managers.

## Features

- **Architecture Detection**: Automatically detects ARM64 or AMD64 systems and selects appropriate images
- **Multiple Media Servers**: Choose between Plex, Jellyfin, Emby,
- **Request Manager Integration**: Optional Overseerr or Jellyseerr installation
- **Torrent Indexing**: Optional Jackett with FlareSolverr for Cloudflare bypass
- **Docker Management**: Optional Portainer installation
- **Full Configuration**: All components are automatically configured to work together

## Installation

Run the following command to download, make executable, and execute the script in one go:
sudo curl -sO https://raw.githubusercontent.com/delete2020/cli_debrid-setup-/main/setup.sh && sudo chmod +x setup.sh && sudo ./setup.sh

The script will guide you through selecting and installing:

Zurg: Bridge between Real-Debrid and your media server
cli_debrid: Web interface for managing Real-Debrid content
Media Server (optional): Plex, Jellyfin, or Emby
Request Manager (optional): Overseerr or Jellyseerr
Jackett (optional): Torrent indexer integration
FlareSolverr (optional): Helps access Cloudflare-protected sites
Portainer (optional): Docker management UI

Requirements

Debian/Ubuntu-based Linux system
Root access
Internet connection
Real-Debrid account and API key

After Installation
After successful installation, you'll be able to access:

Zurg WebDAV interface at http://your-ip:9999/dav/
cli_debrid UI at http://your-ip:5000
Your chosen media server (Plex/Jellyfin/Emby)
Your chosen request manager (Overseerr/Jellyseerr)
Jackett at http://your-ip:9117 (if installed)
FlareSolverr at http://your-ip:8191 (if installed)
Portainer at https://your-ip:9443 (if installed)

Configuration Directories
The script sets up the following directory structure:

/mnt/zurg: Mount point for Real-Debrid content
/mnt/symlinked: Directory for symlinked content
/home/config.yml: Zurg configuration
/user/config/settings.json: cli_debrid configuration
/jackett/config: Jackett configuration (if installed)

Troubleshooting
If you encounter issues:

Check if Zurg container is running: docker ps | grep zurg
Check Zurg logs: docker logs zurg
Try restarting rclone manually: systemctl restart zurg-rclone
