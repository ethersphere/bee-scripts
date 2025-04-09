#!/bin/bash

# Base URL
base_url="http:/localhost:1633/chunks"

# Check if the file path is provided as a command-line argument
if [ -z "$1" ]; then
    echo "Usage: $0 <file_path>"
    exit 1
fi

# Assign the command-line argument to file_path
file_path="$1"

# Read each line from the file
while IFS= read -r line
do
    # Construct the full URL
    url="${base_url}/${line}"
    # echo $url

    # Limit the number of parallel jobs to 50
    while [ "$(jobs | wc -l)" -ge 100 ]; do
        wait -n
    done

    # Run the curl command in the background
    {
        # Check the HTTP status code
        status_code=$(curl -o /dev/null -s -w "%{http_code}\n" "$url")
        if [ "$status_code" -eq 200 ]; then
            echo "ok"
        else
            echo "fail"
        fi

        # response=$(curl "$url" -s)
        # is_retrievable=$(echo "$response" | jq -r '.isRetrievable')
        # if [ "$is_retrievable" == "true" ]; then
        #     echo "ok"
        # else
        #     echo "fail"
        # fi
    } &

done < "$file_path"
