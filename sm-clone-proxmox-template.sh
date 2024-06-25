#!/bin/bash
# (c) CompuMatter, LLC, ServerMatter
# no warranty expressed or implied - use as is.
# The purpose of this script is to:
# Create a clone of a VM within Proxmox.  Though it will create a clone in any circumstance, the I/O bandwidth has been controlled to insure Proxmox does not
#    exceed the systems maximum I/O and slow everything to a crawl
# We have been using it and found it to cause no side effects and implement the solution advertised.  That said, this script is given freely and as-as whereis.

TEMPLATE_ID=103
NEW_VM_ID=106
NEW_VM_NAME="email-server2"
TARGET_NODE="svr1"

# Start the cloning process and get the task ID
echo "Starting cloning process..."
qm clone $TEMPLATE_ID $NEW_VM_ID --name $NEW_VM_NAME --full --target $TARGET_NODE --bwlimit 170000 2>&1 | tee /tmp/qm_clone_output
sleep 1

# Wait for the task ID to appear in the output
TASKID=""
while [ -z "$TASKID" ]; do
    TASKID=$(grep -oP 'UPID:\K[^:]+' /tmp/qm_clone_output | head -1)
    if [ -n "$TASKID" ]; then
        break
    fi
    sleep 1
done

if [ -z "$TASKID" ]; then
  echo "Failed to get task ID. Output was:"
  cat /tmp/qm_clone_output
  exit 1
fi

echo "Task ID: $TASKID"

# Monitor the progress
while true; do
    TASK_DETAILS=$(pvesh get /nodes/$TARGET_NODE/tasks/$TASKID/status --output-format json 2>/dev/null)

    if [ -z "$TASK_DETAILS" ]; then
        echo "Failed to fetch task details. Retrying..."
        sleep 5
        continue
    fi

    STATUS=$(echo "$TASK_DETAILS" | jq -r '.status')
    PID=$(echo "$TASK_DETAILS" | jq -r '.pid')
    UPID=$(echo "$TASK_DETAILS" | jq -r '.upid')
    EXITSTATUS=$(echo "$TASK_DETAILS" | jq -r '.exitstatus')
    STARTTIME=$(echo "$TASK_DETAILS" | jq -r '.starttime')
    ENDTIME=$(echo "$TASK_DETAILS" | jq -r '.endtime')

    echo "Task Status: $STATUS"
    echo "PID: $PID"
    echo "UPID: $UPID"
    echo "Exit Status: $EXITSTATUS"
    echo "Start Time: $STARTTIME"
    echo "End Time: $ENDTIME"

    if [ "$STATUS" = "stopped" ]; then
        if [ "$EXITSTATUS" = "OK" ]; then
            echo "Clone process completed successfully."
        else
            echo "Clone process completed with errors."
        fi
        break
    elif [ "$STATUS" = "error" ]; then
        echo "Clone process failed."
        break
    fi
    sleep 5
done
