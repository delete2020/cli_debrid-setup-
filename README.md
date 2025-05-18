# 🚀 Debrid Media Stack Setup Script

A powerful script to deploy and manage the full **Debrid Media Stack**, offering cross-platform support, automatic optimizations, backups, and seamless integration of media tools.

---

## 🌐 Key Features

* **✅ Cross-distribution Compatibility**
  Works across Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, Alpine, and more.

* **🙟 Backup & Restore**
  Create and restore complete system backups.

* **📦 VPS Detection & Optimization**
  Automatically optimizes settings for VPS environments.

* **🔒 Improved Error Handling**
  Robust validation and recovery mechanisms.

* **📂 Advanced rclone Deployment**
  Enhanced FUSE integration with fallback support.

* **🔄 Automatic Updates**
  Watchtower-enabled container updates.

* **🧽 Portainer Integration**
  Detects and integrates with Portainer seamlessly.

* **🧹 DMB All-in-One Installation**
  Simplified setup of Debrid Media Bridge with integrated components.

---

## ⚙️ Installation Options

You can install the stack using one of two methods:

### 1. **Individual Containers**

Deploy each component separately for modular control.

### 2. **DMB All-in-One**

A bundled install of Debrid Media Bridge including:

* Riven
* cli_debrid
* plex_debrid
* Zurg
* and more

---

## 📅 Installation

Run the following command to download and execute the script:

```bash
sudo curl -sO https://raw.githubusercontent.com/delete2020/cli_debrid-setup-/main/setup.sh && \
sudo chmod +x setup.sh && \
sudo ./setup.sh
```

---

## 🧱 Components

### 🔧 Core Tools

* **Zurg** – Bridge between Real-Debrid and your media server
* **cli\_debrid** – Interface to manage Real-Debrid content

### 📺 Media Servers

* Plex
* Jellyfin
* Emby

### 📬 Request Managers

* Overseerr *(best for Plex)*
* Jellyseerr *(best for Jellyfin)*

### 🛠️ Supplementary Tools

* **Jackett** – Torrent indexer integration
* **FlareSolverr** – Cloudflare bypass
* **Portainer** – Docker management UI
* **Watchtower** – Automated container updates

---

## 💻 System Requirements

* Linux system (Debian/Ubuntu/Arch/Fedora/etc.)
* Root access
* Internet connection
* Real-Debrid account and API key

---

## 🌐 Post-Installation Access

| Service                | URL                                   |
| ---------------------- | ------------------------------------- |
| Zurg WebDAV            | `http://your-ip:9999/dav/`            |
| cli\_debrid UI         | `http://your-ip:5000`                 |
| Plex / Jellyfin / Emby | Respective ports                      |
| Request Manager        | `http://your-ip:5055`                 |
| Jackett                | `http://your-ip:9117`                 |
| FlareSolverr           | `http://your-ip:8191`                 |
| Portainer              | `https://your-ip:9443`                |
| DMB Frontend           | `http://your-ip:3005` *(if selected)* |
| Riven Frontend         | `http://your-ip:3000` *(if selected)* |

---

## 🩹 Maintenance Functions

Built-in functionality to:

* ✅ Create full system backups
* ♻️ Restore from existing backups
* 💪 Repair installations
* 🔄 Update existing setups
* ⚡ Apply VPS-specific optimizations

---

## 🪯 Troubleshooting

| Action                 | Command                                 |
| ---------------------- | --------------------------------------- |
| Check container status | `docker ps \| grep <container_name>`    |
| View logs              | `docker logs <container_name>`          |
| Restart a service      | `systemctl restart zurg-rclone.service` |
| Run repair function    | Use the script’s main menu              |
