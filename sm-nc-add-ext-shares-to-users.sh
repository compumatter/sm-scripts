#!/bin/bash
# (c) CompuMatter, LLC, ServerMatter
# no warranty expressed or implied - use as is.
# The purpose of this script is to:
### Determine what shares are in /etc/samba/smb.conf
### Find groups with the same names (or can do string replace if a pattern change is required) and determine users who have access to them
### Add those shares as 'external storage' shares in those users NC
### This script should be run during the initial server build at the end of the NC install.
### This script should be run when new groups are created or users are added to existing groups

#### build associative array called user_to_uuid.  It will contain users and their uuids for use in the balance of the script
output=$(sudo -u www-data php occ user:list)
# Split the output into lines
IFS=$'\n' lines=($output)

groups_changed=false

# Initialize associative array
declare -A user_to_uuid

# Process each line
for line in "${lines[@]}"; do
  # Split the line into UUID and username
  IFS=":" read -r uuid username <<< "$line"

  # Remove leading/trailing whitespace from username
  username=$(echo $username | xargs)

  # Remove leading/trailing whitespace from uuid
  uuid=$(echo $uuid | xargs)
  # Remove preceeding hyphen and space from uuid
  uuid=$(echo "$uuid" | sed 's/^-[[:space:]]*//')

  # uncommnent if you wish to see the users returned
  #  echo $username $uuid
  # Add to associative array
  user_to_uuid["$username"]=$uuid
done


#### This section of the code parses the smb.conf file and builds two arrays.  One is the $shares (share names) and the other is the share paths (the directory being shared)
# these arrays will be used in the final section of the script
# this section also gets the realm from the smb.conf file ie; office.theirname.ext

config_file="/etc/samba/smb.conf"
# Use grep to find the line containing "realm" in smb.conf
realm_line=$(grep -E "^\s*realm\s*=" "$config_file")
# Use awk to extract the realm value from the line
realm=$(echo "$realm_line" | awk -F "=" '{print $2}' | awk '{gsub(/^ +| +$/,"")}1')
# Convert realmto lowercase
realm="${realm,,}"

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

#### This section queries samba for a list of users and then walks/loops through each username found in $group_users
# We also pull the $user_uuid out of the $user_to_uuid array that was built in the first section of this script
# Finally, we build the NextCloud script that is used for creating the new share
for share in "${!paths[@]}"; do
#    echo "$share ${paths[$share]}"

    # We mirror our group names / share names except our groups use hyphens. Here we swap the shares underscore for a hyphen
    # If you need to do a character string replacement from shares to smb groups, uncomment this and do your string replace
    # group_to_list_members=${share//_/-}
    group_to_list_members=$share
    
#    echo "Members of group '$group_to_list_members':"
    # tail begins the capture at the 2nd line
    mapfile -t group_users < <(samba-tool group listmembers "$group_to_list_members" 2>/dev/null | tail -n +1)

#    mapfile -t group_users < <(samba-tool group listmembers "$group_to_list_members" | tail -n +1)
    for username in "${group_users[@]}"
    do
        user_uuid=${user_to_uuid["$username"]}
        if [ "$user_uuid" ]; then

              ### This section tests if the share/mount already exists
              ### If it does, we will continue to the next  in the loop
              ### If it does not, we will add the users share/mount
              share_exists=$(sudo -u www-data php occ files_external:list -- $user_uuid 2>/dev/null | grep "s-$share")

               # Check if there is any output
              if [[ -n "$share_exists" ]]; then
                    # Do something with the output here
                    # Replace the 'echo' statement below with your desired action
                    # echo "this external mount s-$share already for $username - not adding"
                    continue;
              else
                    groups_changed=true
                    # mount does not exist so adding now
                    # echo "adding mount s-$share"
                    # echo "$username $share ${paths[$share]} $user_uuid"
                    # echo $username
                    # note: user_uuid in this case includes the preceeding hyphen in that variable
                    nc_add_user_share=$(echo "sudo -u www-data php occ files_external:create --user=\"$user_uuid\" \"s-$share\" 'smb' 'password::logincredentials' --config host=\"127.0.0.1\" --config share=\"$share\" --config root="" --config domain=\"$realm\"")

                    # uncomment if you just want to see the command resulting
                    # echo $nc_add_user_share

                    # comment out if you just want to see the display above.
                    eval "$nc_add_user_share"
              fi
        fi
    done
done

if [ "$groups_changed" == true ]; then
    # scan to incorporate the new files into NextCloud
    sudo -u www-data php occ files:scan --unscanned --all
fi
