#!/bin/bash

source ../_test_common.sh
source ./_marketplace_products.sh

function main {
	if [ "${#}" -eq 1 ]
	then
		"${1}"
	else
		test_marketplace_products_get_latest_product_virtual_settings_file_entry_json_index
	fi
}

function test_marketplace_products_get_latest_product_virtual_settings_file_entry_json_index {
	_test_marketplace_products_get_latest_product_virtual_settings_file_entry_json_index "2025.Q1" "2"
	_test_marketplace_products_get_latest_product_virtual_settings_file_entry_json_index "7.4" "2"
}

function _test_marketplace_products_get_latest_product_virtual_settings_file_entry_json_index {
	local product_virtual_settings_file_entries=$(cat "${PWD}/test-dependencies/expected/test_marketplace_products_${1}.json")

	assert_equals \
		"$(_get_latest_product_virtual_settings_file_entry_json_index "${product_virtual_settings_file_entries}")" \
		"${2}"
}

main "${@}"