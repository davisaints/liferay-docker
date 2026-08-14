#!/bin/bash

source ../_liferay_common.sh
source ../_release_common.sh

function check_liferay_marketplace_products_compatibility {
	if [ "${LIFERAY_RELEASE_DEVELOPER_MODE}" == "true" ]
	then
		lc_log INFO "Skipping the Liferay Marketplace products compatibility check because LIFERAY_RELEASE_DEVELOPER_MODE is set to \"true\"."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if ! is_first_quarterly_release
	then
		lc_log INFO "The compatibility of Liferay Marketplace products should not be checked on the ${_PRODUCT_VERSION} release."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	mkdir --parents "${_BUILD_DIR}/deploy"

	if [ -z "${LIFERAY_RELEASE_TEST_MODE}" ]
	then
		_set_liferay_marketplace_oauth2_token

		if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi

		mkdir --parents "${_BUILD_DIR}/marketplace"

		declare -A LIFERAY_MARKETPLACE_PRODUCTS=(
			["adyen"]="f05ab2d6-1d54-c72d-988a-91fcd5669ef3"
			["drools"]="15099181"
			["hubspot"]="53d5501f-abd7-b579-af7f-56b8b15966d0"
			["liferaycommerceminium4globalcss"]="ebcf98b3-9844-b783-757a-579944b18b00"
			["liferaypaypalbatch"]="a1946869-212f-0793-d703-b623d0f149a6"
			["liferayupscommerceshippingengine"]="f1cb4b5e-fbdd-7f70-df5d-9f1a736784b2"
			["opensearch"]="ea19fdc8-b908-690d-9f90-15edcdd23a87"
			["punchout"]="175496027"
			["stripe"]="6a02a832-083b-f08c-888a-0a59d7c09119"
		)
	fi

	for liferay_marketplace_product_name in $(printf "%s\n" "${!LIFERAY_MARKETPLACE_PRODUCTS[@]}" | sort --ignore-case)
	do
		if [ -z "${LIFERAY_RELEASE_TEST_MODE}" ]
		then
			lc_log INFO "Downloading Liferay Marketplace product ${liferay_marketplace_product_name}."

			_download_product_by_external_reference_code "${LIFERAY_MARKETPLACE_PRODUCTS[${liferay_marketplace_product_name}]}" "${liferay_marketplace_product_name}"

			if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
			then
				return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
			fi
		fi

		if [ "${liferay_marketplace_product_name}" == "punchout" ]
		then
			_deploy_punchout2go_activation_key

			if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
			then
				return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
			fi
		fi

		lc_log INFO "Preparing Liferay Marketplace product zip file ${liferay_marketplace_product_name}.zip for deployment to ${LIFERAY_DOCKER_IMAGE_NAME}.\n"

		_deploy_liferay_marketplace_product_zip_file "${_BUILD_DIR}/marketplace/${liferay_marketplace_product_name}.zip"

		if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done

	_LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE="${_BUILD_DIR}/log_$(date +%s)_liferay_marketplace_products_deployment.txt"

	_start_liferay_container

	if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
	then
		_stop_liferay_container

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	docker logs "${_LIFERAY_MARKETPLACE_CONTAINER_ID}" &> "${_LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE}"

	for liferay_marketplace_product_name in $(printf "%s\n" "${!LIFERAY_MARKETPLACE_PRODUCTS[@]}" | sort --ignore-case)
	do
		_check_liferay_marketplace_product_compatibility "${LIFERAY_MARKETPLACE_PRODUCTS[${liferay_marketplace_product_name}]}" "${liferay_marketplace_product_name}"

		if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
		then
			_stop_liferay_container

			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi

		if [ "${liferay_marketplace_product_name}" == "punchout" ]
		then
			_check_punchout2go_activation_key

			if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
			then
				_stop_liferay_container

				return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
			fi
		fi
	done

	_stop_liferay_container
}

function check_usage {
	if [ -z "${LIFERAY_DOCKER_IMAGE_NAME}" ]
	then
		print_help
	fi

	_PRODUCT_VERSION=$( \
		echo "${LIFERAY_DOCKER_IMAGE_NAME}" | \
		cut --delimiter=':' --fields=2 | \
		cut --delimiter='-' --fields=1)

	_BUILD_DIR=$(mktemp --directory)
}

