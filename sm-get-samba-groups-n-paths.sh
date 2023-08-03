#!/bin/bash
# (c) CompuMatter, LLC, ServerMatter
# no warranty expressed or implied - use as is.

config_file="/etc/samba/smb.conf"

# List of excluded shares
exclude_list=("sysvol" "netlogon" "homes" "printers" "print$" "global")

# Parse smb.conf
IFS=$'\n'
shares=($(awk '/^\[.*\]$/ { print $0 }' "$config_file" | tr -d '[]'))

# Filter out excluded shares
for i in "${!shares[@]}"; do
    for exclude in "${exclude_list[@]}"; do
        if [[ "${shares[$i]}" = "$exclude" ]]; then
            unset 'shares[i]'
        fi
    done
done

# Associate paths with shares
declare -A paths
for share in "${shares[@]}"; do
#    echo "Working on share: $share"
    path=$(awk -v section="$share" -v RS='' '$0 ~ "\\["section"\\]" && $0 ~ /path[ =]/ {print $0}' "$config_file" | awk -F'[ =]+' '/path[ =]/{print $NF}')
#    echo "path = $path"
    paths["$share"]=$path
done

# Output result
for share in "${!paths[@]}"; do
    echo "$share ${paths[$share]}"
done

