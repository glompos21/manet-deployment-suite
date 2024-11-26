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
ip addr del "${MESH_IP}/${MESH_NETMASK}" dev bat0 2>/dev/null || true
ip addr add "${MESH_IP}/${MESH_NETMASK}" dev bat0

if [ "${ENABLE_ROUTING}" = "1" ]; then
    echo "Debug: Configuring routing and firewall"
    sysctl -w net.ipv4.ip_forward=1
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Connection tracking
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Basic mesh routing
    iptables -A FORWARD -i bat0 -j ACCEPT
    iptables -A FORWARD -o bat0 -j ACCEPT
    
    # NAT configuration
    iptables -t nat -A POSTROUTING -o bat0 -j MASQUERADE
    
    # Security logging
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables_INPUT_denied: " --log-level 7
    iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "iptables_FORWARD_denied: " --log-level 7
    
    ip route del default via "${MESH_IP}" dev bat0 2>/dev/null || true
    ip route add default via "${MESH_IP}" dev bat0
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
