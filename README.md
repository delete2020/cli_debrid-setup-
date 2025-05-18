# Debrid Media Stack Setup Script

A comprehensive solution for deploying and managing debrid-based media servers on Linux systems. This script provides a user-friendly way to set up a complete media stack with Real-Debrid integration.

## Key Features

### Cross-distribution Compatibility
Works seamlessly across multiple Linux distributions including:
- Debian & Ubuntu-based systems
- RHEL, Fedora, CentOS, Rocky Linux
- Arch, Manjaro, EndeavourOS
- openSUSE & SUSE Linux
- Alpine Linux
- And more!

### Smart Detection and Optimization
- **Multi-Architecture Support**: Automatic detection of AMD64 and ARM64 architectures
- **Auto IP Detection**: Automatically finds your server's IP address
- **FUSE Optimization**: Detects and implements the best available FUSE version for performance
- **Timezone Configuration**: Automatically detects and allows custom timezone settings
- **Discord Notifications**: Optional webhook integration for update notifications

### Installation Options
Two flexible installation paths are available:

1. **Individual Containers Setup**
   - Traditional setup with separate components
   - Greater customization of individual services
   - Fine-grained control over each component

2. **DMB All-in-One Solution**
   - Integrated Debrid Media Bridge with:
     - RIVEN frontend & backend
     - plex_debrid integration
     - Zurg bridge with advanced configuration
     - cli_debrid integration with web UI
     - Streamlined user interface
     - Centralized management

### System Management
- **Backup & Restore Functionality**: Create and restore complete system backups
- **VPS Detection & Optimization**: Automatically optimizes settings for limited resource environments
- **Improved Error Handling**: Robust validation and recovery mechanisms
- **Automatic Updates**: Container updates via Watchtower integration
- **Portainer Support**: Proper detection and integration with Portainer

## Installation

Run this command to download and execute the script:

```bash
sudo curl -sO https://raw.githubusercontent.com/delete2020/cli_debrid-setup-/main/setup.sh && sudo chmod +x setup.sh && sudo ./setup.sh
```

## Components

### Core Components

- **Zurg**: Bridge between Real-Debrid and your media server
  - WebDAV interface for media files
  - Automatic folder organization
  - Real-time content updates

- **cli_debrid**: Management interface for Real-Debrid content
  - Web UI for browsing Real-Debrid files
  - Instant access to torrents and downloads
  - Streaming capabilities

### Media Server Options

- **Plex**: Full-featured media server with streaming to multiple devices
- **Jellyfin**: Open-source media solution with no premium limitations
- **Emby**: Flexible media server with advanced customization

### Request Manager Options

- **Overseerr**: Media request system optimized for Plex
- **Jellyseerr**: Fork of Overseerr designed to work with Jellyfin

### Supplementary Tools

- **Jackett**: Torrent indexer proxy
- **FlareSolverr**: Cloudflare protection bypass
- **Portainer**: Docker management UI
- **Watchtower**: Automatic container updates

## System Requirements

- Linux system (wide distribution support)
- Root access
- Internet connection
- Real-Debrid account and API key
- Minimum 1GB RAM (2GB+ recommended)
- 10GB+ available storage space

## Post-Installation Access

After successful installation, you'll access your services at:

| Service | URL | Description |
|---------|-----|-------------|
| Zurg WebDAV | `http://your-ip:9999/dav/` | Mount point for media files |
| cli_debrid UI | `http://your-ip:5000` | Web interface for RD management |
| Plex | `http://your-ip:32400/web` | Plex media server interface |
| Jellyfin | `http://your-ip:8096` | Jellyfin media server interface |
| Emby | `http://your-ip:8096` | Emby media server interface |
| Overseerr/Jellyseerr | `http://your-ip:5055` | Request manager interface |
| Jackett | `http://your-ip:9117` | Torrent indexer configuration |
| FlareSolverr | `http://your-ip:8191` | Cloudflare bypass service |
| Portainer | `https://your-ip:9443` | Docker management interface |
| DMB Frontend | `http://your-ip:3005` | DMB management interface |
| Riven Frontend | `http://your-ip:3000` | Riven interface |
| cli_debrid UI (DMB) | `http://your-ip:5000` | Web interface for RD management (within DMB) |

## Maintenance Functions

The script includes enhanced maintenance capabilities:

- **Create System Backups**: Save your entire configuration for later recovery
- **Restore from Backups**: Easily restore your setup from previous backups
- **Repair Installations**: Automatically fix common issues
- **Update Existing Setups**: Keep your installation up-to-date with the latest improvements
- **VPS-specific Optimizations**: Special settings for limited resource environments

## Backup System

The built-in backup system preserves all critical configuration files:

- Container configurations and settings
- Docker Compose files
- API keys and service connections
- Mount settings and systemd service files
- Custom user configurations

Backups are stored in the `/backup` directory and can be easily restored through the script's menu.

## Migration Path

The script allows for flexible deployment options:

- Start with individual containers and later migrate to DMB
- Perform complete system backups before major changes
- Update from older setups to newer configurations
- Repair installations while preserving user data

## Performance Optimization

The script includes several performance optimizations:

- **VPS-specific Settings**: Reduced resource usage on limited hardware
- **FUSE3 Implementation**: Modern, faster filesystem mounting when available
- **Caching Optimizations**: Improved media loading speed through smart caching
- **Concurrent Workers**: Configurable parallel processing based on available resources
- **Multi-thread Transfers**: Optimized file transfers for better throughput

## Logging and Monitoring

Debug and monitoring features include:

- **Centralized Logs**: All services log to accessible locations
- **Startup Verification**: Automatic checks ensure services are running correctly
- **Mount Monitoring**: Continuous checking of mount points and reconnection if needed

## Troubleshooting

If you encounter issues:

- **Check container status**: `docker ps | grep container_name`
- **View logs**: `docker logs container_name`
- **Restart services**: `systemctl restart zurg-rclone.service`
- **Use the built-in repair function** from the main menu
- **Check mount points**: Verify `/mnt/zurg` is properly mounted

## Advanced Configuration

For advanced users, the script creates configuration files that can be manually edited:

- **Zurg Configuration**: `/home/config.yml`
- **cli_debrid Settings**: `/user/config/settings.json`
- **Rclone Configuration**: `/root/.config/rclone/rclone.conf`
- **Mount Service**: `/etc/systemd/system/zurg-rclone.service`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the MIT License.

## Community Resources

- For issues and feature requests, please use the GitHub Issues page
