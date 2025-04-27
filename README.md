## Debrid Media Stack Setup Script

Cross-distribution Compatibility: Works across Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, and more
Backup & Restore Functionality: Create and restore complete system backups
VPS Detection & Optimization: Automatically optimizes settings for VPS environments
Improved Error Handling: Robust validation and recovery mechanisms
Advanced rclone Deployment: Enhanced FUSE integration with fallback options
Automatic Updates: Container updates via Watchtower integration
Portainer Support: Proper detection and integration with Portainer
DMB All-in-One Option: New option to install Debrid Media Bridge with integrated components

Installation Options
Two installation paths are now available:

Individual Containers: Traditional setup with separate components
DMB All-in-One: Integrated Debrid Media Bridge including Riven, plex_debrid, Zurg, etc.

Installation
Run this command to download and execute the script:
bashsudo curl -sO https://raw.githubusercontent.com/delete2020/cli_debrid-setup-/main/setup.sh && sudo chmod +x setup.sh && sudo ./setup.sh
Components
Core Components:

Zurg: Bridge between Real-Debrid and your media server
cli_debrid: Management interface for Real-Debrid content

Media Server Options:

Plex
Jellyfin
Emby

Request Manager Options:

Overseerr (best with Plex)
Jellyseerr (best with Jellyfin)

Supplementary Tools:

Jackett: Torrent indexer integration
FlareSolverr: Cloudflare protection bypass
Portainer: Docker management UI
Watchtower: Automatic container updates

System Requirements

Linux system (wide distribution support)
Root access
Internet connection
Real-Debrid account and API key

Post-Installation Access
After successful installation, you'll access your services at:

Zurg WebDAV: http://your-ip:9999/dav/
cli_debrid UI: http://your-ip:5000
Media server (Plex/Jellyfin/Emby): Respective ports
Request manager: http://your-ip:5055
Jackett: http://your-ip:9117
FlareSolverr: http://your-ip:8191
Portainer: https://your-ip:9443
DMB Frontend (if selected): http://your-ip:3005
Riven Frontend (if DMB selected): http://your-ip:3000

Maintenance Functions
The script now includes enhanced maintenance capabilities:

Create system backups
Restore from previous backups
Repair installations
Update existing setups
VPS-specific optimizations

Troubleshooting
If you encounter issues:

Check container status: docker ps | grep container_name
View logs: docker logs container_name
Restart services: systemctl restart zurg-rclone.service
Use the built-in repair function from the main menu
