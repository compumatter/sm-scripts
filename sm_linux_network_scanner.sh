#!/bin/bash
if ! which nmap >/dev/null; then
    echo "nmap is not installed - this script requires it"
    echo "It can be installed with - apt install nmap"
    return;
fi
# Check if the script is being run as root (EUID = 0)
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root user or with sudo"
    return;
fi
lease_file_location="/var/lib/dhcp/dhcpd.leases"

# will return br0, eth0, eno1 or whatever the default Interface is
default_interface=$(ip route | awk '/default/ {print $5}')
ip_and_cidr=$(ip -o -f inet addr show $default_interface | awk '{print $4}')
ip_range=$(echo $ip_and_cidr | sed 's/\.[0-9]*\//.0\//')

echo -e "\nRunning nmap -sn $ip_range to get a list of all IP addresses\n"
readarray -t ips < <(nmap -sn $ip_range | awk '/Nmap scan report/{gsub(/[()]/,""); print $NF}' | sort -t . -n -k 1,1 -k 2,2 -k 3,3 -k 4,4)

# Set column widths
col1=14
col2=17
col3=17
col4=15
col5=30

echo -e "Checking each IP address for Hostname, MAC, Workgroup or Domain, Manufacturer info\n"

# Format the output
printf "%-${col1}s | %-${col2}s | %-${col3}s | %-${col4}s | %-${col5}s \n" "IP" "MAC" "HOSTNAME" "WG-DOMAIN" "MANUFACTURER"
printf "%-${col1}s | %-${col2}s | %-${col3}s | %-${col4}s | %-${col5}s \n" "$(printf '%.s-' {1..13})" "$(printf '%.s-' {1..17})" "$(printf '%.s-' {1..17})" "$(printf '%.s-' {1..15})" "$(printf '%.s-' {1..30})"

for IP in "${ips[@]}"
do
  # Run the nmap command for the current IP
  OUTPUT="$(nmap --script nbstat.nse -p 137,139 $IP)"
  # Extract the necessary information
  MAC=$(echo "$OUTPUT" | grep 'MAC Address' | awk '{print $3}')
  HOSTNAME=$(echo "$OUTPUT" | grep '<20>.*<unique>.*<active>' | awk -F'[|<]' '{print $2}' | tr -d '_' | xargs)
  WG_DOMAIN=$(echo "$OUTPUT" | grep -v '<permanent>' | grep '<00>.*<group>.*<active>' | awk -F'[|<]' '{print $2}' | tr -d '_' | xargs)
  MANUFACTURER=$(echo "$OUTPUT" | grep 'MAC Address' | awk -F'(' '{print $2}' | cut -d ')' -f1)

  # if a dhcp server leases file exists on this machine, we will query it for a hostname if not already returned by nmap
  if [ -f "$lease_file_location" ]; then
    # If HOSTNAME is empty, fetch from dhcpd.leases
    if [ -z "$HOSTNAME" ]; then
      HOSTNAME=$(awk -v ip="$IP" '$1 == "lease" && $2 == ip {f=1} f && /client-hostname/ {print substr($2, 2, length($2) - 3); exit}' "$lease_file_location" | cut -c 1-15)

      # Append an asterisk (*) if HOSTNAME has a value
      if [ -n "$HOSTNAME" ]; then
        HOSTNAME="$HOSTNAME *"
      fi
    fi
  fi

  # Print a row of data for the current IP
  printf "%-${col1}s | %-${col2}s | %-${col3}s | %-${col4}s | %-${col5}s \n" "$IP" "$MAC" "$HOSTNAME" "$WG_DOMAIN" "$MANUFACTURER"
done

if [ -f "$lease_file_location" ]; then
  echo -e "\n* to the right of hostname indicates the hostname could not be acquired from nmap so was pulled from $lease_file_location\n"
fi

# we are grateful if you would leave our short tagline attached
echo -e "This network scanner script is provided free of charge by ServerMatter\n"
# Disclaimer: This script is provided as-is with no warranty and no responsibility.
# The author and contributors shall not be liable for any direct, indirect, incidental,
# special, exemplary, or consequential damages arising from the use of this script.
