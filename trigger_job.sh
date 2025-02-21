#!/bin/bash

function main {
    trigger_job

    wait_for_build
}

JENKINS_API_TOKEN='11b6a75b77646ff7d5f96284893aa16cba'
JENKINS_URL="http://localhost:8080"
JENKINS_USER="jenkins"
JOB_NAME="my-job"

function trigger_job {
    local http_code=$(
        curl \
            "${JENKINS_URL}/job/${JOB_NAME}/build" \
            --output /dev/null -w "%{http_code}" \
            --request POST \
            --silent \
            --user "${JENKINS_USER}:${JENKINS_API_TOKEN}")

    if [ "${http_code}" -ne 201 ]
    then
        echo "Unable to trigger ${JOB_NAME}"

        return 1
    fi

    echo "${JOB_NAME} triggered successfully."
}

function wait_for_build {
    echo "Waiting for ${JOB_NAME} to start..."

    while true
    do
        local curl_response=$(
            curl \
                "${JENKINS_URL}/queue/api/json" \
                --request GET \
                --silent \
                --user "${JENKINS_USER}:${JENKINS_API_TOKEN}")
    
        local build_number=$(echo "${curl_response}" | jq -r '.items[0].id')

        if [[ "${build_number}" != "null" && -n "${build_number}" ]]
        then
            echo "${JOB_NAME} started with build number: ${build_number}"
            wait_for_job_results "${build_number}"
            return
        fi

        sleep 5
    done
}

function wait_for_job_results {
    local build_id=$1

    while true
    do
        local curl_response=$(
            curl \
            "${JENKINS_URL}/job/${JOB_NAME}/${build_id}/api/json" \
            --request GET \
            --silent \
            --user "${JENKINS_USER}:${JENKINS_API_TOKEN}"
        )

        if [[ "${curl_response}" == *"Not Found"* ]]
        then
            echo "Build is still in progress, retrying in 5 seconds..."
            sleep 5
            continue
        fi

        local build_result=$(echo "${curl_response}" | jq -r '.result')

        if [[ "${build_result}" == "SUCCESS" ]]
        then
            echo "${JOB_NAME} completed successfully with status: ${build_result}"
            return 0
        elif [[ "${build_result}" == "FAILURE" || "${build_result}" == "ABORTED" ]]
        then
            echo "${JOB_NAME} failed with status: ${build_result}"
            return 1
        fi
    done
}

main
