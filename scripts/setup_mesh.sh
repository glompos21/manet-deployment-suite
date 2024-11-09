#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check if batman-adv module is loaded
if ! lsmod | grep -q "^batman_adv"; then
    echo "batman-adv module is not loaded. Loading now..."
    modprobe batman-adv
    if [ $? -ne 0 ]; then
        echo "Failed to load batman-adv module"
        exit 1
    fi
fi

# Default values
INTERFACE="wlan0"
CELL_ID="02:12:34:56:78:9A"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        -c|--cell-id)
            CELL_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Stop NetworkManager from managing the interface
nmcli device set $INTERFACE managed no

# Bring down the interface
ip link set $INTERFACE down

# Set interface to ad-hoc mode
iwconfig $INTERFACE mode ad-hoc
iwconfig $INTERFACE essid "batman-mesh"
iwconfig $INTERFACE ap $CELL_ID
iwconfig $INTERFACE channel 1

# Bring up the interface
ip link set $INTERFACE up

# Create batman-adv interface
batctl if add $INTERFACE
ip link set up bat0

# Configure IP addressing
ip addr add 192.168.99.1/24 dev bat0

echo "Mesh network setup complete!"
echo "Interface: $INTERFACE"
echo "Batman Interface: bat0"
echo "Cell ID: $CELL_ID"
