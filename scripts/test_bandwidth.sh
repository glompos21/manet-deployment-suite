#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check if iperf3 is installed
if ! command -v iperf3 &> /dev/null; then
    echo "iperf3 is not installed. Installing now..."
    apt-get update && apt-get install -y iperf3
    if [ $? -ne 0 ]; then
        echo "Failed to install iperf3"
        exit 1
    fi
fi

# Check if batman interface exists
if ! ip link show bat0 &> /dev/null; then
    echo "Batman interface (bat0) not found. Please ensure mesh network is setup first."
    exit 1
fi

# Default values
MODE="client"
SERVER_IP=""
PORT="5201"
DURATION="10"

# Help function
show_help() {
    echo "Usage: $0 [-s|--server] [-c|--client SERVER_IP] [-p|--port PORT] [-t|--time SECONDS]"
    echo ""
    echo "Options:"
    echo "  -s, --server        Run in server mode"
    echo "  -c, --client IP     Run in client mode and connect to specified server IP"
    echo "  -p, --port PORT     Specify port number (default: 5201)"
    echo "  -t, --time SECONDS  Test duration in seconds (default: 10)"
    echo ""
    echo "Examples:"
    echo "  Server mode: $0 -s"
    echo "  Client mode: $0 -c 192.168.99.2"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            MODE="server"
            shift
            ;;
        -c|--client)
            MODE="client"
            SERVER_IP="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -t|--time)
            DURATION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate parameters
if [ "$MODE" = "client" ] && [ -z "$SERVER_IP" ]; then
    echo "Error: Server IP is required for client mode"
    show_help
    exit 1
fi

# Run iperf3 in specified mode
if [ "$MODE" = "server" ]; then
    echo "Starting iperf3 server on bat0 interface..."
    iperf3 -s -B $(ip addr show bat0 | grep inet | awk '{print $2}' | cut -d/ -f1)
else
    echo "Starting bandwidth test to $SERVER_IP for $DURATION seconds..."
    iperf3 -c "$SERVER_IP" -t "$DURATION"
fi
