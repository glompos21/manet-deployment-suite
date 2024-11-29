#!/bin/bash

# Exit on any error
set -e

echo "==== Starting mesh network configuration ===="

# Debug output
echo "Debug: MESH_INTERFACE=${MESH_INTERFACE}"

# Verify required tools
command -v batctl >/dev/null 2>&1 || { echo "Error: batctl not installed"; exit 1; }
command -v ip >/dev/null 2>&1 || { echo "Error: ip command not found"; exit 1; }
command -v iwconfig >/dev/null 2>&1 || { echo "Error: iwconfig not found"; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo "Error: iptables not found"; exit 1; }
command -v nmcli >/dev/null 2>&1 || { echo "Error: nmcli not found"; exit 1; }

# Verify interface exists and is wireless
ip link show "${MESH_INTERFACE}" >/dev/null 2>&1 || { echo "Error: ${MESH_INTERFACE} interface not found"; exit 1; }
iwconfig "${MESH_INTERFACE}" 2>/dev/null | grep -q "IEEE 802.11" || { echo "Error: ${MESH_INTERFACE} is not a wireless interface"; exit 1; }

# Function to detect gateway IP from batman-adv
detect_gateway_ip() {
    echo "Debug: Starting gateway detection" >&2
    
    # Check if bat0 interface exists
    if ! ip link show bat0 >/dev/null 2>&1; then
        echo "Debug: bat0 interface not found" >&2
        return 1
    fi
    
    # Check if any gateway exists and capture gateway MAC
    gateway_mac=$(batctl gwl 2>/dev/null | grep -E "^.*\[.*\].*[0-9]+\.[0-9]+/[0-9]+\.[0-9]+.*MBit" | awk '{print $1}')
    
    if [ -z "$gateway_mac" ]; then
        echo "Debug: No gateway found in batctl gwl" >&2
        return 1
    fi
    
    echo "Debug: Found gateway MAC: ${gateway_mac}" >&2
    
    # Try all possible IPs
    for i in $(seq 1 254); do
        test_ip="10.0.0.${i}"
        echo "Debug: Trying ${test_ip}" >&2
        
        # Run arping and capture output
        if timeout 2s arping -I bat0 -c 2 "${test_ip}" 2>/dev/null | grep -q "bytes from"; then
            echo "Debug: Found gateway at ${test_ip}" >&2
            echo "${test_ip}"
            return 0
        fi
    done
    
    echo "Debug: No gateway IP found" >&2
    return 1
}

# Configure wireless interface
echo "Debug: Setting regulatory domain"
iw reg set US
sleep 1

echo "Debug: Disabling NetworkManager for ${MESH_INTERFACE}"
nmcli device set "${MESH_INTERFACE}" managed no
sleep 1

echo "Debug: Setting interface down"
ip link set down dev "${MESH_INTERFACE}"
sleep 1

echo "Debug: Loading batman-adv module"
modprobe batman-adv
if ! lsmod | grep -q "^batman_adv"; then
    echo "Error: Failed to load batman-adv module"
    exit 1
fi
sleep 2

echo "Debug: Setting MTU"
ip link set mtu "${MESH_MTU}" dev "${MESH_INTERFACE}"
sleep 1

echo "Debug: Configuring wireless settings"
iwconfig "${MESH_INTERFACE}" mode ad-hoc
iwconfig "${MESH_INTERFACE}" essid "${MESH_ESSID}"
iwconfig "${MESH_INTERFACE}" ap "${MESH_CELL_ID}"
iwconfig "${MESH_INTERFACE}" channel "${MESH_CHANNEL}"
sleep 1

echo "Debug: Setting interface up"
ip link set up dev "${MESH_INTERFACE}"
sleep 3

echo "Debug: Verifying interface is up"
if ! ip link show "${MESH_INTERFACE}" | grep -q "UP"; then
    echo "Error: Failed to bring up ${MESH_INTERFACE}"
    exit 1
fi

echo "Debug: Adding interface to batman-adv"
if ! batctl if add "${MESH_INTERFACE}"; then
    echo "Error: Failed to add interface to batman-adv"
    exit 1
fi
sleep 2

echo "Debug: Waiting for bat0 interface"
for i in $(seq 1 30); do
    if ip link show bat0 >/dev/null 2>&1; then
        echo "bat0 interface is ready"
        break
    fi
    if [ "$i" = "30" ]; then
        echo "Error: Timeout waiting for bat0 interface"
        exit 1
    fi
    echo "Waiting for bat0... attempt $i"
    sleep 1
done

echo "Debug: Setting bat0 up"
ip link set up dev bat0
sleep 1

