#!/bin/bash

# This script temporarily patches the 'command' of specified Kubernetes StatefulSets.
# It uses 'kubectl patch --type=merge' with 'jq' to modify the StatefulSet definition,
# then triggers a 'kubectl rollout restart' to ensure all pods are updated
# with the new command (regardless of readiness). It then optionally restores
# the original command and triggers another rollout restart.

# --- Configuration ---
STATEFULSET_BASENAME="bee"
STATEFULSET_START_INDEX=1
STATEFULSET_END_INDEX=4
CONTAINER_INDEX=0 # Assumes the command is on the first container (index 0)
                  # Adjust this if the command you want to patch is in a different container.

# --- Functions ---

# Function to display error messages and exit
function error_exit {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to prompt for user input
function get_user_input {
    local prompt_message="$1"
    local variable_name="$2"
    read -p "$prompt_message" "$variable_name"
    if [[ -z "${!variable_name}" ]]; then
        error_exit "Input cannot be empty. Exiting."
    fi
}

# Function to convert a space-separated string into a JSON array string
# This is used for constructing the JSON payload for jq.
function to_json_array {
    local input_string="$1"
    # Split the input string by spaces into an array
    IFS=' ' read -r -a array <<< "$input_string"
    local json_array="["
    for i in "${!array[@]}"; do
        json_array+='"'
        json_array+="${array[$i]}"
        json_array+='"'
        if [[ "$i" -lt $(( ${#array[@]} - 1 )) ]]; then
            json_array+=','
        fi
    done
    json_array+="]"
    echo "$json_array"
}

# Function to display StatefulSet YAML for inspection
function display_statefulset_yaml {
    local namespace="$1"
    local sts_name="$2"
    echo ""
    echo "--- Displaying YAML for StatefulSet: $sts_name in namespace: $namespace ---"
    if ! kubectl get statefulset "$sts_name" -n "$namespace" -o yaml; then
        echo "ERROR: Could not retrieve YAML for StatefulSet '$sts_name'. Please check namespace and StatefulSet name."
        return 1 # Indicate failure
    fi
    echo "---------------------------------------------------------------------"
    echo ""
    echo "Look for 'spec.template.spec.containers' and then 'command' or 'args' fields."
    echo "The first container is index 0, the second is index 1, and so on."
    echo "Press Enter to continue..."
    read -r # Wait for user to press Enter
    return 0 # Indicate success
}

# --- Main Script ---

echo "--- Kubernetes StatefulSet Command Patcher ---"
echo ""

# Check for jq existence
if ! command -v jq &> /dev/null; then
    error_exit "jq command not found. Please install jq (e.g., 'brew install jq' or 'sudo apt-get install jq')."
fi

# 1. Prompt for Namespace
get_user_input "Enter the Kubernetes namespace for the StatefulSets: " NAMESPACE

# Optional: Inspect StatefulSet YAML
echo ""
read -p "Do you want to inspect the YAML of a StatefulSet before patching? (y/N): " INSPECT_CHOICE
INSPECT_CHOICE=${INSPECT_CHOICE:-N} # Default to No

if [[ "$INSPECT_CHOICE" =~ ^[Yy]$ ]]; then
    get_user_input "Enter the number of the StatefulSet to inspect (e.g., 1 for bee-1): " INSPECT_STS_NUM
    INSPECT_STATEFULSET_NAME="${STATEFULSET_BASENAME}-${INSPECT_STS_NUM}"
    if ! display_statefulset_yaml "$NAMESPACE" "$INSPECT_STATEFULSET_NAME"; then
        error_exit "Failed to display YAML. Exiting."
    fi
fi

# 2. Prompt for New Command
echo ""
echo "Enter the NEW command to temporarily apply to the StatefulSets."
echo "Example: 'sleep 3600' or 'ls -la /tmp'"
get_user_input "New command: " NEW_COMMAND_INPUT

# Convert the new command input into a JSON array string for jq
NEW_COMMAND_JSON=$(to_json_array "$NEW_COMMAND_INPUT")
echo "New command will be applied as: $NEW_COMMAND_JSON"
echo ""

# Loop through each StatefulSet
for i in $(seq "$STATEFULSET_START_INDEX" "$STATEFULSET_END_INDEX"); do
    STATEFULSET_NAME="${STATEFULSET_BASENAME}-${i}"
    echo "Processing StatefulSet: $STATEFULSET_NAME in namespace: $NAMESPACE"
    echo "--------------------------------------------------"

    # 3a. Get Original Command and Container Name
    echo "Retrieving original command and container name..."
    CONTAINER_NAME=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[${CONTAINER_INDEX}].name}" 2>/dev/null)
    if [[ -z "$CONTAINER_NAME" ]]; then
        error_exit "Could not determine container name at index ${CONTAINER_INDEX} for $STATEFULSET_NAME. Exiting."
    fi
    echo "Targeting container: $CONTAINER_NAME"

    ORIGINAL_COMMAND_EXISTS=false
    ORIGINAL_COMMAND_JSON="" # Will store original command as JSON array string

    # Get the current StatefulSet JSON
    CURRENT_STS_JSON=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    if [[ -z "$CURRENT_STS_JSON" ]]; then
        error_exit "Could not retrieve StatefulSet JSON for $STATEFULSET_NAME. Exiting."
    fi

    # Extract original command using jq
    TEMP_ORIGINAL_COMMAND_JSON=$(echo "$CURRENT_STS_JSON" | jq -c ".spec.template.spec.containers[${CONTAINER_INDEX}].command" 2>/dev/null)

    if [[ "$TEMP_ORIGINAL_COMMAND_JSON" != "null" && -n "$TEMP_ORIGINAL_COMMAND_JSON" ]]; then
        ORIGINAL_COMMAND_EXISTS=true
        ORIGINAL_COMMAND_JSON="$TEMP_ORIGINAL_COMMAND_JSON"
        echo "Original command: $ORIGINAL_COMMAND_JSON"
    else
        echo "Original 'command' field not found for $STATEFULSET_NAME. It will be added temporarily."
    fi

    # Get initial generation before patching
    INITIAL_GENERATION=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath="{.metadata.generation}" 2>/dev/null)
    echo "Initial metadata.generation: $INITIAL_GENERATION"

    # 3b. Apply New Command using kubectl patch --type=merge with jq
    echo "Applying new command: $NEW_COMMAND_JSON to container '$CONTAINER_NAME' using kubectl patch --type=merge with jq..."

    # Construct the merge patch JSON using jq to target the specific container by name
    # This creates a partial JSON that kubectl patch --type=merge will apply
    MERGE_PATCH_JSON=$(jq -n \
        --arg container_name "$CONTAINER_NAME" \
        --argjson new_cmd "$NEW_COMMAND_JSON" \
        '{spec: {template: {spec: {containers: [{name: $container_name, command: $new_cmd}]}}}}')

    echo "Merge Patch JSON being sent:"
    echo "$MERGE_PATCH_JSON" | jq .
    echo "---"

    if ! kubectl patch statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --type='merge' -p="$MERGE_PATCH_JSON"; then
        error_exit "Failed to patch $STATEFULSET_NAME with new command. Exiting."
    fi
    echo "Command patch applied. Triggering rollout restart to ensure all pods update..."

    # Verify generation change and command after first patch
    CURRENT_GENERATION=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath="{.metadata.generation}" 2>/dev/null)
    echo "Current metadata.generation after first patch: $CURRENT_GENERATION"
    if [[ "$CURRENT_GENERATION" -eq "$INITIAL_GENERATION" ]]; then
        echo "WARNING: metadata.generation did NOT increment after applying new command. The change might not have been registered."
    fi
    VERIFIED_COMMAND=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[${CONTAINER_INDEX}].command}" 2>/dev/null)
    echo "Verified command after first patch: $VERIFIED_COMMAND"


    # 3c. Trigger and Wait for Rollout Restart (New Command)
    echo "Executing 'kubectl rollout restart statefulset/$STATEFULSET_NAME'..."
    if ! kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE"; then
        echo "WARNING: Failed to trigger rollout restart for $STATEFULSET_NAME. Manual intervention may be required!"
    fi

    echo "Waiting for rollout restart to complete with new command (max 5m)..."
    # This will confirm that all pods have cycled, even if they crash.
    if ! kubectl rollout status statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" --timeout=5m; then
        echo "WARNING: Rollout restart for $STATEFULSET_NAME with new command did not complete within 5 minutes."
        echo "         This could mean pods are crashlooping or stuck. Manual verification of pod status is highly recommended."
    else
        echo "Rollout restart completed. All pods should now have attempted to run the new command."
    fi

    # 3d. Prompt to Restore Original Command
    echo ""
    read -p "Do you want to restore the original command for $STATEFULSET_NAME? (Y/n): " RESTORE_CHOICE
    RESTORE_CHOICE=${RESTORE_CHOICE:-Y} # Default to Yes

    if [[ "$RESTORE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Restoring original command..."
        GENERATION_BEFORE_RESTORE=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath="{.metadata.generation}" 2>/dev/null)
        echo "metadata.generation before restore: $GENERATION_BEFORE_RESTORE"

        # Get the current StatefulSet JSON again for restoration
        CURRENT_STS_JSON_FOR_RESTORE=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
        if [[ -z "$CURRENT_STS_JSON_FOR_RESTORE" ]]; then
            error_exit "Could not retrieve StatefulSet JSON for $STATEFULSET_NAME during restore. Exiting."
        fi

        local RESTORE_MERGE_PATCH_JSON=""

        if $ORIGINAL_COMMAND_EXISTS; then
            echo "Restoring original command: $ORIGINAL_COMMAND_JSON using kubectl patch --type=merge with jq..."
            RESTORE_MERGE_PATCH_JSON=$(jq -n \
                --arg container_name "$CONTAINER_NAME" \
                --argjson original_cmd "$ORIGINAL_COMMAND_JSON" \
                '{spec: {template: {spec: {containers: [{name: $container_name, command: $original_cmd}]}}}}')
        else
            echo "Original 'command' field was not present. Removing the temporary command using kubectl patch --type=merge with jq 'del'..."
            RESTORE_MERGE_PATCH_JSON=$(jq -n \
                --arg container_name "$CONTAINER_NAME" \
                '{spec: {template: {spec: {containers: [{name: $container_name, command: null}]}}}}') # Setting to null removes the field in merge patch
        fi

        echo "Restore Merge Patch JSON being sent:"
        echo "$RESTORE_MERGE_PATCH_JSON" | jq .
        echo "---"

        if ! kubectl patch statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --type='merge' -p="$RESTORE_MERGE_PATCH_JSON"; then
            error_exit "Failed to restore original command for $STATEFULSET_NAME. Manual intervention may be required!"
        fi

        echo "Restore applied. Triggering rollout restart to ensure pods revert to original command..."
        if ! kubectl rollout restart statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE"; then
            echo "WARNING: Failed to trigger rollout restart for $STATEFULSET_NAME during restore. Manual intervention may be required!"
        fi

        echo "Waiting for rollout restart to complete with original command (waiting for readiness)..."
        # 3e. Wait for Second Rolling Restart to Complete (Original Command) - Using kubectl rollout status for readiness
        if ! kubectl rollout status statefulset/"$STATEFULSET_NAME" -n "$NAMESPACE" --timeout=5m; then
            echo "WARNING: Rollout for $STATEFULSET_NAME with original command did not complete within 5 minutes."
            echo "         Manual verification is recommended. Pods might be stuck or crashlooping even after restore."
        else
            echo "Rollout completed. $STATEFULSET_NAME is back to its original command and pods are ready."
        fi
    else
        echo "Skipping restore for $STATEFULSET_NAME. The new command will remain applied."
    fi

    echo ""
done

echo "--- Script Finished ---"
echo "All specified StatefulSets have been processed."
echo "Please verify the state of your pods if any warnings were displayed."