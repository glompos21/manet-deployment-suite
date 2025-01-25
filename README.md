# Mobile Ad-Hoc Network (MANET) Deployment Suite

## Table of Contents
- [Introduction](#introduction)
- [What is a MANET?](#what-is-a-manet)
- [Why Use This Guide?](#why-use-this-guide)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Node Configuration Types](#node-configuration-types)
- [Service Operation](#service-operation)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)
- [Security Considerations](#security-considerations)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Advanced Topics](#advanced-topics)
- [References](#references)

## Introduction

The B.A.T.M.A.N. advanced (batman-adv) is a layer 2 routing protocol implemented as a Linux kernel module, designed specifically for mobile ad-hoc networks. This repository provides a comprehensive suite of tools and configurations to simplify the deployment and management of batman-adv networks.

### Key Features
- Automatic gateway detection and configuration
- Seamless failover between gateways
- Support for multiple network topologies
- Integrated monitoring and maintenance tools
- Secure by default configuration

## What is a MANET?

A Mobile Ad-Hoc Network (MANET) is a decentralized type of wireless network that doesn't rely on pre-existing infrastructure. Each node participates in routing by forwarding data to other nodes, and the determination of which nodes forward data is made dynamically based on network connectivity.

Key characteristics:
- Self-forming and self-healing
- No central infrastructure required
- Dynamic routing based on network conditions
- Peer-to-peer communication between nodes

Common applications include:
- Emergency response and disaster recovery
- Military tactical networks
- Underground mining operations
- Construction site communications
- Temporary event networks
- Remote area connectivity

## Requirements

### Hardware Requirements
- **Minimum**:
  - Single-board computer (Raspberry Pi, Libre Computer, etc.)
  - WiFi adapter supporting ad-hoc mode
  - Power supply
  - SD card/storage

### Software Requirements
- Debian-based Linux distribution (Debian, Ubuntu, Raspberry Pi OS)
- Required packages:
  ```bash
  sudo apt install batctl iw wireless-tools net-tools bridge-utils iptables dnsmasq hostapd arping arp-scan
  ```

### Network Planning
Before deployment, consider:
1. **Network Size**
   - Number of nodes
   - Expected coverage area
   - User density

2. **Topology**
   - Simple mesh (all nodes equal)
   - Gateway mesh (internet access)
   - Access point mesh (client access)
   - Hybrid setup

3. **IP Addressing**
   - Mesh network range (e.g., 10.0.0.0/24)
   - AP network range (e.g., 10.20.0.0/24)
   - WAN configuration

## Installation

### 1. System Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y git batctl iw wireless-tools net-tools bridge-utils iptables dnsmasq hostapd arping

# Clone repository
git clone https://github.com/ifHoncho/mobile-ad-hoc-deployment-suite.git
cd manet-deployment-suite

# Install configuration files
sudo ./setup.sh
```

### 2. Initial Configuration
1. Create configuration directory:
   ```bash
   sudo mkdir -p /etc/mesh-network
   ```

2. Copy and edit configuration:
   ```bash
   sudo cp config_tools/mesh-config.conf /etc/mesh-network/mesh-config.conf
   sudo nano /etc/mesh-network/mesh-config.conf
   ```

### 3. Service Installation
```bash
# Install service files
sudo cp config_tools/mesh-network.service /etc/systemd/system/
sudo cp config_tools/mesh-network.sh /usr/sbin/
sudo cp config_tools/mesh-network-stop.sh /usr/sbin/

# Set permissions
sudo chmod +x /usr/sbin/mesh-network.sh
sudo chmod +x /usr/sbin/mesh-network-stop.sh

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable mesh-network.service
sudo systemctl start mesh-network.service
```

## Configuration

### Basic Configuration
Minimum required settings in `/etc/mesh-network/mesh-config.conf`:

```bash
# Interface Configuration
MESH_INTERFACE=wlan0          # Primary mesh interface
NODE_IP=10.0.0.x             # Node IP (must be valid IPv4 format)
MESH_NETMASK=24              # Network mask (e.g., 16 for /16)
GATEWAY_IP=10.0.0.1          # Gateway IP (must be valid IPv4 format)

# Mesh Parameters
MESH_MODE=ad-hoc             # Must be set to ad-hoc
MESH_ESSID=mesh-network      # Network name (same for all nodes)
MESH_CHANNEL=1               # WiFi channel (1, 6, or 11)
MESH_CELL_ID=02:12:34:56:78:9A  # Cell ID (same for all nodes)

# Batman-adv Settings
BATMAN_GW_MODE=client        # client, server, or off
BATMAN_ROUTING_ALGORITHM=BATMAN_V  # Must be BATMAN_IV or BATMAN_V
```

### Advanced Configuration
Optional settings for enhanced functionality:

```bash
# Additional Interface Options
AP_IFACE=wlan1              # Access point interface
WAN_IFACE=wlan2             # Wireless WAN interface
ETH_WAN=eth0                # Ethernet WAN interface
ETH_LAN=eth1                # Ethernet LAN interface

# Performance Tuning
MESH_MTU=1500               # MTU size for mesh interface
BATMAN_ORIG_INTERVAL=1000   # Originator interval (ms)
BATMAN_HOP_PENALTY=30       # Hop penalty
BATMAN_LOG_LEVEL=batman     # Logging level

# Routing Options
ENABLE_ROUTING=1            # Enable routing/NAT
```

## Service Operation

The mesh network is managed through systemd:

```bash
# Enable auto-start
sudo systemctl enable mesh-network.service

# Start the service
sudo systemctl start mesh-network.service

# Check status
sudo systemctl status mesh-network.service
```

### Service Logging
The service maintains detailed logs in multiple locations:

1. **Main Service Log**:
   ```bash
   # View mesh network service log
   tail -f /var/log/mesh-network.log
   
   # View last 100 lines with timestamps
   tail -n 100 /var/log/mesh-network.log
   
   # Search for specific events
   grep "gateway" /var/log/mesh-network.log
   grep "error" /var/log/mesh-network.log
   ```

2. **Systemd Journal**:
   ```bash
   # Follow service logs in real-time
   sudo journalctl -u mesh-network.service -f
   
   # View logs since last boot
   sudo journalctl -u mesh-network.service -b
   
   # View logs with timestamps
   sudo journalctl -u mesh-network.service --output=short-precise
   ```

3. **System Logs**:
   ```bash
   # Check kernel messages related to batman-adv
   dmesg | grep batman
   
   # View system logs for network-related events
   tail -f /var/log/syslog | grep -E "batman|mesh|wlan"
   ```

### Log Analysis
Important log entries to watch for:

1. **Gateway Detection**:
   ```
   [timestamp] Starting gateway detection
   [timestamp] Found batman-adv gateway MAC: xx:xx:xx:xx:xx:xx
   [timestamp] Verified x.x.x.x is a batman-adv gateway
   ```

2. **Route Configuration**:
   ```
   [timestamp] Configuring routing for gateway x.x.x.x
   [timestamp] Successfully added default route via x.x.x.x
   ```

3. **Error Conditions**:
   ```
   [timestamp] Failed to add default route
   [timestamp] Gateway unreachable after multiple attempts
   [timestamp] Interface not ready or down
   ```

## Troubleshooting

### Common Issues

1. **Service Fails to Start**
   ```bash
   # Check service status
   sudo systemctl status mesh-network.service
   
   # View detailed logs
   sudo journalctl -u mesh-network.service -f
   tail -f /var/log/mesh-network.log
   
   # Check for errors in system log
   grep -i error /var/log/mesh-network.log
   ```

2. **No Gateway Connection**
   ```bash
   # Check batman-adv gateway list
   sudo batctl gwl
   
   # Verify ARP entries
   arp -a | grep bat0
   
   # Test gateway ping
   sudo batctl ping <gateway-ip>
   
   # Check gateway detection logs
   tail -f /var/log/mesh-network.log | grep -E "gateway|route"
   ```

3. **Interface Problems**
   ```bash
   # Check interface status
   ip link show
   iwconfig
   
   # Verify batman-adv is loaded
   lsmod | grep batman
   
   # Check batman-adv interface
   batctl if
   
   # Monitor interface-related logs
   tail -f /var/log/mesh-network.log | grep -E "interface|wlan"
   ```

### Diagnostic Commands
```bash
# Real-time log monitoring
tail -f /var/log/mesh-network.log

# Check batman-adv status
sudo batctl o         # Originator table
sudo batctl t        # Translation table
sudo batctl d        # Debug log

# Network diagnostics
sudo iw dev          # Wireless interface info
sudo iwconfig        # Wireless settings
sudo iftop -i bat0   # Network traffic

# System checks
dmesg | grep batman  # Kernel messages
sudo sysctl -a | grep batman  # Kernel parameters
```

## Advanced Topics

### Custom Gateway Selection
Gateway selection process:
1. Checks ARP cache for potential gateways
2. Verifies gateway status using batman-adv
3. Tests connectivity before configuring routes
4. Monitors gateway health and performs failover

### High Availability Setup
For critical deployments:
1. Configure multiple gateway nodes
2. Set up redundant paths
3. Implement monitoring and alerting
4. Use automatic failover

### Performance Tuning
```bash
# Optimize batman-adv parameters
sudo batctl hardif $MESH_INTERFACE gw_mode client
sudo batctl hardif $MESH_INTERFACE orig_interval 1000
sudo batctl hardif $MESH_INTERFACE hop_penalty 15
```

## References

- [Batman-adv Documentation](https://www.open-mesh.org/projects/batman-adv/wiki)
- [Linux Wireless](https://wireless.wiki.kernel.org/)
- [Netfilter/iptables](https://netfilter.org/documentation/)
- [IEEE 802.11s Mesh Networking](https://ieeexplore.ieee.org/document/5167291)

## Monitoring and Maintenance

### Log Monitoring
Regular log monitoring is essential for maintaining mesh network health:

1. **Automated Log Checking**:
   ```bash
   # Create a simple log monitor
   watch -n 10 'tail -n 20 /var/log/mesh-network.log'
   
   # Monitor specific events
   tail -f /var/log/mesh-network.log | grep --color=auto -E 'error|warning|gateway|route'
   ```

2. **Log Rotation**:
   The service automatically rotates logs to prevent disk space issues. Old logs are stored as:
   ```
   /var/log/mesh-network.log.1
   /var/log/mesh-network.log.2.gz
   /var/log/mesh-network.log.3.gz
   ```

3. **Log Analysis Tools**:
   ```bash
   # Count occurrences of specific events
   grep -c "gateway" /var/log/mesh-network.log
   
   # View unique gateway IPs
   grep "gateway" /var/log/mesh-network.log | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u
   
   # Check for common errors
   grep -i error /var/log/mesh-network.log | sort | uniq -c
   ```

### Performance Monitoring
Monitor network performance using various tools:

1. **Traffic Analysis**:
   ```bash
   # Monitor interface traffic
   sudo iftop -i bat0
   
   # View bandwidth usage
   sudo nethogs bat0
   
   # Check interface statistics
   cat /sys/class/net/bat0/statistics/*
   ```

2. **Gateway Status**:
   ```bash
   # Check current gateway
   ip route show | grep default
   
   # Monitor gateway changes
   tail -f /var/log/mesh-network.log | grep "gateway"
   
   # View gateway list
   sudo batctl gwl
   ```

3. **Node Status**:
   ```bash
   # View originator table
   sudo batctl o
   
   # Check translation table
   sudo batctl t
   
   # Monitor debug log
   sudo batctl d
   ```