echo "Debug: Configuring IP address"
# Clean up existing IP configuration
ip addr flush dev bat0 2>/dev/null || true
ip addr add "${NODE_IP}/${MESH_NETMASK}" dev bat0 || {
    echo "Error: Failed to add IP address to bat0"
    exit 1
}

echo "Debug: Adding mesh network route"
ip route del 10.0.0.0/16 dev bat0 2>/dev/null || true
ip route add 10.0.0.0/16 dev bat0 proto kernel scope link src 10.0.0.2 || {
    echo "Error: Failed to add mesh network route"
    exit 1
}

if [ "${ENABLE_ROUTING}" = "1" ]; then
    echo "Debug: Configuring routing and firewall"
    sysctl -w net.ipv4.ip_forward=1 || { echo "Error: Failed to enable IP forwarding"; exit 1; }
    
    echo "Debug: Flushing existing routes and firewall rules"
    # Clean up existing firewall rules and routes
    ip route flush dev bat0 || echo "Warning: Could not flush routes"
    iptables -F || { echo "Error: Failed to flush iptables rules"; exit 1; }
    iptables -t nat -F || { echo "Error: Failed to flush NAT rules"; exit 1; }
    iptables -t mangle -F || { echo "Error: Failed to flush mangle rules"; exit 1; }
    
    echo "Debug: Setting default policies"
    iptables -P INPUT ACCEPT || { echo "Error: Failed to set INPUT policy"; exit 1; }
    iptables -P FORWARD ACCEPT || { echo "Error: Failed to set FORWARD policy"; exit 1; }
    iptables -P OUTPUT ACCEPT || { echo "Error: Failed to set OUTPUT policy"; exit 1; }
    
    echo "Debug: Configuring connection tracking"
    # Connection tracking
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || { echo "Error: Failed to add INPUT state rule"; exit 1; }
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT || { echo "Error: Failed to add FORWARD state rule"; exit 1; }
    
    echo "Debug: Setting up mesh routing rules"
    # Basic mesh routing
    iptables -A FORWARD -i bat0 -j ACCEPT || { echo "Error: Failed to add FORWARD input rule"; exit 1; }
    iptables -A FORWARD -o bat0 -j ACCEPT || { echo "Error: Failed to add FORWARD output rule"; exit 1; }
    
    echo "Debug: Configuring NAT"
    # NAT configuration
    iptables -t nat -A POSTROUTING -o bat0 -j MASQUERADE || { echo "Error: Failed to add MASQUERADE rule"; exit 1; }
    
    echo "Debug: Setting up logging rules"
    # Security logging
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables_INPUT_denied: " --log-level 7 || echo "Warning: Failed to add INPUT logging rule"
    iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "iptables_FORWARD_denied: " --log-level 7 || echo "Warning: Failed to add FORWARD logging rule"
    
    echo "Debug: Detecting gateway"
    # Detect and configure gateway routing
    if [ "${BATMAN_GW_MODE}" != "server" ]; then
        echo "Debug: Not in server mode, attempting gateway detection"
        echo "Debug: Current BATMAN_GW_MODE=${BATMAN_GW_MODE}"
        
        echo "Debug: Current gateway list:"
        batctl gwl || echo "Warning: Could not get gateway list"
        
        # Capture only stdout, redirect stderr to console for debugging
        detected_gateway=$(detect_gateway_ip 2>/dev/null) || {
            echo "Warning: Gateway detection failed"
            detected_gateway=""
        }
        
        if [ -n "$detected_gateway" ] && [[ "$detected_gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            GATEWAY_IP="$detected_gateway"
            echo "Debug: Using detected gateway IP: ${GATEWAY_IP}"
        else
            echo "Debug: No valid gateway detected, using configured GATEWAY_IP: ${GATEWAY_IP}"
        fi
    else
        echo "Debug: Running in server mode, skipping gateway detection"
    fi
fi

echo "Debug: Setting BATMAN-adv parameters"
if ! batctl gw_mode "${BATMAN_GW_MODE}"; then
    echo "Error: Failed to set gateway mode"
    exit 1
fi

if ! batctl orig_interval "${BATMAN_ORIG_INTERVAL}"; then
    echo "Error: Failed to set originator interval"
    exit 1
fi

if ! batctl hop_penalty "${BATMAN_HOP_PENALTY}"; then
    echo "Error: Failed to set hop penalty"
    exit 1
fi

if ! batctl loglevel "${BATMAN_LOG_LEVEL}"; then
    echo "Error: Failed to set log level"
    exit 1
fi

echo "==== Mesh network configuration complete ===="
