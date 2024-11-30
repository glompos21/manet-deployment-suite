#!/bin/bash

# Exit on any error
set -e

# Check if running as a service
if [ "${1}" = "service" ]; then
    # Redirect output to log file without tee when running as a service
    LOG_FILE="/var/log/mesh-network.log"
    exec 1>> "${LOG_FILE}"
    exec 2>> "${LOG_FILE}"
else
    # Keep the existing tee logging for interactive use
    LOG_FILE="/var/log/mesh-network.log"
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2>&1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    log "ERROR: $1"
    exit 1
}

# Function to validate configuration
validate_config() {
    local required_vars=(
        "MESH_INTERFACE" "MESH_MTU" "MESH_MODE" "MESH_ESSID" 
        "MESH_CHANNEL" "MESH_CELL_ID" "NODE_IP" "GATEWAY_IP" 
        "MESH_NETMASK" "BATMAN_GW_MODE"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required configuration variable ${var} is not set"
        fi
    done
    
    # Validate IP address format
    if ! [[ "${NODE_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid NODE_IP format: ${NODE_IP}"
    fi
    
    if ! [[ "${GATEWAY_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid GATEWAY_IP format: ${GATEWAY_IP}"
    fi
}

# Function to detect gateway IP from batman-adv with improved logic
detect_gateway_ip() {
    log "Starting gateway detection" >&2
    
    # Check if bat0 interface exists
    if ! ip link show bat0 >/dev/null 2>&1; then
        log "bat0 interface not found" >&2
        return 1
    fi
    
    # First try the configured gateway
    if arping -I bat0 -c 3 -w 2 "${GATEWAY_IP}" 2>/dev/null | grep -q "bytes from"; then
        log "Configured gateway ${GATEWAY_IP} is reachable" >&2
        printf "%s" "${GATEWAY_IP}"
        return 0
    fi
    
    log "Configured gateway not reachable, scanning for alternatives" >&2
    
    # Get list of potential gateways from batctl
    local gw_list
    gw_list=$(batctl gwl 2>/dev/null)
    
    if [ -z "${gw_list}" ]; then
        log "No gateways found in batctl gwl" >&2
    else
        log "Gateway list: ${gw_list}" >&2
    fi
    
    # Try to resolve gateway addresses using batctl
    local batman_nodes
    batman_nodes=$(batctl n 2>/dev/null | grep -v "No batman nodes in range" || true)
    
    # Fallback: scan common IP ranges
    log "Scanning common IP ranges for gateways" >&2
    local network_prefix="${NODE_IP%.*}"
    
    for i in {1..10}; do
        local test_ip="${network_prefix}.${i}"
        if [ "${test_ip}" != "${NODE_IP}" ]; then
            if arping -I bat0 -c 5 -w 1 "${test_ip}" 2>/dev/null | grep -q "bytes from"; then
                log "Found potential gateway at ${test_ip}" >&2
                printf "%s" "${test_ip}"
                return 0
            fi
        fi
    done
    
    log "No gateway found after exhaustive search" >&2
    return 1
}

# Start main script execution
log "==== Starting mesh network configuration ===="

# Validate configuration
log "Validating configuration parameters"
validate_config

# Debug output
log "Debug: MESH_INTERFACE=${MESH_INTERFACE}"

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
log "Debug: Setting regulatory domain"
iw reg set US
sleep 1

log "Debug: Disabling NetworkManager for ${MESH_INTERFACE}"
nmcli device set "${MESH_INTERFACE}" managed no
sleep 1

log "Debug: Setting interface down"
ip link set down dev "${MESH_INTERFACE}"
sleep 1

log "Debug: Loading batman-adv module"
modprobe batman-adv
if ! lsmod | grep -q "^batman_adv"; then
    echo "Error: Failed to load batman-adv module"
    exit 1
fi
sleep 2

log "Debug: Setting MTU"
ip link set mtu "${MESH_MTU}" dev "${MESH_INTERFACE}"
sleep 1

log "Debug: Configuring wireless settings"
iwconfig "${MESH_INTERFACE}" mode ad-hoc
iwconfig "${MESH_INTERFACE}" essid "${MESH_ESSID}"
iwconfig "${MESH_INTERFACE}" ap "${MESH_CELL_ID}"
iwconfig "${MESH_INTERFACE}" channel "${MESH_CHANNEL}"
sleep 1

log "Debug: Setting interface up"
ip link set up dev "${MESH_INTERFACE}"
sleep 3

log "Debug: Verifying interface is up"
if ! ip link show "${MESH_INTERFACE}" | grep -q "UP"; then
    echo "Error: Failed to bring up ${MESH_INTERFACE}"
    exit 1
fi

log "Debug: Adding interface to batman-adv"
if ! batctl if add "${MESH_INTERFACE}"; then
    echo "Error: Failed to add interface to batman-adv"
    exit 1
fi
sleep 2

log "Debug: Waiting for bat0 interface"
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

log "Debug: Setting bat0 up"
ip link set up dev bat0
sleep 1

log "Debug: Configuring IP address"
# Clean up existing IP configuration
ip addr flush dev bat0 2>/dev/null || true
ip addr add "${NODE_IP}/${MESH_NETMASK}" dev bat0 || {
    echo "Error: Failed to add IP address to bat0"
    exit 1
}

log "Debug: Adding mesh network route"
# Calculate network address from NODE_IP and MESH_NETMASK
NETWORK_ADDRESS="${NODE_IP%.*}.0"  # Extract first 3 octets and append .0
ip route flush dev bat0 || echo "Warning: Could not flush routes"
ip route add "${NETWORK_ADDRESS}/${MESH_NETMASK}" dev bat0 proto kernel scope link src "${NODE_IP}" || {
    echo "Error: Failed to add mesh network route"
    exit 1
}

if [ "${ENABLE_ROUTING}" = "1" ]; then
    log "Debug: Configuring routing and firewall"
    sysctl -w net.ipv4.ip_forward=1 || { echo "Error: Failed to enable IP forwarding"; exit 1; }
    
    log "Debug: Flushing existing routes and firewall rules"
    # Clean up existing firewall rules
    iptables -F || { echo "Error: Failed to flush iptables rules"; exit 1; }
    iptables -t nat -F || { echo "Error: Failed to flush NAT rules"; exit 1; }
    iptables -t mangle -F || { echo "Error: Failed to flush mangle rules"; exit 1; }
    
    log "Debug: Setting default policies"
    iptables -P INPUT ACCEPT || { echo "Error: Failed to set INPUT policy"; exit 1; }
    iptables -P FORWARD ACCEPT || { echo "Error: Failed to set FORWARD policy"; exit 1; }
    iptables -P OUTPUT ACCEPT || { echo "Error: Failed to set OUTPUT policy"; exit 1; }
    
    log "Debug: Configuring connection tracking"
    # Connection tracking
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || { echo "Error: Failed to add INPUT state rule"; exit 1; }
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT || { echo "Error: Failed to add FORWARD state rule"; exit 1; }
    
    log "Debug: Setting up mesh routing rules"
    # Basic mesh routing
    iptables -A FORWARD -i bat0 -j ACCEPT || { echo "Error: Failed to add FORWARD input rule"; exit 1; }
    iptables -A FORWARD -o bat0 -j ACCEPT || { echo "Error: Failed to add FORWARD output rule"; exit 1; }
    
    log "Debug: Configuring NAT"
    # NAT configuration
    iptables -t nat -A POSTROUTING -o bat0 -j MASQUERADE || { echo "Error: Failed to add MASQUERADE rule"; exit 1; }
    
    log "Debug: Setting up logging rules"
    # Security logging
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables_INPUT_denied: " --log-level 7 || echo "Warning: Failed to add INPUT logging rule"
    iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "iptables_FORWARD_denied: " --log-level 7 || echo "Warning: Failed to add FORWARD logging rule"
    
    log "Debug: Detecting gateway"
    # Detect and configure gateway routing
    if [ "${BATMAN_GW_MODE}" != "server" ]; then
        log "Client mode: Starting gateway detection"
        
        detected_gateway=$(detect_gateway_ip) || {
            log "Warning: Initial gateway detection failed"
            detected_gateway=""
        }
        
        if [ -n "${detected_gateway}" ]; then
            GATEWAY_IP="${detected_gateway}"
            log "Using detected gateway: ${GATEWAY_IP}"
            
            # Set up routing with fallback
            if ! ip route add default via "${GATEWAY_IP}" dev bat0 metric 150; then
                log "Failed to add primary route, attempting fallback configuration"
                if ! ip route add default via "${GATEWAY_IP}" dev bat0 metric 200; then
                    error "Failed to configure any routing"
                fi
            fi
            
            # Monitor gateway status in background with proper process management
            {
                while true; do
                    sleep 30
                    if ! ping -c 1 -W 5 "${GATEWAY_IP}" >/dev/null 2>&1; then
                        log "Gateway ${GATEWAY_IP} became unreachable, attempting to find new gateway"
                        new_gateway=$(detect_gateway_ip)
                        if [ -n "${new_gateway}" ] && [ "${new_gateway}" != "${GATEWAY_IP}" ]; then
                            log "Switching to new gateway: ${new_gateway}"
                            ip route replace default via "${new_gateway}" dev bat0 metric 150
                            GATEWAY_IP="${new_gateway}"
                        fi
                    fi
                done
            } </dev/null >/dev/null 2>&1 &
            
            # Store the monitoring process PID in a file for proper cleanup
            echo $! > /var/run/mesh-network-monitor.pid
        else
            error "No valid gateway could be found"
        fi
    else
        log "Running in server mode, skipping gateway detection"
        # Server mode configuration...
    fi
fi

log "Debug: Setting BATMAN-adv parameters"
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

log "==== Mesh network configuration complete ===="

# If running as a service, keep the script running to maintain the network
if [ "${1}" = "service" ]; then
    # Wait indefinitely while still responding to signals
    while true; do
        sleep 3600 & wait $!
    done
fi
