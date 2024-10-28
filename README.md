# Mobile Ad-Hoc Network (MANET) Deployment Suite

**Table of Contents**
- [Introduction](#introduction)
- [What is a MANET?](#What-is-a-MANET?)
- [Why Use This Tool?](#why-use-this-tool)
- [Requirements](#requirements)
- [Requisite Skills](#requisite-skills)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Introduction
B.A.T.M.A.N. advanced (often referenced as batman-adv) is an implementation of the B.A.T.M.A.N. routing protocol in the form of a Linux kernel module operating on layer 2. This repository is dedicated to making the deployment of this tool easy, quick, and versatile for almost any potential use case.

## What is a MANET?
Mesh networking is by no means a new concept. If you're reading this in a public space (or a larger house), odds are you're connected to an access point that acts as part of a mesh. Mobile Ad Hoc Networking, however—also known as a 'MANET'—is starting to see some very interesting applications in our world. From networks of underground machinery to emergency response infrastructure and even special military operations, the term 'MANET' is becoming more well-known.

As Cisco puts it:
> "Mobile Ad Hoc Networks (MANETs) are an emerging type of wireless networking, in which mobile nodes associate on an extemporaneous or ad hoc basis. MANETs are both self-forming and self-healing, enabling peer-level communications between mobile nodes without reliance on centralized resources or fixed infrastructure.
> These attributes enable MANETs to deliver significant benefits in virtually any scenario that includes a cadre of highly mobile users or platforms, a strong need to share IP-based information, and an environment in which fixed network infrastructure is impractical, impaired, or impossible. Key applications include disaster recovery, heavy construction, mining, transportation, defense, and special event management."

## Why Use This Tool?
If you and your team want the superpower that is mobile ad-hoc networking without spending thousdands of dollars on the current off the shelf solutions... you're in the right place. This tool is designed to help build a MANET from off the shelf hardware that any civilian can buy, even if they're on a budget!

## Requirements
Before you can create an ad hoc mesh, you will need some hardware. This tool is designed to deploy on Debian-based Linux devices, so if it runs Debian, it will probably work (think Raspberry Pis, Libre Computer, etc.).

Second to the board itself, you will need at least **one WiFi radio**. This will most commonly be the onboard WiFi chipset of whatever board you are using, but it is still worth mentioning as a WiFi radio is a necessary component for each node. (*Note that additional WiFi dongles may be used to provide a WiFi Access Point, allowing end users to access the mesh, though this is not a requirement.)

## Requisite Skills
The idea behind this tool is to allow more typical users access to this cutting-edge technology without needing to be a Linux whiz or a networking guru. With that being said, troubleshooting is part of life with this kind of stuff, and it would behoove the installer to have some comfort with the Linux operating system (and command line), and a basic understanding of networking concepts (e.g., DHCP, DNS). Understanding the OSI model (particularly layers 2 & 3) is a bonus.

In all reality, however, you can absolutely do all of this without any of the skills mentioned above as long as you have the right attitude and the will to learn as you go.

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/mobile-ad-hoc-deployment-suite.git
   cd mobile-ad-hoc-deployment-suite
   ```

2. Make the scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

3. Install Batman-adv and dependencies:
   ```bash
   sudo ./scripts/install_batman.sh
   ```

## Usage

### Setting up a Mesh Network

1. Setup the mesh network with default settings:
   ```bash
   sudo ./scripts/setup_mesh.sh
   ```

2. Or customize the setup with specific parameters:
   ```bash
   sudo ./scripts/setup_mesh.sh -i wlan0 -m mesh0 -c 02:12:34:56:78:9A
   ```

   Parameters:
   - `-i, --interface`: WiFi interface to use (default: wlan0)
   - `-m, --mesh-name`: Name for the mesh interface (default: mesh0)
   - `-c, --cell-id`: Cell ID for the ad-hoc network (default: 02:12:34:56:78:9A)

### Monitoring the Mesh Network

To monitor the mesh network status:
```bash
sudo ./scripts/monitor_mesh.sh
```

This will show:
- Connected mesh interfaces
- Originator table (known nodes)
- Translation table
- Gateway information
- Interface statistics

## Troubleshooting

### Common Issues

1. **Interface not found**
   - Verify your WiFi interface name using `iwconfig`
   - Ensure the interface is not being managed by NetworkManager

2. **Cannot create mesh interface**
   - Check if batman-adv module is loaded: `lsmod | grep batman`
   - Try reloading the module: `sudo modprobe batman-adv`

3. **No mesh connectivity**
   - Verify all nodes are using the same cell ID
   - Check if interfaces are in ad-hoc mode
   - Ensure all nodes are on the same channel

### Getting Help

If you encounter issues:
1. Check the output of `dmesg` for kernel messages
2. Use `batctl` to debug mesh status
3. Open an issue on GitHub with detailed information about your setup and the problem