function main {
	if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
	then
		return
	fi

	check_usage

	lc_time_run check_liferay_marketplace_products_compatibility

	local exit_code=${?}

	rm --force --recursive "${_BUILD_DIR}"

	return "${exit_code}"
}

function print_help {
	echo "Usage: LIFERAY_DOCKER_IMAGE_NAME=<<liferay_docker_image_name>> ${0}"
	echo ""
	echo "The script reads the following environment variables:"
	echo ""
	echo "    LIFERAY_DOCKER_IMAGE_NAME: Liferay Docker image name to check Marketplace product compatibility against"
	echo "    LIFERAY_RELEASE_DEVELOPER_MODE (optional): Set this to \"true\" to skip the compatibility check"
	echo "    LIFERAY_RELEASE_TEST_MODE (optional): Set this to skip downloading and deploying Marketplace products"
	echo "    LIFERAY_RELEASE_UPLOAD (optional): Set this to \"true\" to update the list of supported versions on Marketplace"
	echo ""
	echo "Example: LIFERAY_DOCKER_IMAGE_NAME=liferay/release-candidates:2026.q1.0-123456789 ${0}"

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

function _check_liferay_marketplace_product_compatibility {
	local product_external_reference_code=${1}
	local product_name=${2}

	lc_log INFO "Checking the compatibility of Liferay Marketplace product ${product_name} with ${_PRODUCT_VERSION} release."

	if [ ! -f "${_BUILD_DIR}/marketplace/${product_name}.zip" ]
	then
		lc_log ERROR "Unable to check the compatibility of Liferay Marketplace product ${product_name} because the product zip file ${product_name}.zip was not downloaded.\n"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local modules_info=$(blade sh --host localhost --port "${_LIFERAY_MARKETPLACE_CONTAINER_OSGI_CONSOLE_PORT}" lb -s | grep "${product_name}")

	if [ -z "${modules_info}" ]
	then
		lc_log ERROR "Unable to check the compatibility of Liferay Marketplace product ${product_name}.\n"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	if echo "${modules_info}" | grep --extended-regexp --invert-match "Active|Resolved" &> /dev/null
	then
		lc_log ERROR "One or more modules of Liferay Marketplace product ${product_name} are not compatible with release ${_PRODUCT_VERSION}:"

		while IFS= read -r module_info
		do
			local module_name=$( \
				echo "${module_info}" | \
				cut --delimiter "|" --fields=4 | \
				sed --expression "s/ (.*)//" | \
				xargs)

			lc_log ERROR "Module ${module_name} is not compatible with release ${_PRODUCT_VERSION}."

			local module_id=$( \
				echo "${module_info}" | \
				cut --delimiter "|" --fields=1 | \
				xargs)

			lc_log INFO "OSGI diagnostics: $( \
				blade sh --host localhost --port "${_LIFERAY_MARKETPLACE_CONTAINER_OSGI_CONSOLE_PORT}" diag "${module_id}" | \
				tail --lines=+3 | \
				xargs)"

			if grep --quiet "${module_name}" "${_LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE}"
			then
				lc_log INFO "Deployment logs for ${module_name}:"

				cat "${_LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE}" | grep "${module_name}"
			fi
		done <<< "${modules_info}"

		echo ""

		return
	fi

	if [ -z "${LIFERAY_RELEASE_TEST_MODE}" ]
	then
		lc_log INFO "Module ${product_name} is compatible with release ${_PRODUCT_VERSION}. Updating list of supported versions."

		_update_product_supported_versions "${product_external_reference_code}" "${product_name}"
	fi
}

function _check_punchout2go_activation_key {
	if grep --quiet "Liferay Commerce Connector to PunchOut2Go license validation passed" "${_LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE}"
	then
		lc_log INFO "The Punchout2Go activation key was processed successfully."

		return "${LIFERAY_COMMON_EXIT_CODE_OK}"
	fi

	lc_log ERROR "Unable to process the Punchout2Go activation key."

	return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
}

function _deploy_liferay_marketplace_product_zip_file {
	local liferay_marketplace_product_zip_file_path=${1}

	if [ ! -f "${liferay_marketplace_product_zip_file_path}" ]
	then
		lc_log ERROR "The Liferay Marketplace product zip file ${liferay_marketplace_product_zip_file_path} does not exist."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	if unzip -l "${liferay_marketplace_product_zip_file_path}" | grep "client-extension" &> /dev/null
	then
		cp "${liferay_marketplace_product_zip_file_path}" "${_BUILD_DIR}/deploy"
	elif unzip -l "${liferay_marketplace_product_zip_file_path}" | grep "\.lpkg$" &> /dev/null
	then
		unzip \
			-d "${_BUILD_DIR}/deploy" \
			-j \
			-o \
			-q \
			"${liferay_marketplace_product_zip_file_path}" "*.lpkg" \
			-x "*/*" 2> /dev/null
	elif unzip -l "${liferay_marketplace_product_zip_file_path}" | grep "\.zip$" &> /dev/null
	then
		unzip \
			-d "${_BUILD_DIR}/deploy" \
			-j \
			-o \
			-q \
			"${liferay_marketplace_product_zip_file_path}" "*.zip" \
			-x "*/*" 2> /dev/null
	fi

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to deploy $(basename "${liferay_marketplace_product_zip_file_path}") to ${_BUILD_DIR}/deploy."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _deploy_punchout2go_activation_key {
	local activation_key_year=$(date +%Y)

	if [[ "$(date +%-m)" -lt 4 ]]
	then
		activation_key_year=$((activation_key_year - 1))
	fi

	local activation_key_file_path=$(_get_punchout2go_activation_key "${activation_key_year}")

	if [ ! -f "${activation_key_file_path}" ]
	then
		lc_log ERROR "Unable to deploy the Punchout2Go activation key for ${activation_key_year} because the activation key is not set or the file does not exist."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	lc_log INFO "Deploying the Punchout2Go activation key for ${activation_key_year} to ${_BUILD_DIR}/deploy."

	cp "${activation_key_file_path}" "${_BUILD_DIR}/deploy"

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to deploy the Punchout2Go activation key."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _download_product {
	local product_download_url=${1}
	local product_file_name=${2}

	local http_code=$( \
		curl \
			--header "Authorization: Bearer ${_LIFERAY_MARKETPLACE_OAUTH2_TOKEN}" \
			--location \
			--output "${_BUILD_DIR}/marketplace/${product_file_name}" \
			--request GET \
			--retry 3 \
			--retry-delay 10 \
			--silent \
			--write-out "%{http_code}" \
			"https://marketplace.liferay.com/${product_download_url}")

	if [[ "${http_code}" -ge 400 ]]
	then
		lc_log ERROR "Unable to download product ${product_file_name}. HTTP response code was ${http_code}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _download_product_by_external_reference_code {
	local product_external_reference_code=${1}
	local product_file_name=${2}

	local product_virtual_settings_file_entries=$(_get_product_virtual_settings_file_entries_by_external_reference_code "${product_external_reference_code}")

	if [ -z "${product_virtual_settings_file_entries}" ]
	then
		lc_log ERROR "Unable to get product virtual settings file entries."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local latest_product_virtual_settings_file_entry_json_index=$(_get_latest_product_virtual_settings_file_entry_json_index "${product_virtual_settings_file_entries}")

	if [ -z "${latest_product_virtual_settings_file_entry_json_index}" ]
	then
		lc_log ERROR "Unable to get JSON index for the latest product virtual settings file entry."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local product_download_url=$( \
		echo "${product_virtual_settings_file_entries}" | \
		jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].src" | \
		sed --expression "s|^/||")

	_download_product "${product_download_url}" "${product_file_name}.zip"

	if [[ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _get_latest_product_virtual_settings_file_entry_json_index {
	local product_virtual_settings_file_entries=${1}

	local latest_product_virtual_settings_file_entry_json_index=$( \
		echo "${product_virtual_settings_file_entries}" | \
		jq ".items
			| to_entries
			| map(
				select(
					(.value.version // \"\")
					| test(\"Q[1-4]|7[.][0-4]\")
				)
			)
			| max_by([
				(.value.version | test(\"Q\")),
				(.value.version | split(\", \") | max)
			])
			| .key?")

	if [ "${latest_product_virtual_settings_file_entry_json_index}" == "null" ]
	then
		echo ""

		return
	fi

	echo "${latest_product_virtual_settings_file_entry_json_index}"
}

function _get_product_by_external_reference_code {
	local product_external_reference_code=${1}

	local http_code_file=$(mktemp)

	local product=$( \
		curl \
			--header "Authorization: Bearer ${_LIFERAY_MARKETPLACE_OAUTH2_TOKEN}" \
			--request GET \
			--retry 3 \
			--retry-delay 10 \
			--silent \
			--write-out "%output{${http_code_file}}%{http_code}" \
			"https://marketplace.liferay.com/o/headless-commerce-admin-catalog/v1.0/products/by-externalReferenceCode/${product_external_reference_code}?nestedFields=productVirtualSettings%2Cattachments")

	local http_code=$(cat "${http_code_file}")

	if [[ "${http_code}" -ge 400 ]]
	then
		echo ""

		rm --force "${http_code_file}"

		return
	fi

	rm --force "${http_code_file}"

	echo "${product}"
}

function _get_product_virtual_settings_file_entries_by_external_reference_code {
	local product_external_reference_code=${1}

	local product=$(_get_product_by_external_reference_code "${product_external_reference_code}")

	if [ -z "${product}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local product_virtual_settings_id=$(echo "${product}" | jq --raw-output ".productVirtualSettings.id")

	local http_code_file=$(mktemp)

	local product_virtual_settings_file_entries=$( \
		curl \
			--header "Authorization: Bearer ${_LIFERAY_MARKETPLACE_OAUTH2_TOKEN}" \
			--request GET \
			--retry 3 \
			--retry-delay 10 \
			--silent \
			--write-out "%output{${http_code_file}}%{http_code}" \
			"https://marketplace.liferay.com/o/headless-commerce-admin-catalog/v1.0/product-virtual-settings/${product_virtual_settings_id}/product-virtual-settings-file-entries?pageSize=20")

	local http_code=$(cat "${http_code_file}")

	if [[ "${http_code}" -ge 400 ]]
	then
		echo ""

		rm --force "${http_code_file}"

		return
	fi

	rm --force "${http_code_file}"

	echo "${product_virtual_settings_file_entries}"
}

function _get_punchout2go_activation_key {
	local activation_key_year=${1}

	if [[ "${activation_key_year}" -eq 2026 ]]
	then
		echo "${LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_2026}"
	elif [[ "${activation_key_year}" -eq 2027 ]]
	then
		echo "${LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_2027}"
	elif [[ "${activation_key_year}" -eq 2028 ]]
	then
		echo "${LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_2028}"
	elif [[ "${activation_key_year}" -eq 2029 ]]
	then
		echo "${LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_2029}"
	fi
}

function _set_liferay_marketplace_oauth2_token {
	local http_code_file=$(mktemp)

	local liferay_marketplace_oauth2_token_response=$( \
		curl \
			--data "client_id=${LIFERAY_MARKETPLACE_OAUTH2_CLIENT_ID}&client_secret=${LIFERAY_MARKETPLACE_OAUTH2_CLIENT_SECRET}&grant_type=client_credentials" \
			--request POST \
			--retry 3 \
			--retry-delay 10 \
			--silent \
			--write-out "%output{${http_code_file}}%{http_code}" \
			"https://marketplace.liferay.com/o/oauth2/token")

	local http_code=$(cat "${http_code_file}")

	if [[ "${http_code}" -ge 400 ]]
	then
		lc_log ERROR "Unable to get Liferay Marketplace OAuth2 token. HTTP response code was ${http_code}."

		rm --force "${http_code_file}"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	rm --force "${http_code_file}"

	_LIFERAY_MARKETPLACE_OAUTH2_TOKEN=$(echo "${liferay_marketplace_oauth2_token_response}" | jq --raw-output ".access_token")
}

function _start_liferay_container {
	lc_log INFO "Pulling ${LIFERAY_DOCKER_IMAGE_NAME}."

	docker pull "${LIFERAY_DOCKER_IMAGE_NAME}"

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to pull ${LIFERAY_DOCKER_IMAGE_NAME}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	lc_log INFO "Starting a container from ${LIFERAY_DOCKER_IMAGE_NAME}."

	_LIFERAY_MARKETPLACE_CONTAINER_ID=$( \
		docker run \
			--detach \
			--publish 8080 \
			--publish 11311 \
			--volume "${_BUILD_DIR}/deploy:/opt/liferay/deploy:rw" \
			"${LIFERAY_DOCKER_IMAGE_NAME}")

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to start a container from ${LIFERAY_DOCKER_IMAGE_NAME}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	_LIFERAY_MARKETPLACE_CONTAINER_OSGI_CONSOLE_PORT=$( \
		docker port "${_LIFERAY_MARKETPLACE_CONTAINER_ID}" 11311/tcp | \
		awk -F ":" 'END {print $NF}')

	lc_log INFO "Waiting for the container to become healthy..."

	local health_status

	for count in {1..200}
	do
		health_status=$(docker inspect --format="{{json .State.Health.Status}}" "${_LIFERAY_MARKETPLACE_CONTAINER_ID}")

		if [ "${health_status}" == "\"healthy\"" ]
		then
			lc_log INFO "Startup was successful."

			return
		fi

		sleep 3
	done

	lc_log ERROR "Unable to start the container from ${LIFERAY_DOCKER_IMAGE_NAME} in 600 seconds. Health status is: ${health_status}."

	docker logs "${_LIFERAY_MARKETPLACE_CONTAINER_ID}"

	return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
}

function _stop_liferay_container {
	lc_log INFO "Stopping the container."

	docker kill "${_LIFERAY_MARKETPLACE_CONTAINER_ID}" &> /dev/null

	docker rm "${_LIFERAY_MARKETPLACE_CONTAINER_ID}" &> /dev/null
}

function _update_product_supported_versions {
	if [ "${LIFERAY_RELEASE_UPLOAD}" != "true" ]
	then
		lc_log INFO "Set the environment variable LIFERAY_RELEASE_UPLOAD to \"true\" to enable."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local product_external_reference_code=${1}
	local product_name=${2}

	local product_virtual_settings_file_entries=$(_get_product_virtual_settings_file_entries_by_external_reference_code "${product_external_reference_code}")

	local latest_product_virtual_settings_file_entry_json_index=$(_get_latest_product_virtual_settings_file_entry_json_index "${product_virtual_settings_file_entries}")

	local latest_product_virtual_file_entry_version=$(echo "${product_virtual_settings_file_entries}" | jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].version")

	local product_virtual_file_entry_target_version=$( \
		get_product_group_version | \
		tr "." " " | \
		tr "[:lower:]" "[:upper:]")

	if [[ "${latest_product_virtual_file_entry_version}" != *"${product_virtual_file_entry_target_version}"* ]]
	then
		local latest_product_virtual_file_entry_id=$(echo "${product_virtual_settings_file_entries}" | jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].id")

		local http_code=$( \
			curl \
				--form "productVirtualSettingsFileEntry={\"version\": \"${latest_product_virtual_file_entry_version}, ${product_virtual_file_entry_target_version}\"};type=application/json" \
				--header "Authorization: Bearer ${_LIFERAY_MARKETPLACE_OAUTH2_TOKEN}" \
				--output /dev/null \
				--request PATCH \
				--retry 3 \
				--retry-delay 10 \
				--silent \
				--write-out "%{http_code}" \
				"https://marketplace.liferay.com/o/headless-commerce-admin-catalog/v1.0/product-virtual-settings-file-entries/${latest_product_virtual_file_entry_id}")

		if [[ "${http_code}" -ge 400 ]]
		then
			lc_log ERROR "Unable to update the list of supported versions for product ${product_name}. HTTP response code was ${http_code}.\n"

			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi

		local data=$(
			cat <<- END
			{
				"specificationKey": "liferay-version",
				"value": {
					"en_US": "${product_virtual_file_entry_target_version}"
				}
			}
			END
		)

		http_code=$( \
			curl \
				--data "${data}" \
				--header "Authorization: Bearer ${_LIFERAY_MARKETPLACE_OAUTH2_TOKEN}" \
				--header "Content-Type: application/json" \
				--header "accept: application/json" \
				--header "x-csrf-token: ${LIFERAY_MARKETPLACE_CSRF_TOKEN}" \
				--output /dev/null \
				--request POST \
				--retry 3 \
				--retry-delay 10 \
				--silent \
				--write-out "%{http_code}" \
				"https://marketplace.liferay.com/o/headless-commerce-admin-catalog/v1.0/products/by-externalReferenceCode/${product_external_reference_code}/product-specifications")

		if [[ "${http_code}" -ge 400 ]]
		then
			lc_log ERROR "Unable to update the list of supported versions in the product specifications for product ${product_name}. HTTP response code was ${http_code}.\n"

			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi

		lc_log INFO "The supported versions list was successfully updated for product ${product_name} to include the ${product_virtual_file_entry_target_version} release.\n"
	else
		lc_log INFO "The supported versions list for product ${product_name} already contains the ${product_virtual_file_entry_target_version} release.\n"
	fi
}

main "${@}"
