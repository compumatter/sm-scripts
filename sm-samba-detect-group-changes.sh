#!/bin/bash
# samba domain admin password aka sdap
sdap="whateveryoursisorpullfromelsewhere"

# this is the file which will have the bytes ie; 55 or whatever the number is
size_monitor_file="groupfilesize.txt"
ldap_search_group_info_results_file="ldap_group_info.txt"

# If the file does not exist, create it with size 0
if [ ! -f "$size_monitor_file" ]; then
    echo 0 > "$size_monitor_file"
fi
# this simply cat's the contents of the file which will be 0 if first time run or the bytesize value if run previously
currentfilesize=$(cat $size_monitor_file)

# samba/group_changed/ldap_group_info.txt will provide a file which contains the samba-ad-dc group state at the time of running this script
# we are only interested in the 'bytesize' of this script.  When we run this file again from a cron, it will allow us to know if the groups have changed.
# If they have, we will run the nextcloud sm_add_AD_shares_to_nc.sh script
command="ldapsearch -H ldap://yourdomain.ext:389 -D 'cn=Administrator, cn=users, dc=yourdomain, dc=ext' -b 'dc=yourdomain, dc=ext' -w$sdap '(objectClass=group)'"
# echo "$command"  # This will echo the command for debugging purposes
# places the results of our ldapsearch ... objectClass=group output into this file
# this gives us a file we can measure for changes
eval "$command" > $ldap_search_group_info_results_file

# this measures the bytesize of the above commands output and stores it in the variable newfilesize
newfilesize=$(wc -c $ldap_search_group_info_results_file | awk '{print $1}')

# we place the value of $newfilesize into the $size_monitor_file so the next time we run this script that will be the existing aka $currentfilesize
echo $newfilesize > $size_monitor_file

# this is where we test to see if the results of the ldapsearch on groups ended up with a different bytesize.  If so, we add the shares
if [ "$currentfilesize" -ne "$newfilesize" ]
then
    # The file sizes are not equal. This means some samba-ad-dc group activity has occurred so recreate shares :-)
    /path/to/script/to/run.sh
fi
