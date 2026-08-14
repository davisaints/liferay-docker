#!/bin/bash

source ../_liferay_common.sh
source ../_test_common.sh
source ./check_marketplace_compatibility.sh

function main {
	trap tear_down EXIT

	set_up

	if [[ "${#}" -eq 1 ]]
	then
		"${1}"
	else
		test_marketplace_check_punchout2go_activation_key
		test_marketplace_deploy_liferay_marketplace_product_zip_file
		test_marketplace_deploy_punchout2go_activation_key
		test_marketplace_get_latest_product_virtual_settings_file_entry_json_index
	fi
}

function set_up {
	common_set_up

	export _RELEASE_ROOT_DIR=${PWD}

	export _BUILD_DIR=$(mktemp --directory)
	export _PRODUCT_VERSION="2025.q3.0"

	mkdir --parents "${_BUILD_DIR}/deploy"
	mkdir --parents "${_BUILD_DIR}/marketplace"

	cp "${_RELEASE_ROOT_DIR}/test-dependencies/actual/liferaycommerceminium4globalcss.zip" "${_BUILD_DIR}/marketplace"
}

function tear_down {
	common_tear_down

	rm --force --recursive "${_BUILD_DIR}"

	unset _BUILD_DIR
	unset _PRODUCT_VERSION
	unset _RELEASE_ROOT_DIR
}

# Note: the container lifecycle (pulling LIFERAY_DOCKER_IMAGE_NAME, running it,
# and checking OSGi state through blade sh --host --port) is exercised by the
# check-marketplace-compatibility Jenkins job itself, not by this unit test
# suite, since it requires Docker and a published image.

function test_marketplace_check_punchout2go_activation_key {
	_test_marketplace_check_punchout2go_activation_key \
		"Liferay Commerce Connector to PunchOut2Go license validation passed" "0"
	_test_marketplace_check_punchout2go_activation_key \
		"Unable to resolve com.liferay.commerce.punchout.api: This application does not have a valid license" "1"
}

function test_marketplace_deploy_liferay_marketplace_product_zip_file {
	_deploy_liferay_marketplace_product_zip_file "${_BUILD_DIR}/marketplace/liferaycommerceminium4globalcss.zip" &> /dev/null

	assert_equals \
		"${?}" "0" \
		"$(ls -1 "${_BUILD_DIR}/deploy/liferaycommerceminium4globalcss.zip" | wc --lines)" "1"

	rm --force "${_BUILD_DIR}/deploy/liferaycommerceminium4globalcss.zip"
}

function test_marketplace_deploy_punchout2go_activation_key {
	local activation_key_year=$(date +%Y)

	if [[ "$(date +%-m)" -lt 4 ]]
	then
		activation_key_year=$((activation_key_year - 1))
	fi

	local activation_key_directory=$(mktemp --directory)
	local activation_key_file="${activation_key_directory}/activation-key-punchout2go-${activation_key_year}-04-01.xml"

	echo "<license/>" > "${activation_key_file}"

	export "LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_${activation_key_year}=${activation_key_file}"

	_deploy_punchout2go_activation_key &> /dev/null

	assert_equals \
		"${?}" "0" \
		"$(ls -1 "${_BUILD_DIR}/deploy/activation-key-punchout2go-${activation_key_year}-04-01.xml" | wc --lines)" "1"

	rm --force "${_BUILD_DIR}/deploy/activation-key-punchout2go-${activation_key_year}-04-01.xml"
	rm --force --recursive "${activation_key_directory}"

	unset "LIFERAY_PUNCHOUT2GO_ACTIVATION_KEY_${activation_key_year}"
}

function test_marketplace_get_latest_product_virtual_settings_file_entry_json_index {
	_test_marketplace_get_latest_product_virtual_settings_file_entry_json_index "2026.Q2" "2"
	_test_marketplace_get_latest_product_virtual_settings_file_entry_json_index "7.4" "2"
	_test_marketplace_get_latest_product_virtual_settings_file_entry_json_index "empty_version" ""
}

function _test_marketplace_check_punchout2go_activation_key {
	local deployment_log_file=$(mktemp)

	export _LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE=${deployment_log_file}

	echo "${1}" > "${deployment_log_file}"

	_check_punchout2go_activation_key &> /dev/null

	assert_equals "${?}" "${2}"

	rm --force "${deployment_log_file}"

	unset _LIFERAY_MARKETPLACE_PRODUCTS_DEPLOYMENT_LOG_FILE
}

function _test_marketplace_get_latest_product_virtual_settings_file_entry_json_index {
	local product_virtual_settings_file_entries=$(cat "${_RELEASE_ROOT_DIR}/test-dependencies/actual/test_marketplace_${1}.json")

	assert_equals \
		"$(_get_latest_product_virtual_settings_file_entry_json_index "${product_virtual_settings_file_entries}")" \
		"${2}"
}

main "${@}"
