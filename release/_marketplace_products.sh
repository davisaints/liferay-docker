#!/bin/bash

source ../_liferay_common.sh
source ../_release_common.sh
source ./_product.sh

function test_marketplace_products_compatibility {
	if ! is_first_quarterly_release
	then
		lc_log INFO "Marketplace products should not be tested on the ${_PRODUCT_VERSION} release."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	declare -A PRODUCT_EXTERNAL_REFERENCE_CODES=(
		["Liferay Commerce Connector to PunchOut2Go - API"]="175496027"
		["Liferay Commerce Connector to PunchOut2Go - Impl"]="175496027"
		["Liferay Connector to OpenSearch 2 - API"]="ea19fdc8-b908-690d-9f90-15edcdd23a87"
		["Liferay Connector to OpenSearch 2 - Impl"]="ea19fdc8-b908-690d-9f90-15edcdd23a87"
		["Liferay Connector to Solr 8 - API"]="30536632"
		["Liferay Connector to Solr 8 - Impl"]="30536632"
		["Liferay Drools - Impl"]="15099181"
		["liferayadyenbatch"]="f05ab2d6-1d54-c72d-988a-91fcd5669ef3"
		["liferayadyencommercepaymentintegration"]="f05ab2d6-1d54-c72d-988a-91fcd5669ef3"
		["liferaycommerceminium4globalcss"]="bee3adc0-891c-5828-c4f6-3d244135c972"
		["liferaypaypalbatch"]="a1946869-212f-0793-d703-b623d0f149a6"
		["liferayupscommerceshippingengine"]="f1cb4b5e-fbdd-7f70-df5d-9f1a736784b2"
		["stripe"]="6a02a832-083b-f08c-888a-0a59d7c09119"
	)

	_get_oauth2_token

	if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	mkdir --parents "${_BUILD_DIR}/marketplace"

	for product_external_reference_code in $(printf "%s\n" "${PRODUCT_EXTERNAL_REFERENCE_CODES[@]}" | sort --unique)
	do
		lc_log INFO "Downloading product ${product_external_reference_code}."

		_download_product_by_external_reference_code "${product_external_reference_code}"

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi

		lc_log INFO "Copying product zip file ${product_external_reference_code}.zip to ${_BUNDLES_DIR}/deploy."

		_copy_to_deploy_folder "${_BUILD_DIR}/marketplace/${product_external_reference_code}.zip"

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done

	rm --force "${_BUILD_DIR}/warm-up-tomcat"

	warm_up_tomcat &> /dev/null

	echo "include-and-override=portal-developer.properties" > "${_BUNDLES_DIR}/portal-ext.properties"

	start_tomcat &> /dev/null

	while IFS= read -r product_module_name
	do
		_test_product_module "${PRODUCT_EXTERNAL_REFERENCE_CODES[${product_module_name}]}" "${product_module_name}"

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done < <(printf "%s\n" "${!PRODUCT_EXTERNAL_REFERENCE_CODES[@]}" | sort --ignore-case)

	stop_tomcat &> /dev/null
}

