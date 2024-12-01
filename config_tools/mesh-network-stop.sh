#!/bin/bash

# Source config file if it exists
[ -f /etc/mesh-network/mesh-config.conf ] && . /etc/mesh-network/mesh-config.conf

# Set up logging
LOG_FILE="/var/log/mesh-network.log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STOP: $1"
}

log "Stopping mesh network"

# Kill any existing monitoring processes
if [ -f /var/run/mesh-network-monitor.pid ]; then
    kill $(cat /var/run/mesh-network-monitor.pid) 2>/dev/null || true
    rm -f /var/run/mesh-network-monitor.pid
fi

# Flush all routes and addresses from bat0 interface
if ip link show bat0 >/dev/null 2>&1; then
    log "Cleaning up bat0 interface"
    ip route flush dev bat0 2>/dev/null || true
    ip addr flush dev bat0 2>/dev/null || true
    ip link set down dev bat0 2>/dev/null || true
fi

# Find and clean up mesh interface if MESH_INTERFACE is not set
if [ -z "${MESH_INTERFACE}" ]; then
    MESH_INTERFACE=$(batctl if 2>/dev/null | head -n1 | cut -f1) || true
fi

# Remove interface from batman-adv
if [ -n "${MESH_INTERFACE}" ]; then
    log "Removing ${MESH_INTERFACE} from batman-adv"
    batctl if del "${MESH_INTERFACE}" 2>/dev/null || true
fi

# Reset wireless interface
if [ -n "${MESH_INTERFACE}" ]; then
    log "Resetting ${MESH_INTERFACE}"
    ip link set down dev "${MESH_INTERFACE}" 2>/dev/null || true
    iwconfig "${MESH_INTERFACE}" mode managed 2>/dev/null || true
    ip addr flush dev "${MESH_INTERFACE}" 2>/dev/null || true
fi

# Unload batman-adv module if no other interfaces are using it
if ! batctl if 2>/dev/null | grep -q .; then
    log "Unloading batman-adv module"
    rmmod batman-adv 2>/dev/null || true
fi

# Reset firewall rules regardless of ENABLE_ROUTING
log "Resetting firewall rules"
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true

# Reset default policies
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Disable IP forwarding
sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true

# Re-enable NetworkManager for the interface
if [ -n "${MESH_INTERFACE}" ]; then
    log "Re-enabling NetworkManager for ${MESH_INTERFACE}"
    nmcli device set "${MESH_INTERFACE}" managed yes 2>/dev/null || true
fi

log "Mesh network stopped successfully"
exit 0
