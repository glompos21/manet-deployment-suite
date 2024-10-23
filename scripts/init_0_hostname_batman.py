import subprocess
import os
import re

def run_command(command, shell=True):
    """Run a shell command and print it for debugging purposes."""
    try:
        print(f"Running: {command}")
        subprocess.run(command, shell=shell, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e}")
        return False
    return True

def get_available_interfaces():
    """Get a list of available network interfaces excluding 'lo' and 'eth' interfaces."""
    result = subprocess.run(["ip", "link"], capture_output=True, text=True)
    interfaces = []
    for line in result.stdout.splitlines():
        match = re.match(r"\d+: ([^:]+):", line)
        if match:
            interface = match.group(1)
            if interface not in ["lo"] and not interface.startswith("eth"):
                interfaces.append(interface)
    return interfaces

def select_network_interface():
    """Prompt the user to select a network interface from the available list."""
    interfaces = get_available_interfaces()
    if not interfaces:
        print("No suitable network interfaces found.")
        exit(1)
    
    print("Available network interfaces:")
    for idx, interface in enumerate(interfaces):
        print(f"{idx + 1}. {interface}")
    
    while True:
        try:
            choice = int(input("Select the network interface for batman-adv by number: "))
            if 1 <= choice <= len(interfaces):
                return interfaces[choice - 1]
            else:
                print("Invalid selection. Please try again.")
        except ValueError:
            print("Invalid input. Please enter a number.")

def main():
    # Ask for hostname
    hostname = input("Enter the hostname for this device: ")
    if not run_command(f"hostnamectl set-hostname {hostname}"):
        print("Failed to set hostname. Exiting...")
        exit(1)

    # Update package lists and install required packages
    if not run_command("apt-get update"):
        print("Failed to update package lists. Exiting...")
        exit(1)

    if not run_command("apt-get install -y batctl batman-adv net-tools iproute2 wireless-tools"):
        print("Failed to install required packages. Exiting...")
        exit(1)

    # Ask for network interface
    network_interface = select_network_interface()

    # Load the batman-adv kernel module
    if not run_command("modprobe batman-adv"):
        print("Failed to load batman-adv kernel module. Exiting...")
        exit(1)

    # Make the module persistent
    try:
        with open("/etc/modules", "a") as modules_file:
            modules_file.write("batman-adv\n")
    except IOError as e:
        print(f"Failed to write to /etc/modules: {e}")
        exit(1)

    # Configure batman-adv on the specified interface
    print("Configuring batman-adv...")
    if not run_command(f"ip link set {network_interface} down"):
        print("Failed to bring down the network interface. Exiting...")
        exit(1)

    if not run_command(f"ip link set {network_interface} mtu 1532"):
        print("Failed to set MTU on the network interface. Exiting...")
        exit(1)

    if not run_command(f"batctl if add {network_interface}"):
        print("Failed to add network interface to batman-adv. Exiting...")
        exit(1)

    if not run_command(f"ip link set {network_interface} up"):
        print("Failed to bring up the network interface. Exiting...")
        exit(1)

    if not run_command(f"ip link set up dev bat0"):
        print("Failed to bring up bat0 interface. Exiting...")
        exit(1)

    # Add batman-adv configuration to /etc/network/interfaces for persistence
    try:
        with open("/etc/network/interfaces", "a") as interfaces_file:
            interfaces_file.write(f"\n# Configuration for batman-adv\n")
            interfaces_file.write(f"auto {network_interface}\n")
            interfaces_file.write(f"iface {network_interface} inet manual\n")
            interfaces_file.write(f"    mtu 1532\n")
            interfaces_file.write(f"    pre-up batctl if add {network_interface}\n")
            interfaces_file.write(f"    post-up ip link set up dev {network_interface}\n")

            interfaces_file.write(f"\nauto bat0\n")
            interfaces_file.write(f"iface bat0 inet static\n")
            interfaces_file.write(f"    address 10.0.0.1\n")
            interfaces_file.write(f"    netmask 255.255.255.0\n")
    except IOError as e:
        print(f"Failed to write to /etc/network/interfaces: {e}")
        exit(1)

    print("batman-adv configuration complete!")

if __name__ == "__main__":
    # Ensure the script is being run as root
    if os.geteuid() != 0:
        print("This script must be run as root. Please run with sudo.")
        exit(1)

    main()
