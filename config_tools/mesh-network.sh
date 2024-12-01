#!/bin/bash

# Instead of set -e, we'll handle errors more gracefully
set -o pipefail

# Add timeout function
timeout_exec() {
    local timeout=$1
    shift
    local cmd="$@"
    
    ( $cmd ) & pid=$!
    ( sleep $timeout && kill -HUP $pid ) 2>/dev/null & watcher=$!
    wait $pid 2>/dev/null && pkill -HUP -P $watcher
}

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

# Function to get gateway MACs from batctl gwl
get_gateway_macs() {
    # Get gateway list and filter out the header line and extract the Router MAC
    batctl gwl -n 2>/dev/null | grep -v "B.A.T.M.A.N." | grep "^*" | awk '{print $2}'
}

# Function to get MAC address from batctl ping
get_batman_mac() {
    local ip="$1"
    local mac
    mac=$(batctl ping -c1 "${ip}" 2>/dev/null | head -n1 | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -n1)
    echo "${mac}"
}

# Function to detect gateway IP
detect_gateway_ip() {
    # Redirect debug output to stderr
    log "Starting gateway detection" >&2
    
    # Check if bat0 interface exists
    if ! ip link show bat0 >/dev/null 2>&1; then
        log "bat0 interface not found" >&2
        return 1
    fi
    
    # Get list of gateway MACs from batctl gwl
    log "Getting list of batman-adv gateways" >&2
    local gateway_macs
    gateway_macs=$(get_gateway_macs)
    
    if [ -z "${gateway_macs}" ]; then
        log "No batman-adv gateways found" >&2
        return 1
    fi
    
    log "Found batman-adv gateway MAC(s): ${gateway_macs}" >&2
    
    # Get potential gateway IP from ARP cache
    local potential_ip
    potential_ip=$(arp -a | grep "bat0" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    
    if [ -n "${potential_ip}" ]; then
        log "Found potential gateway IP: ${potential_ip}" >&2
        
        # Verify this IP belongs to a batman-adv gateway
        local batman_mac
        batman_mac=$(get_batman_mac "${potential_ip}")
        
        if [ -n "${batman_mac}" ]; then
            log "IP ${potential_ip} belongs to batman-adv node: ${batman_mac}" >&2
            
            # Check if this MAC is in our gateway list
            if echo "${gateway_macs}" | grep -q "${batman_mac}"; then
                log "Verified ${potential_ip} is a batman-adv gateway" >&2
                
                # Try multiple times to reach the gateway
                local max_tries=3
                local try=1
                while [ $try -le $max_tries ]; do
                    log "Attempt $try/$max_tries to reach gateway" >&2
                    if ping -c 1 -W 2 "${potential_ip}" >/dev/null 2>&1; then
                        log "Gateway ${potential_ip} is reachable" >&2
                        printf "%s\n" "${potential_ip}"
                        return 0
                    fi
                    try=$((try + 1))
                    [ $try -le $max_tries ] && sleep 2
                done
                log "Gateway ${potential_ip} is not reachable after $max_tries attempts" >&2
            else
                log "IP ${potential_ip} is not a batman-adv gateway (MAC not in gateway list)" >&2
            fi
        else
            log "Could not get batman-adv MAC for ${potential_ip}" >&2
        fi
    fi
    
    log "No valid gateway found in ARP cache" >&2
    return 1
}

# Function to configure routing
configure_routing() {
    local gateway_ip="$1"
    
    # Validate input
    if [ -z "${gateway_ip}" ] || ! [[ "${gateway_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "Invalid gateway IP: ${gateway_ip}"
        return 1
    fi
    
    log "Configuring routing for gateway ${gateway_ip}"
    
    # Check if the route already exists
    if ip route show | grep -q "^default via ${gateway_ip}"; then
        log "Route already exists"
        return 0
    fi
    
    # Remove any existing default routes
    ip route flush default 2>/dev/null || true
    
    # Try multiple times to add the route
    local max_tries=3
    local try=1
    while [ $try -le $max_tries ]; do
        log "Attempt $try/$max_tries to add route"
        if ip route add default via "${gateway_ip}" dev bat0; then
            log "Successfully added default route via ${gateway_ip}"
            return 0
        fi
        try=$((try + 1))
        [ $try -le $max_tries ] && sleep 2
    done
    
    log "Failed to add default route after $max_tries attempts"
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

# Add these variables near the top of the script, after the initial variable declarations
VALID_WAN=""
VALID_LAN=""

# Modify the get_valid_interfaces function
get_valid_interfaces() {
    log "Validating network interfaces..."
    
    # Check WAN interfaces with more detailed validation
    if ip link show "${WAN_IFACE}" >/dev/null 2>&1 && [ -n "${WAN_IFACE}" ]; then
        VALID_WAN="${WAN_IFACE}"
        log "Found WAN interface: ${VALID_WAN}"
    elif ip link show "${ETH_WAN}" >/dev/null 2>&1 && [ -n "${ETH_WAN}" ]; then
        VALID_WAN="${ETH_WAN}"
        log "Found WAN interface: ${VALID_WAN}"
    else
        log "WARNING: No valid WAN interface found"
    fi
    
    # Check LAN interfaces with more detailed validation
    if ip link show "${ETH_LAN}" >/dev/null 2>&1 && [ -n "${ETH_LAN}" ]; then
        VALID_LAN="${ETH_LAN}"
        log "Found LAN interface: ${VALID_LAN}"
    else
        log "WARNING: No valid LAN interface found"
    fi
    
    # Additional validation for server mode
    if [ "${BATMAN_GW_MODE}" = "server" ]; then
        if [ -z "${VALID_WAN}" ]; then
            log "WARNING: Server mode with no WAN interface"
        fi
    fi
}

if [ "${ENABLE_ROUTING}" = "1" ]; then
    log "Debug: Configuring routing and firewall"
    
    # Validate interfaces first
    get_valid_interfaces
    
    # Log interface status
    if [ -n "${VALID_WAN}" ]; then
        log "Debug: Using WAN interface: ${VALID_WAN}"
    else
        log "Debug: No WAN interface available"
    fi
    
    if [ -n "${VALID_LAN}" ]; then
        log "Debug: Using LAN interface: ${VALID_LAN}"
    else
        log "Debug: No LAN interface available"
    fi
    
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
            log "DEBUG: Initial gateway detection failed, will retry later"
            detected_gateway=""
        }
        
        if [ -n "${detected_gateway}" ]; then
            GATEWAY_IP="${detected_gateway}"
            log "DEBUG: Using detected gateway: ${GATEWAY_IP}"
            
            # Set up routing with fallback
            if ! ip route add default via "${GATEWAY_IP}" dev bat0 metric 150; then
                log "DEBUG: Failed to add primary route, attempting fallback configuration"
                if ! ip route add default via "${GATEWAY_IP}" dev bat0 metric 200; then
                    log "DEBUG: Failed to configure any routing"
                    # Don't exit here, just continue and retry later
                fi
            fi
            
            # Monitor gateway status in background with proper process management
            {
                while true; do
                    sleep 30
                    if ! ping -c 1 -W 5 "${GATEWAY_IP}" >/dev/null 2>&1; then
                        log "DEBUG: Gateway ${GATEWAY_IP} became unreachable, attempting to find new gateway"
                        new_gateway=$(detect_gateway_ip)
                        if [ -n "${new_gateway}" ] && [ "${new_gateway}" != "${GATEWAY_IP}" ]; then
                            log "DEBUG: Switching to new gateway: ${new_gateway}"
                            ip route replace default via "${new_gateway}" dev bat0 metric 150 || {
                                log "DEBUG: Failed to update route to new gateway"
                            }
                            GATEWAY_IP="${new_gateway}"
                        fi
                    fi
                done
            } </dev/null >/dev/null 2>&1 &
            
            # Store the monitoring process PID in a file for proper cleanup
            echo $! > /var/run/mesh-network-monitor.pid
        else
            log "DEBUG: No valid gateway found initially, continuing without gateway"
            # Don't exit here, just continue and the service will retry later
        fi
    else
        log "Running in server mode, configuring gateway rules"
        
        # Configure WAN interface rules
        if [ -n "${VALID_WAN}" ]; then
            log "Setting up gateway forwarding rules for WAN interface ${VALID_WAN}"
            
            if ! iptables -A FORWARD -i bat0 -o "${VALID_WAN}" -j ACCEPT; then
                log "ERROR: Failed to add bat0 to WAN forwarding rule"
                exit 1
            fi
            
            if ! iptables -A FORWARD -i "${VALID_WAN}" -o bat0 -j ACCEPT; then
                log "ERROR: Failed to add WAN to bat0 forwarding rule" 
                exit 1
            fi
            
            log "Setting up NAT for internet access"
            if ! iptables -t nat -A POSTROUTING -o "${VALID_WAN}" -j MASQUERADE; then
                log "ERROR: Failed to add NAT masquerade rule"
                exit 1
            fi
        else
            log "WARNING: No valid WAN interface found for server mode"
        fi
        
        # Configure LAN interface rules if available
        if [ -n "${VALID_LAN}" ]; then
            log "Setting up LAN interface rules for ${VALID_LAN}"
            
            if ! iptables -A FORWARD -i "${VALID_LAN}" -o bat0 -j ACCEPT; then
                log "ERROR: Failed to add LAN to bat0 forwarding rule"
                exit 1
            fi
            
            if ! iptables -A FORWARD -i bat0 -o "${VALID_LAN}" -j ACCEPT; then
                log "ERROR: Failed to add bat0 to LAN forwarding rule"
                exit 1
            fi
            
            # Add NAT for LAN clients
            if ! iptables -t nat -A POSTROUTING -s "${NETWORK_ADDRESS}/${MESH_NETMASK}" -o "${VALID_LAN}" -j MASQUERADE; then
                log "ERROR: Failed to add LAN NAT masquerade rule"
                exit 1
            fi
        fi
        
        # Add logging for debugging
        log "DEBUG: Verifying iptables rules..."
        iptables -L FORWARD -n -v
        iptables -t nat -L POSTROUTING -n -v
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

# Improved interface setup with better error handling
setup_interface() {
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log "Attempting interface setup (attempt $((retry_count + 1))/${max_retries})"
        
        # Clean up any existing configuration
        ip link set down dev "${MESH_INTERFACE}" 2>/dev/null || true
        ip addr flush dev "${MESH_INTERFACE}" 2>/dev/null || true
        
        if ! timeout_exec 10 ip link set "${MESH_INTERFACE}" up; then
            log "Failed to bring up interface, retrying..."
            sleep 2
            retry_count=$((retry_count + 1))
            continue
        fi
        
        if ! timeout_exec 5 iwconfig "${MESH_INTERFACE}" mode ad-hoc; then
            log "Failed to set ad-hoc mode, retrying..."
            sleep 2
            retry_count=$((retry_count + 1))
            continue
        fi
        
        # Configure wireless settings with proper delays
        iwconfig "${MESH_INTERFACE}" essid "${MESH_ESSID}"
        sleep 1
        iwconfig "${MESH_INTERFACE}" ap "${MESH_CELL_ID}"
        sleep 1
        iwconfig "${MESH_INTERFACE}" channel "${MESH_CHANNEL}"
        sleep 2
        
        # Verify configuration
        if iwconfig "${MESH_INTERFACE}" | grep -q "${MESH_ESSID}"; then
            log "Interface setup successful"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        sleep 2
    done
    
    log "Failed to setup interface after ${max_retries} attempts"
    return 1
}

# Improved main execution with proper cleanup
cleanup() {
    log "Cleaning up..."
    if [ -f /var/run/mesh-network-monitor.pid ]; then
        kill $(cat /var/run/mesh-network-monitor.pid) 2>/dev/null || true
        rm -f /var/run/mesh-network-monitor.pid
    fi
}

trap cleanup EXIT

# Function to monitor gateway
monitor_gateway() {
    local current_gateway="$1"
    local unreachable=true
    
    for i in {1..3}; do
        if ping -c 1 -W 2 "${current_gateway}" >/dev/null 2>&1; then
            unreachable=false
            break
        fi
        sleep 2
    done
    
    echo "${unreachable}"
}

# If running as a service, keep the script running to maintain the network
if [ "${1}" = "service" ]; then
    # Simplified service monitoring
    RETRY_INTERVAL=30  # Time between retries in seconds
    
    while true; do
        # Check if bat0 interface is up
        if ! ip link show bat0 >/dev/null 2>&1 || ! ip link show bat0 | grep -q "UP"; then
            log "bat0 interface not ready or down, waiting..."
            sleep "${RETRY_INTERVAL}"
            continue
        fi
        
        # Check if we need to configure a gateway
        if ! ip route show | grep -q "^default"; then
            log "No default route found, checking for gateway..."
            gateway_ip=$(detect_gateway_ip)
            
            if [ -n "${gateway_ip}" ]; then
                if configure_routing "${gateway_ip}"; then
                    # Wait a moment to ensure route is stable
                    sleep 2
                    # Verify route was actually added
                    if ! ip route show | grep -q "^default"; then
                        log "Route verification failed, will retry"
                        continue
                    fi
                fi
            fi
        else
            # Passive monitoring - only check if current gateway is still valid
            current_gateway=$(ip route show | grep "^default" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
            if [ -n "${current_gateway}" ]; then
                # Check gateway reachability
                unreachable=$(monitor_gateway "${current_gateway}")
                
                if [ "${unreachable}" = "true" ]; then
                    log "Current gateway ${current_gateway} is unreachable after multiple attempts"
                    ip route del default 2>/dev/null || true
                fi
            fi
        fi
        
        sleep "${RETRY_INTERVAL}"
    done
fi
