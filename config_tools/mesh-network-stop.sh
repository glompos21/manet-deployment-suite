#!/bin/bash

echo "==== Stopping mesh network ===="

# Cleanup routing and IP configuration
ip route del default via "${NODE_IP}" dev bat0 2>/dev/null || true
ip route del default via "${GATEWAY_IP}" dev bat0 2>/dev/null || true
ip addr del "${NODE_IP}/${MESH_NETMASK}" dev bat0 2>/dev/null || true
ip link set down dev bat0 2>/dev/null || true

# Remove interface from batman-adv
batctl if del "${MESH_INTERFACE}" 2>/dev/null || true

# Reset wireless interface
ip link set down dev "${MESH_INTERFACE}" 2>/dev/null || true
iwconfig "${MESH_INTERFACE}" mode managed 2>/dev/null || true

# Unload batman-adv module
rmmod batman-adv 2>/dev/null || true

# Reset firewall if routing was enabled
if [ "${ENABLE_ROUTING}" = "1" ]; then
    iptables -F || true
    iptables -t nat -F || true
    iptables -t mangle -F || true
fi

# Re-enable NetworkManager
nmcli device set "${MESH_INTERFACE}" managed yes 2>/dev/null || true

echo "==== Mesh network stopped ===="
