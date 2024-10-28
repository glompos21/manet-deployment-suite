#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Install dependencies
apt-get update
apt-get install -y \
    batctl \
    python3 \
    python3-pip \
    wireless-tools \
    net-tools

# Load batman-adv kernel module
modprobe batman-adv

# Add batman-adv to /etc/modules to load at boot
if ! grep -q "batman-adv" /etc/modules; then
    echo "batman-adv" >> /etc/modules
fi

echo "Batman-adv installation complete!"
