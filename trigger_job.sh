#!/bin/bash

function main {
    trigger_job

    wait_for_build
}

base_url="http://localhost:8080"
TOKEN='11b6a75b77646ff7d5f96284893aa16cba'

function trigger_job {
    local http_code=$(
        curl \
            "${base_url}/job/my-job/build" \
            --output /dev/null -w "%{http_code}" \
            --request POST \
            --silent \
            --user "jenkins:${TOKEN}")

    echo "Job run response: ${http_code}"

    if [ "${http_code}" -ne 201 ]
    then
        echo "Unable to trigger release job"

        return 1
    fi

    echo "Job triggered successfully."
}

function wait_for_build {
    echo "Waiting for Job to start..."

    while true
    do
        local curl_response=$(
            curl \
                "${base_url}/queue/api/json" \
                --request GET \
                --silent \
                --user "jenkins:${TOKEN}")
    
        local build_number=$(echo "${curl_response}" | jq -r '.items[0].id')

        if [[ "${build_number}" != "null" && -n "${build_number}" ]]
        then
            echo "Job started with build number: ${build_number}"
            monitor_build "${build_number}"
            return
        fi

        sleep 5
    done
}

function monitor_build {
    local build_id=$1

    while true
    do
        local curl_response=$(
            curl \
            "${base_url}/job/my-job/${build_id}/api/json" \
            --request GET \
            --silent \
            --user "jenkins:${TOKEN}"
        )

        if [[ "${curl_response}" == *"Not Found"* ]]
        then
            echo "Build not found, retrying in 5 seconds..."
            sleep 5
            continue
        fi

        local build_result=$(echo "${curl_response}" | jq -r '.result')

        if [[ "${build_result}" == "SUCCESS" ]]
        then
            echo "Job completed successfully!"
            return 0
        elif [[ "${build_result}" == "FAILURE" || "${build_result}" == "ABORTED" ]]
        then
            echo "Job failed with status: ${build_result}"
            return 1
        fi
    done
}

main
