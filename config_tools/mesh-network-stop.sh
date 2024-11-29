#!/bin/bash

echo "==== Stopping mesh network ===="

# Flush all routes and addresses from bat0 interface
if ip link show bat0 >/dev/null 2>&1; then
    ip route flush dev bat0 2>/dev/null || true
    ip addr flush dev bat0 2>/dev/null || true
    ip link set down dev bat0 2>/dev/null || true
fi

# Remove interface from batman-adv
if [ -n "${MESH_INTERFACE}" ]; then
    batctl if del "${MESH_INTERFACE}" 2>/dev/null || true
fi

# Reset wireless interface
if [ -n "${MESH_INTERFACE}" ]; then
    ip link set down dev "${MESH_INTERFACE}" 2>/dev/null || true
    iwconfig "${MESH_INTERFACE}" mode managed 2>/dev/null || true
    ip addr flush dev "${MESH_INTERFACE}" 2>/dev/null || true
fi

# Unload batman-adv module if no other interfaces are using it
if ! batctl if | grep -q .; then
    rmmod batman-adv 2>/dev/null || true
fi

# Reset firewall if routing was enabled
if [ "${ENABLE_ROUTING}" = "1" ]; then
    # Flush all rules
    iptables -F || true
    iptables -t nat -F || true
    iptables -t mangle -F || true
    
    # Reset default policies
    iptables -P INPUT ACCEPT || true
    iptables -P FORWARD ACCEPT || true
    iptables -P OUTPUT ACCEPT || true
    
    # Disable IP forwarding
    sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
fi

# Re-enable NetworkManager for the interface
if [ -n "${MESH_INTERFACE}" ]; then
    nmcli device set "${MESH_INTERFACE}" managed yes 2>/dev/null || true
fi

echo "==== Mesh network stopped ===="
