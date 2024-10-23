import subprocess
import os

def run_command(command, shell=True):
    """Run a shell command and print it for debugging purposes."""
    try:
        print(f"Running: {command}")
        subprocess.run(command, shell=shell, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e}")
        exit(1)

def main():
    # Ask for hostname
    hostname = input("Enter the hostname for this device: ")
    run_command(f"hostnamectl set-hostname {hostname}")

    # Update package lists and install required packages
    run_command("apt-get update")
    run_command("apt-get install -y batctl batman-adv net-tools iproute2 wireless-tools")

    # Ask for network interface
    network_interface = input("Enter the network interface for batman-adv (e.g., wlan0, eth0): ")

    # Load the batman-adv kernel module
    run_command("modprobe batman-adv")

    # Make the module persistent
    with open("/etc/modules", "a") as modules_file:
        modules_file.write("batman-adv\n")

    # Configure batman-adv on the specified interface
    print("Configuring batman-adv...")
    run_command(f"ip link set {network_interface} down")
    run_command(f"ip link set {network_interface} mtu 1532")
    run_command(f"batctl if add {network_interface}")
    run_command(f"ip link set {network_interface} up")
    run_command(f"ip link set up dev bat0")

    # Add batman-adv configuration to /etc/network/interfaces for persistence
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

    print("batman-adv configuration complete!")

if __name__ == "__main__":
    # Ensure the script is being run as root
    if os.geteuid() != 0:
        print("This script must be run as root. Please run with sudo.")
        exit(1)

    main()
