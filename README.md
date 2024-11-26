# Mobile Ad-Hoc Network (MANET) Deployment Suite

## Table of Contents
- [Introduction](#introduction)
- [What is a MANET?](#what-is-a-manet)
- [Why Use This Guide?](#why-use-this-guide)
- [Requirements](#requirements)
- [Network Planning](#network-planning)
  - [Interface Selection](#interface-selection)
  - [Network Addressing](#network-addressing)
- [Base System Setup](#base-system-setup)
  - [User Account Setup](#1-user-account-setup)
  - [Fresh Debian Installation](#2-fresh-debian-installation)
  - [Load Batman-adv Module](#3-load-batman-adv-module)
- [Basic Mesh Configuration](#basic-mesh-configuration)
  - [Automated Setup Using Systemd Service](#automated-setup-using-systemd-service)
  - [Manual Configuration](#manual-configuration)
- [Network Routing Configuration](#network-routing-configuration)
  - [Enable IP Forwarding](#1-enable-ip-forwarding)
  - [Configure iptables for Network Routing](#2-configure-iptables-for-network-routing)
  - [Access Point Configuration (Optional)](#3-access-point-configuration-optional)
- [Configure dnsmasq for IP Address Leasing to Downstream Devices](#configure-dnsmasq-for-ip-address-leasing-to-downstream-devices)
  - [Install dnsmasq](#1-install-dnsmasq)
  - [Configure dnsmasq for the Access Point or LAN](#2-configure-dnsmasq-for-the-access-point-or-lan)
  - [Example Configuration for Gateway Node](#example-configuration-for-gateway-node)
  - [Example Configuration for Access Point Node](#example-configuration-for-access-point-node)
  - [Restart dnsmasq](#3-restart-dnsmasq)
  - [Verify Configuration](#4-verify-configuration)
  - [Example: Configure LAN Interface](#example-configure-lan-interface)
- [Troubleshooting](#troubleshooting)
  - [Check Batman-adv Status](#1-check-batman-adv-status)
  - [Debug Connectivity](#2-debug-connectivity)
  - [Common Issues](#3-common-issues)
- [Performance Optimization](#performance-optimization)
  - [MTU Settings](#mtu-settings)
  - [Channel Selection](#channel-selection)
- [Security Considerations](#security-considerations)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
  - [Basic Monitoring](#basic-monitoring)
  - [Performance Testing](#performance-testing)
- [References](#references)
- [Contributing](#contributing)

## Introduction

B.A.T.M.A.N. advanced (often referenced as batman-adv) is an implementation of the B.A.T.M.A.N. routing protocol in the form of a Linux kernel module operating on layer 2. This repository is dedicated to making the deployment of this tool easy, quick, and versatile for almost any potential use case.

## What is a MANET?

Mesh networking is by no means a new concept. If you're reading this in a public space (or a larger house), odds are you're connected to an access point that acts as part of a mesh. Mobile Ad Hoc Networking, however—also known as a 'MANET'—is starting to see some very interesting applications in our world. From networks of underground machinery to emergency response infrastructure and even special military operations, the term 'MANET' is becoming more well-known.

As Cisco puts it:
> "Mobile Ad Hoc Networks (MANETs) are an emerging type of wireless networking, in which mobile nodes associate on an extemporaneous or ad hoc basis. MANETs are both self-forming and self-healing, enabling peer-level communications between mobile nodes without reliance on centralized resources or fixed infrastructure.
> These attributes enable MANETs to deliver significant benefits in virtually any scenario that includes a cadre of highly mobile users or platforms, a strong need to share IP-based information, and an environment in which fixed network infrastructure is impractical, impaired, or impossible. Key applications include disaster recovery, heavy construction, mining, transportation, defense, and special event management."

## Why Use This Guide?

If you and your team want the superpower that is mobile ad-hoc networking without spending thousands of dollars on the current off-the-shelf solutions... you're in the right place. This tool is designed to help build a MANET from off-the-shelf hardware that any civilian can buy, even if they're on a budget!

## Requirements

Before you can create an ad hoc mesh, you will need some hardware. This tool is designed to deploy on Debian-based Linux devices, so if it runs Debian, it will probably work (think Raspberry Pis, Libre Computer, etc.).

Second to the board itself, you will need at least **one WiFi radio**. This will most commonly be the onboard WiFi chipset of whatever board you are using, but it is still worth mentioning as a WiFi radio is a necessary component for each node. (*Note that additional WiFi dongles may be used to provide a WiFi Access Point, allowing end users to access the mesh, though this is not a requirement.)

### Network Types

Your mesh network can be configured in several ways:
1. **Simple Mesh**: All nodes communicate directly
2. **Gateway Mesh**: One node acts as an internet gateway
3. **Access Point Mesh**: Nodes provide WiFi access points
4. **Hybrid Setup**: Combination of gateway and access points

## Network Planning

### Interface Selection

Before beginning setup, identify your network interfaces and plan their roles:

1. **List Available Interfaces**

```bash
# Show all network interfaces
ip link show

# Show wireless interfaces and capabilities
iw dev
```

2. **Choose Mesh Interface**

```bash
# After identifying your wireless interface (e.g., wlan0, wlan1), set it as your mesh interface
export MESH_IFACE="wlan0"  # Replace wlan0 with your chosen interface
# Also do the following where applicable
export AP_IFACE="wlan1"
export WAN_IFACE="eth0"
export LAN_IFACE="eth1"

# Verify interface exists and is suitable
iw dev $MESH_IFACE info  # Should show interface details
```

3. **Interface Role Planning**

Each interface in your system needs a clear, dedicated role:
- **Mesh Interface ($MESH_IFACE)**: Must support ad-hoc mode for mesh networking
  - Usually a WiFi interface with good Linux driver support
  - Check ad-hoc support: `iw dev $MESH_IFACE info | grep "supported interface modes"`
- **Access Point Interface** (optional): Needs AP mode support
  - Separate from mesh interface to avoid performance issues
  - Check AP support: `iw list | grep "* AP"`
- **WAN Interface** (optional): For internet gateway nodes
  - Typically eth0 or a separate WiFi interface

4. **Network Addressing**
- Plan your IP ranges carefully:
  - Mesh network (bat0): e.g., 10.10.0.0/16
  - Access Points: e.g., 10.20.0.0/16 (note, each access point should be on a separate range to avoid IP conflicts between EUDs on different APs)
  - Avoid conflicts with existing networks
- Document your IP scheme for future reference
- Leave room for network expansion

## Base System Setup

### 1. User Account Setup

After installing Debian, create a non-root user account and configure sudo access:

```bash
# Create new user (replace username with desired name)
adduser username

# Install sudo if not already installed
apt install sudo

# Add user to sudo group
usermod -aG sudo username

# Switch to the new user
su - username

# Verify sudo access
sudo whoami  # Should output "root"
```

### 2. Fresh Debian Installation

```bash
# Update system
sudo apt update
sudo apt upgrade

# Install essential packages
sudo apt install -y \
    batctl \
    iw \
    wireless-tools \
    net-tools \
    bridge-utils \
    iptables   \
    dnsmasq \
    hostapd 
```

### 3. Load Batman-adv Module

```bash
# Load module
sudo modprobe batman-adv

# Make it permanent
echo "batman-adv" | sudo tee -a /etc/modules
```

## Basic Mesh Configuration

You can configure the mesh network either manually or using our automated systemd service.

### Automated Setup Using Systemd Service

The automated setup uses two key files:
1. `mesh-network.service`: A systemd service that handles the mesh network configuration
2. `mesh-config.conf`: A configuration file containing all mesh network parameters

#### 1. Understanding mesh-config.conf

The configuration file (`/etc/mesh-network/mesh-config.conf`) contains all the parameters needed to set up your mesh network. Here's a detailed explanation of each parameter:

note: the actual mesh-config file should not contain comments. The template should be copied from the provided file, not the example below.
```conf
# Network Interface Settings
MESH_INTERFACE=wlan0         # The wireless interface to use for mesh networking
MESH_MTU=1500               # Maximum Transmission Unit size
MESH_MODE=ad-hoc            # Wireless mode (must be ad-hoc for mesh)
MESH_ESSID=mesh-network     # Network name (must be identical across all nodes)
MESH_CHANNEL=1              # WiFi channel (1, 6, or 11 recommended)
MESH_CELL_ID=02:12:34:56:78:9A  # Cell ID (BSSID) must be identical across all nodes

# BATMAN-adv Settings
BATMAN_ORIG_INTERVAL=1000   # Originator interval in milliseconds
                             # Lower values = faster updates but more overhead
BATMAN_GW_MODE=server      # Gateway mode: server (provides internet)
                             # client (uses internet), or off

# IP Configuration
MESH_IP=192.168.99.1       # IP address for this node (unique per node)
MESH_NETMASK=24            # Network mask (e.g., 24 for /24)
ENABLE_ROUTING=1           # Enable IP forwarding (1=yes, 0=no)

# Advanced Settings
BATMAN_HOP_PENALTY=30      # Penalty for each hop (15-100, higher = less hops)
BATMAN_LOG_LEVEL=batman         # Log level (0=none to 4=verbose)
```

#### 2. Understanding mesh-network.service

The systemd service (`/etc/systemd/system/mesh-network.service`) provides automated setup and teardown of the mesh network. Key features:

- **Dependency Management**: Starts after network services are ready
- **Pre-flight Checks**: Verifies all required tools and interfaces
- **Comprehensive Setup**:
  - Configures wireless interface in ad-hoc mode
  - Sets up BATMAN-adv with specified parameters
  - Configures IP addressing and routing
  - Sets up firewall rules if routing is enabled

#### 3. Installation and Setup

1. **Create Configuration Directory and Files**
```bash
sudo mkdir -p /etc/mesh-network
```

2. **Configure Mesh Settings**
Copy the example configuration and modify for your needs:
```bash
sudo cp config_tools/mesh-config.conf /etc/mesh-network/
sudo nano /etc/mesh-network/mesh-config.conf
```

3. **Install and Enable the Service**
```bash
# Copy service file
sudo cp config_tools/mesh-network.service /etc/systemd/system/
# Copy service executables
sudo cp config_tools/mesh-network.sh /usr/sbin/
sudo cp config_tools/mesh-network-stop.sh /usr/sbin/
# Set permissions
sudo chmod 644 /etc/systemd/system/mesh-network.service
sudo chmod +x /usr/sbin/mesh-network.sh
sudo chmod +x /usr/sbin/mesh-network-stop.sh

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable mesh-network.service
sudo systemctl start mesh-network.service
```

4. **Verify Service Status**
```bash
sudo systemctl status mesh-network.service
```

#### 4. Configuration Tips

- **IP Addresses**: Each node must have a unique IP address in the same subnet
- **Network Name**: The MESH_ESSID must be identical across all nodes
- **Cell ID**: The MESH_CELL_ID (BSSID) must be identical across all nodes in the mesh network. This is a crucial parameter that ensures all nodes can identify and communicate with each other. The format must be a valid MAC address (e.g., 02:12:34:56:78:9A). The first byte (02) indicates a locally administered address.
- **Channel Selection**: Use channels 1, 6, or 11 to avoid interference
- **Gateway Mode**:
  - Set BATMAN_GW_MODE="server" on nodes providing internet access
  - Set BATMAN_GW_MODE="client" on nodes that should use internet access
  - Set BATMAN_GW_MODE="off" for nodes that don't need internet connectivity
- **Performance Tuning**:
  - Adjust BATMAN_ORIG_INTERVAL based on network mobility
  - Modify BATMAN_HOP_PENALTY to control route selection
  - Set MTU based on your network requirements

#### 5. Modifying Configuration

To change settings:
1. Edit `/etc/mesh-network/mesh-config.conf`
2. Restart the service: `sudo systemctl restart mesh-network.service`

### Manual Configuration

```bash
# Prevent network-manager from interacting with interface
sudo nmcli device set $AP_IFACE managed no

# Configure interface
sudo ip link set $MESH_IFACE down
sudo iwconfig $MESH_IFACE mode ad-hoc
# Cell ID (BSSID) & name (ESSID) must be identical across all mesh nodes
sudo iwconfig $MESH_IFACE essid "your-mesh-name"
sudo iwconfig $MESH_IFACE ap 02:12:34:56:78:9A
sudo iwconfig $MESH_IFACE channel 1
sudo ip link set $MESH_IFACE up
```

### 2. Setup Batman-adv

```bash
# Add interface to batman-adv
sudo batctl if add $MESH_IFACE

# Bring up batman interface
sudo ip link set up dev bat0

# Configure IP (choose your network range)
sudo ip addr add your.chosen.ip.address/netmask dev bat0
```

## Network Routing Configuration

### 1. Enable IP Forwarding

```bash
# Enable IPv4 forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Make it permanent
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2. Configure iptables for Network Routing

#### Basic Routing Setup

```bash
# Clear existing rules
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Set default policies
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Enable routing between interfaces
sudo iptables -A FORWARD -i bat0 -j ACCEPT
sudo iptables -A FORWARD -o bat0 -j ACCEPT
```

#### For Gateway Nodes

```bash
# Allow forwarding between all relevant interfaces
sudo iptables -A FORWARD -i bat0 -o $WAN_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $WAN_IFACE -o bat0 -j ACCEPT

# Setup NAT for internet access
sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
```

#### For Access Point Nodes

```bash
# Allow forwarding between mesh and AP
sudo iptables -A FORWARD -i bat0 -o $AP_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $AP_IFACE -o bat0 -j ACCEPT

# NAT for AP clients (if needed)
sudo iptables -t nat -A POSTROUTING -o bat0 -j MASQUERADE
```

#### Save iptables Rules

```bash
# Install iptables-persistent
sudo apt install iptables-persistent -y

# Save current rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### 3. Access Point Configuration (Optional)

```bash
# Install hostapd
sudo apt install hostapd

# Configure AP interface
sudo ip link set $AP_IFACE up
sudo ip addr add your.ap.ip.address/netmask dev $AP_IFACE
```

#### Create a configuration file 
```bash
sudo nano /etc/hostapd/hostapd.conf 
```
```conf
interface=AP_IFACE
driver=nl80211
hw_mode=g
ssid=your-ap-name
channel=11
wpa=2
wpa_passphrase=your-secure-password
wpa_key_mgmt=WPA-PSK
```
note: channel must be different than the channel set for batman-mesh, either 1, 6, or 11. AP_IFACE must be actual name of the adapter, not the variable
#### Link hostapd Configuration: 
Point the hostapd service to your configuration file. Edit the hostapd default file:
```bash
sudo nano /etc/default/hostapd
```
Add or modify the line:
```conf
DAEMON_CONF="/etc/hostapd/hostapd.conf"
```
Unmask, enable, and restart hostapd
```bash
sudo systemctl unmask
sudo systemctl restart hostapd
sudo systemctl enable hostapd
```
Check Status Verify that the hostapd service is running without errors:
```bash
sudo systemctl status hostapd
```

## Configure dnsmasq for IP Address Leasing to Downstream Devices

To enable each node to lease IP addresses to EUDs (either through its access point or LAN connection), you will use `dnsmasq`, a lightweight DHCP and DNS server. This is where network planning comes into play, each instance of dnsmasq needs to have its own IP range so that EUDs on different nodes do not have IP conflicts.

### 1. Install dnsmasq

Ensure `dnsmasq` is installed on your system:

```bash
sudo apt install dnsmasq
```

### 2. Configure dnsmasq for the Access Point or LAN

Edit the `dnsmasq` configuration file to specify the parameters for your downstream network. You can edit the main configuration file or create a new one in `/etc/dnsmasq.d/` for clarity.

Create a new file for configuration:

```bash
sudo nano /etc/dnsmasq.d/downstream.conf
```

Add the following configuration options, modifying as needed for your setup:

```conf
# Interface to provide DHCP services
interface=$AP_IFACE  # Replace $AP_IFACE with your Access Point or LAN interface name

# DHCP range for downstream devices
# Set the IP range for the devices connecting to the Access Point
# Example: 10.20.1.50 - 10.20.1.150 with a lease time of 24 hours
dhcp-range=10.20.1.50,10.20.1.150,24h

# Gateway configuration
# Set the gateway for the downstream devices to use (typically the node itself)
dhcp-option=3,10.20.1.1  # Replace 10.20.1.1 with the IP of your AP interface

# DNS server options
# Set the DNS server for the downstream devices (can be the node or a public DNS)
dhcp-option=6,9.9.9.9,8.8.8.8  # Quad9 DNS, google as backup, or use your own choice

# Log DHCP leases (optional for debugging purposes)
dhcp-leasefile=/var/lib/misc/dnsmasq.leases

# Domain name for downstream devices (optional)
domain=mesh.local
```

### 3. Restart dnsmasq

After configuring `dnsmasq`, restart it to apply the changes:

```bash
sudo systemctl restart dnsmasq
```

### 4. Verify Configuration

You can verify that `dnsmasq` is running and leasing IP addresses properly by checking its status and examining the lease file:

```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# View active DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

### Notes

- **Interface Selection**: Make sure the correct interface (`$AP_IFACE` or `$LAN_IFACE`) is configured. If you have both AP and LAN connections, you may need multiple `interface` entries or separate configuration files for each interface.
- **Firewall Rules**: Ensure that your firewall rules allow DHCP traffic (typically UDP ports 67 and 68) on the interfaces where `dnsmasq` is providing services.
- **Access Point Setup**: Ensure that your access point is configured properly and running, as downstream devices need to connect to it to get IP addresses from `dnsmasq`.

### Example: Configure LAN Interface

If you want to lease IPs to devices connected to a LAN port, you can set up `dnsmasq` similarly:

```bash
# Create a configuration for the LAN interface
sudo nano /etc/dnsmasq.d/lan.conf
```

```conf
# Interface to provide DHCP services for LAN
interface=$LAN_IFACE  # Replace $LAN_IFACE with your LAN interface name

# DHCP range for LAN devices
dhcp-range=192.168.2.50,192.168.2.150,24h

# Gateway and DNS settings
dhcp-option=3,192.168.2.1
```

Restart `dnsmasq` after saving changes:

```bash
sudo systemctl restart dnsmasq
```

With these configurations, each node in your MANET can independently lease IP addresses to connected devices, ensuring seamless network expansion and connectivity for all downstream devices.

## Troubleshooting

### 1. Check Batman-adv Status

```bash
# View mesh interfaces
sudo batctl if

# Show neighbors
sudo batctl n

# View originator table
sudo batctl o
```

### 2. Debug Connectivity

```bash
# Check routing
ip route show
sudo iptables -L -v -n

# Test connectivity between interfaces
ping -I bat0 target.ip.address
```

### 3. Common Issues

- **Interface selection**: Verify interface capabilities with `iw list`
- **Routing issues**: Check iptables rules and IP forwarding
- **AP problems**: Verify interface supports AP mode
- **Performance issues**: Check for interference, MTU settings

## Performance Optimization

### MTU Settings

```bash
# Optimize MTU for mesh interface
sudo ip link set $MESH_IFACE mtu 1532
```

### Channel Selection

```bash
# Scan for least congested channel
sudo iwlist $MESH_IFACE scan | grep -i channel
```

## Security Considerations

1. **Network Planning**
   - Segment networks appropriately
   - Use private IP ranges
   - Plan firewall rules carefully

2. **Firewall Configuration**
   - Restrict access between segments as needed
   - Consider implementing connection tracking
   - Log suspicious activities

## Monitoring and Maintenance

### Basic Monitoring

```bash
# Check mesh status
sudo batctl n
sudo batctl o

# Monitor traffic
sudo iftop -i bat0
```

### Performance Testing

```bash
# Install iperf3
sudo apt install iperf3

# Test throughput between nodes
iperf3 -s  # on server
iperf3 -c target.ip.address  # on client
```

## References

- [Batman-adv Wiki](https://www.open-mesh.org/projects/batman-adv/wiki)
- [Linux Wireless Documentation](https://wireless.wiki.kernel.org/)
- [Debian Network Configuration](https://wiki.debian.org/NetworkConfiguration)
- [Netfilter/iptables Documentation](https://netfilter.org/documentation/)

