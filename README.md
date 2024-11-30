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
- [Interface Persistence](#interface-persistence)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Performance Optimization](#performance-optimization)
- [Security Considerations](#security-considerations)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [References](#references)

## Introduction

The B.A.T.M.A.N. advanced (commonly referred to as batman-adv) is an implementation of the B.A.T.M.A.N. layer 2 routing protocol, integrated as a Linux kernel module. This repository aims to simplify the deployment of batman-adv, ensuring it is easy, efficient, and adaptable to various use cases.

## What is a MANET?

Mesh networking is not a novel concept. If you are in a public space or a large residence, there is a good chance that you are connected to a network through an access point that is part of a mesh. However, Mobile Ad Hoc Networking (MANET) brings unique possibilities, especially in highly dynamic environments. MANETs are increasingly finding critical applications in areas such as underground mining operations, emergency response systems, and specialized military communications. This has led to a rising awareness and use of the term "MANET" in both industrial and public domains.

As Cisco describes it:

> "Mobile Ad Hoc Networks (MANETs) are an emerging type of wireless networking, in which mobile nodes associate on an extemporaneous or ad hoc basis. MANETs are both self-forming and self-healing, enabling peer-level communications between mobile nodes without reliance on centralized resources or fixed infrastructure.
>
> These attributes enable MANETs to deliver significant benefits in virtually any scenario that includes a cadre of highly mobile users or platforms, a strong need to share IP-based information, and an environment in which fixed network infrastructure is impractical, impaired, or impossible. Key applications include disaster recovery, heavy construction, mining, transportation, defense, and special event management."

## Why Use This Guide?

If your team is looking to harness the capabilities of mobile ad-hoc networking without incurring the considerable expenses associated with commercial off-the-shelf solutions, this guide is for you. This tool is designed to assist you in building a MANET using easily accessible, consumer-grade hardware, even on a limited budget.

## Requirements

To set up an ad hoc mesh network, you will need:

1. **Hardware Requirements**:
   - Any device capable of running Debian Linux (Raspberry Pi, Libre Computer, etc.)
   - At least one WiFi radio that supports ad-hoc mode
   - Optional: Additional WiFi adapter or Ethernet port for internet gateway
   - Optional: Additional WiFi adapter or Ethernet port for providing downstream access

2. **Software Requirements**:
   - Debian-based Linux distribution
   - Required packages (automatically installed during setup):
     - batctl
     - iw
     - wireless-tools
     - net-tools
     - bridge-utils
     - iptables
     - dnsmasq
     - hostapd
     - arping

### Network Types

Your mesh network can be configured in several ways:
1. **Simple Mesh**: All nodes communicate directly
2. **Gateway Mesh**: One node acts as an internet gateway
3. **Access Point Mesh**: Nodes provide WiFi or LAN access points
4. **Hybrid Setup**: Combination of gateway and access points

## Installation

### 1. Base System Preparation

```bash
# Update system
sudo apt update
sudo apt upgrade -y

# Install git and clone repository
sudo apt install git
git clone [repository-url]
cd [repository-name]

# Run installation script
sudo ./setup.sh
```

### 2. Configuration

The system uses a central configuration file at `/etc/mesh-network/mesh-config.conf`. Edit this file to define your node's role and behavior:

```bash
sudo nano /etc/mesh-network/mesh-config.conf
```

#### Configuration Parameters

```conf
# Interface Definitions
MESH_INTERFACE=wlan0    # Interface used for mesh networking
AP_IFACE=wlan1         # Optional: Interface for WiFi access point
WAN_IFACE=wlan2        # Optional: Interface for internet connection
ETH_WAN=eth0          # Optional: Ethernet WAN interface
ETH_LAN=eth1          # Optional: Ethernet LAN interface

# Mesh Network Parameters
MESH_MTU=1500
MESH_MODE=ad-hoc
MESH_ESSID=mesh-network    # Must be identical across all nodes
MESH_CHANNEL=1            # Use 1, 6, or 11
MESH_CELL_ID=02:12:34:56:78:9A  # Must be identical across all nodes

# BATMAN-adv Configuration
BATMAN_ORIG_INTERVAL=1000
BATMAN_GW_MODE=server    # server=gateway, client=mesh node, off=standalone
BATMAN_HOP_PENALTY=30
BATMAN_LOG_LEVEL=batman

# Network Configuration
NODE_IP=10.0.0.1         # Unique for each node
GATEWAY_IP=10.0.0.1      # IP of the gateway node
MESH_NETMASK=16
ENABLE_ROUTING=1         # Enable for gateway and AP nodes
```

## Node Configuration Types

### 1. Gateway Node
A gateway node provides internet access to the mesh network. Configure:

```conf
BATMAN_GW_MODE=server
ENABLE_ROUTING=1
```

The service script will automatically:
- Enable IP forwarding
- Configure NAT for internet access
- Set up appropriate routing between mesh and WAN interfaces
- Configure firewall rules for secure routing

### 2. Mesh Node
A standard mesh node that routes traffic within the network. Configure:

```conf
BATMAN_GW_MODE=client
ENABLE_ROUTING=1  # If providing AP or LAN access
```

The service script will:
- Configure batman-adv for mesh participation
- Set up routing if ENABLE_ROUTING=1
- Detect and configure gateway routing

### 3. Access Point Node
A node that provides network access to end users. Requires additional configuration:

1. **Assign Static IP to AP Interface**
```bash
sudo nano /etc/network/interfaces

# Add configuration
auto wlan1  # Replace with your AP_IFACE
iface wlan1 inet static
    address 10.20.0.1
    netmask 255.255.255.0
```

2. **Configure hostapd**
```bash
sudo nano /etc/hostapd/hostapd.conf

# Add configuration
interface=wlan1  # Replace with your AP_IFACE
driver=nl80211
hw_mode=g
ssid=your-ap-name
channel=11  # Different from mesh channel
wpa=2
wpa_passphrase=your-secure-password
wpa_key_mgmt=WPA-PSK
```

3. **Enable hostapd**
```bash
sudo systemctl enable hostapd
sudo systemctl start hostapd
```

4. **Configure dnsmasq for DHCP**
```bash
sudo nano /etc/dnsmasq.d/ap.conf

# Add configuration
interface=wlan1  # Replace with your AP_IFACE
dhcp-range=10.20.0.50,10.20.0.150,24h
dhcp-option=3,10.20.0.1
dhcp-option=6,8.8.8.8,8.8.4.4
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

### What the Service Does

The service script (`mesh-network.sh`) automatically:
1. Validates configuration parameters
2. Configures wireless interfaces for mesh operation
3. Sets up batman-adv
4. Configures IP addressing and routing
5. Sets up firewall rules based on node type
6. Monitors gateway connectivity
7. Handles service cleanup on shutdown

## Interface Persistence (Recommended for Multiple Adapters)

To maintain consistent interface names:

```bash
sudo nano /etc/systemd/network/10-wlan0.link

[Match]
MACAddress=xx:xx:xx:xx:xx:xx  # Replace with actual MAC

[Link]
Name=wlan0
```

## Common Issues and Solutions

1. **Missing Commands**
   ```bash
   # Add to ~/.bashrc
   export PATH=$PATH:/sbin:/usr/sbin
   ```

2. **Interface Name Changes**
   - Use systemd-networkd link files as described above

3. **DNSMasq Issues**
   - Ensure interfaces have static IPs
   - Check status: `sudo systemctl status dnsmasq`

4. **NetworkManager Conflicts**
   ```bash
   # List connections
   nmcli connection show
   # Delete conflicting connections
   nmcli connection delete "Connection Name"
   ```

5. **Gateway Routing Issues**
   ```bash
   # Adjust route metrics if needed
   sudo ip route del default via 10.0.0.1 dev bat0
   sudo ip route add default via 10.0.0.1 dev bat0 metric 200
   ```

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

