#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

MESH_NAME="bat0"

while true; do
    clear
    echo "=== BATMAN-ADV Mesh Network Monitor ==="
    echo ""
    
    echo "=== Mesh Interfaces ==="
    batctl if
    echo ""
    
    echo "=== Originator Table ==="
    batctl o
    echo ""
    
    echo "=== Translation Table ==="
    batctl t
    echo ""
    
    echo "=== Gateway Table ==="
    batctl gwl
    echo ""
    
    echo "=== Interface Statistics ==="
    iwconfig 2>/dev/null | grep -A 6 "802.11"
    echo ""
    
    sleep 5
done