function _copy_to_deploy_folder {
	local product_zip_file_path=${1}

	if [ ! -f "${product_zip_file_path}" ]
	then
		lc_log ERROR "The product zip file ${product_zip_file_path} does not exist."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if (unzip -l "${product_zip_file_path}" | grep "client-extension" &>/dev/null)
	then
		cp "${product_zip_file_path}" "${_BUNDLES_DIR}/deploy"
	elif (unzip -l "${product_zip_file_path}" | grep "\.lpkg$" &>/dev/null)
	then
		unzip \
			-d "${_BUNDLES_DIR}/deploy" \
			-j \
			-o \
			-q \
			"${product_zip_file_path}" "*.lpkg" \
			-x "*/*" 2> /dev/null
	elif (unzip -l "${product_zip_file_path}" | grep "\.zip$" &>/dev/null)
	then
		unzip \
			-d "${_BUNDLES_DIR}/deploy" \
			-j \
			-o \
			-q \
			"${product_zip_file_path}" "*.zip" \
			-x "*/*" 2> /dev/null
	fi

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to copy file $(basename "${product_zip_file_path}") to ${_BUNDLES_DIR}/deploy."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _download_product {
	local product_download_url=${1}
	local product_file_name=${2}

	local http_status_code_file=$(mktemp)

	curl \
		"https://marketplace-uat.liferay.com/${product_download_url}" \
		--header "Authorization: Bearer ${MARKETPLACE_OAUTH2_TOKEN}" \
		--location \
		--output "${_BUILD_DIR}/marketplace/${product_file_name}" \
		--request GET \
		--silent \
		--write-out "%output{${http_status_code_file}}%{http_code}"

	http_status_code=$(cat "${http_status_code_file}")

	if [[ "${http_status_code}" -ge 400 ]]
	then
		lc_log ERROR "Unable to download product ${product_file_name}. HTTP status: ${http_status_code}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _download_product_by_external_reference_code {
	local product_external_reference_code=${1}

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

	local product_download_url="$(echo "${product_virtual_settings_file_entries}" | jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].src" | sed "s|^/||")"
	local product_file_name="${product_external_reference_code}.zip"

	_download_product "${product_download_url}" "${product_file_name}"

	if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _get_latest_product_virtual_settings_file_entry_json_index {
	local product_virtual_settings_file_entries=${1}

	local latest_product_virtual_settings_file_entry_json_index=$(
		echo "${product_virtual_settings_file_entries}" |
		jq ".items
			| to_entries
			| map(
				select(
					(.value.version // \"\")
					| test(\"Q[1-4]|7[.][1-4]\")
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

function _get_oauth2_token {
	local http_status_code_file=$(mktemp)

	local oauth2_token_response=$(\
		curl \
			"https://marketplace-preprod.lxc.liferay.com/o/oauth2/token" \
			--data "client_id=${MARKETPLACE_OAUTH2_CLIENT_ID}&client_secret=${MARKETPLACE_OAUTH2_CLIENT_SECRET}&grant_type=client_credentials" \
			--request POST \
			--silent \
			--write-out "%output{${http_status_code_file}}%{http_code}")

	http_status_code=$(cat "${http_status_code_file}")

	if [[ "${http_status_code}" -ge 400 ]]
	then
		lc_log ERROR "Unable to get Marketplace OAuth2 token. HTTP status: ${http_status_code}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	MARKETPLACE_OAUTH2_TOKEN=$(echo "${oauth2_token_response}" | jq --raw-output ".access_token")
}

function _get_product_by_external_reference_code {
	local product_external_reference_code="${1}"

	local http_status_code_file=$(mktemp)

	local product_response=$(\
		curl \
			"https://marketplace-uat.liferay.com/o/headless-commerce-admin-catalog/v1.0/products/by-externalReferenceCode/${product_external_reference_code}?nestedFields=productVirtualSettings%2Cattachments" \
			--header "Authorization: Bearer ${MARKETPLACE_OAUTH2_TOKEN}" \
			--request GET \
			--silent \
			--write-out "%output{${http_status_code_file}}%{http_code}")

	local http_status_code=$(cat "${http_status_code_file}")

	if [[ "${http_status_code}" -ge 400 ]]
	then
		echo ""

		return
	fi

	echo "${product_response}"
}

function _get_product_virtual_settings_file_entries_by_external_reference_code {
	local product_external_reference_code=${1}

	local product_response=$(_get_product_by_external_reference_code "${product_external_reference_code}")

	if [ -z "${product_response}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local product_virtual_settings_id=$(echo "${product_response}" | jq --raw-output ".productVirtualSettings.id")

	local http_status_code_file=$(mktemp)

	local product_virtual_file_entries_response=$(\
		curl \
			"https://marketplace-uat.liferay.com/o/headless-commerce-admin-catalog/v1.0/product-virtual-settings/${product_virtual_settings_id}/product-virtual-settings-file-entries?pageSize=20" \
			--header "Authorization: Bearer ${MARKETPLACE_OAUTH2_TOKEN}" \
			--request GET \
			--silent \
			--write-out "%output{${http_status_code_file}}%{http_code}")

	local http_status_code=$(cat "${http_status_code_file}")

	if [[ "${http_status_code}" -ge 400 ]]
	then
		echo ""

		return
	fi

	echo "${product_virtual_file_entries_response}"
}

function _test_product_module {
	local product_external_reference_code=${1}
	local product_module_name=${2}

	lc_log INFO "Testing the compatibility of '${product_module_name}' with ${_PRODUCT_VERSION} release."

	if [ ! -f "${_BUILD_DIR}/marketplace/${product_external_reference_code}.zip" ]
	then
		lc_log ERROR "Unable to test product '${product_module_name}' because the product zip file ${product_external_reference_code}.zip was not downloaded."

		return
	fi

	local module_info=$(blade sh lb -s | grep "${product_module_name}")

	if (echo "${module_info}" | grep --extended-regexp "Active|Resolved" &> /dev/null)
	then
		lc_log INFO "Module '${product_module_name}' is compatible with release ${_PRODUCT_VERSION}."

		if [ -z "${LIFERAY_RELEASE_TEST_MODE}" ]
		then
			lc_log INFO "Updating list of supported versions for module '${product_module_name}'."

			_update_product_supported_versions "${product_external_reference_code}" "${product_module_name}"

			if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
			then
				return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
			fi
		fi

		return
	fi

	if (echo "${module_info}" | grep --extended-regexp --invert-match "Active|Resolved" &> /dev/null) || [ -n "${module_info}" ]
	then
		lc_log INFO "Module '${product_module_name}' is not compatible with release ${_PRODUCT_VERSION}."
	fi
}

function _update_product_supported_versions {
	local product_external_reference_code=${1}
	local product_module_name=${2}
	
	local product_virtual_settings_file_entries=$(_get_product_virtual_settings_file_entries_by_external_reference_code "${product_external_reference_code}")

	local latest_product_virtual_settings_file_entry_json_index=$(_get_latest_product_virtual_settings_file_entry_json_index "${product_virtual_settings_file_entries}")

	local latest_product_virtual_file_entry_version=$(echo "${product_virtual_settings_file_entries}" | jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].version")

	local product_virtual_file_entry_target_version=$(get_product_group_version | tr "." " " | tr "[:lower:]" "[:upper:]")

	if [[ "${latest_product_virtual_file_entry_version}" != *"${product_virtual_file_entry_target_version}"* ]]
	then
		local latest_product_virtual_file_entry_id=$(echo "${product_virtual_settings_file_entries}" | jq --raw-output ".items[${latest_product_virtual_settings_file_entry_json_index}].id")

		local http_response=$(\
			curl \
				"https://marketplace-uat.liferay.com/o/headless-commerce-admin-catalog/v1.0/product-virtual-settings-file-entries/${latest_product_virtual_file_entry_id}" \
				--form "productVirtualSettingsFileEntry={\"version\": \"${latest_product_virtual_file_entry_version}, ${product_virtual_file_entry_target_version}\"};type=application/json" \
				--header "Authorization: Bearer ${MARKETPLACE_OAUTH2_TOKEN}" \
				--output /dev/null \
				--request PATCH \
				--silent \
				--write-out "%{http_code}")

		if [[ "${http_response}" -ge 400 ]]
		then
			lc_log ERROR "Unable to update the list of supported versions for product '${product_module_name}'. HTTP status: ${http_response}."

			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi

		lc_log INFO "The supported versions list was successfully updated for product '${product_module_name}' to include the ${product_virtual_file_entry_target_version} release."
	else
		lc_log INFO "The supported versions list for product '${product_module_name}' already contains the ${product_virtual_file_entry_target_version} release."
	fi
}