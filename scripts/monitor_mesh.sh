#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

while true; do
    clear
    echo "=== BATMAN-ADV Mesh Network Monitor ==="
    echo ""
    
    echo "=== Mesh Interfaces ==="
    batctl meshif bat0 interface show
    echo ""
    
    echo "=== Originator Table ==="
    batctl meshif bat0 originators
    echo ""
    
    echo "=== Translation Table (Local) ==="
    batctl meshif bat0 translocal
    echo ""
    
    echo "=== Translation Table (Global) ==="
    batctl meshif bat0 transglobal
    echo ""
    
    echo "=== Gateway Table ==="
    batctl meshif bat0 gateways
    echo ""
    
    echo "=== Interface Statistics ==="
    iwconfig 2>/dev/null | grep -A 6 "802.11"
    echo ""
    
    sleep 5
done
