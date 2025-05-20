#!/bin/bash

source ./_release_common.sh
source ./_test_common.sh

function main {
	test_release_common_get_product_group_version
	test_release_common_get_release_year
	test_release_common_is_7_3_ga_release
	test_release_common_is_7_3_release
	test_release_common_is_7_3_u_release
	test_release_common_is_7_4_ga_release
	test_release_common_is_7_4_release
	test_release_common_is_7_4_u_release
	test_release_common_is_early_product_version_than
	test_release_common_is_ga_release
	test_release_common_is_quarterly_release
	test_release_common_is_u_release

	unset _PRODUCT_VERSION
	unset ACTUAL_PRODUCT_VERSION
}

function test_release_common_get_product_group_version {
	_test_release_common_get_product_group_version "2025.q1.0-lts" "2025.q1"
	_test_release_common_get_product_group_version "7.4.13.nightly" "7.4"
}

function test_release_common_get_release_year {
	_PRODUCT_VERSION="2025.q1.0-lts"

	assert_equals "$(get_release_year)" "2025"
}

function test_release_common_is_7_3_ga_release {
	_test_release_common_is_7_3_ga_release "7.3.10-ga1" "true"
	_test_release_common_is_7_3_ga_release "7.3.7-ga8" "true"
	_test_release_common_is_7_3_ga_release "7.4.13-u132" "false"
	_test_release_common_is_7_3_ga_release "7.4.3.132-ga132" "false"
}

function test_release_common_is_7_3_release {
	_test_release_common_is_7_3_release "7.3.10-u36" "true"
	_test_release_common_is_7_3_release "7.3.7-ga8" "true"
	_test_release_common_is_7_3_release "7.4.13-u132" "false"
	_test_release_common_is_7_3_release "7.4.3.132-ga132" "false"
}

function test_release_common_is_7_3_u_release {
	_test_release_common_is_7_3_u_release "7.3.10-u36" "true"
	_test_release_common_is_7_3_u_release "7.3.7-ga8" "false"
	_test_release_common_is_7_3_u_release "7.4.13-u132" "false"
	_test_release_common_is_7_3_u_release "7.4.3.132-ga132" "false"
}

function test_release_common_is_7_4_ga_release {
	_test_release_common_is_7_4_ga_release "7.3.10-u36" "false"
	_test_release_common_is_7_4_ga_release "7.3.7-ga8" "false"
	_test_release_common_is_7_4_ga_release "7.4.13-u132" "false"
	_test_release_common_is_7_4_ga_release "7.4.3.132-ga132" "true"
}

function test_release_common_is_7_4_release {
	_test_release_common_is_7_4_release "7.3.10-u36" "false"
	_test_release_common_is_7_4_release "7.3.7-ga8" "false"
	_test_release_common_is_7_4_release "7.4.13-u132" "true"
	_test_release_common_is_7_4_release "7.4.3.132-ga132" "true"
}

function test_release_common_is_7_4_u_release {
	_test_release_common_is_7_4_u_release "7.3.10-u3" "false"
	_test_release_common_is_7_4_u_release "7.3.10-u36" "false"
	_test_release_common_is_7_4_u_release "7.4.0-ga1" "false"
	_test_release_common_is_7_4_u_release "7.4.13-u134" "true"
}

function test_release_common_is_early_product_version_than {
	_test_release_common_is_early_product_version_than "2023.q3.1" "2025.q2.0" "true"
	_test_release_common_is_early_product_version_than "2024.q4.7" "2025.q1.0" "true"
	_test_release_common_is_early_product_version_than "2025.q1.0" "2025.q1.1" "true"
	_test_release_common_is_early_product_version_than "2025.q1.1-lts" "2025.q1.0-lts" "false"
}

function test_release_common_is_ga_release {
	_test_release_common_is_ga_release "2025.q1.0-lts" "false"
	_test_release_common_is_ga_release "7.3.10-ga2" "true"
	_test_release_common_is_ga_release "7.4.0-ga1" "true"
	_test_release_common_is_ga_release "7.4.13-u134" "false"
	_test_release_common_is_ga_release "7.4.3.132-ga132" "true"
}

function test_release_common_is_quarterly_release {
	_test_release_common_is_quarterly_release "2025.q1.0-lts" "true"
	_test_release_common_is_quarterly_release "7.4.13-u134" "false"
	_test_release_common_is_quarterly_release "7.4.3.112-ga112" "false"
}

function test_release_common_is_u_release {
	_test_release_common_is_u_release "7.3.10-u2" "true"
	_test_release_common_is_u_release "7.4.13-u1" "true"
	_test_release_common_is_u_release "7.4.0-ga1" "false"
	_test_release_common_is_u_release "2025.q2.0-lts" "false"
}

function _test_release_common_get_product_group_version {
	_PRODUCT_VERSION="${1}"

	echo -e "Running _test_release_common_get_product_group_version for ${_PRODUCT_VERSION}.\n"

	assert_equals "$(get_product_group_version)" "${2}"
}

function _test_release_common_is_7_3_ga_release {
	echo -e "Running _test_release_common_is_7_3_ga_release for ${1}.\n"

	assert_equals "$(is_7_3_ga_release "${1}")" "${2}"
}

function _test_release_common_is_7_3_release {
	echo -e "Running _test_release_common_is_7_3_release for ${1}.\n"

	assert_equals "$(is_7_3_release "${1}")" "${2}"
}

function _test_release_common_is_7_3_u_release {
	echo -e "Running _test_release_common_is_7_3_u_release for ${1}.\n"

	assert_equals "$(is_7_3_u_release "${1}")" "${2}"
}

function _test_release_common_is_7_4_ga_release {
	echo -e "Running _test_release_common_is_7_4_ga_release for ${1}.\n"

	assert_equals "$(is_7_4_ga_release "${1}")" "${2}"
}

function _test_release_common_is_7_4_release {
	echo -e "Running _test_release_common_is_7_4_release for ${1}.\n"

	assert_equals "$(is_7_4_release "${1}")" "${2}"
}

function _test_release_common_is_7_4_u_release {
	echo -e "Running _test_release_common_is_7_4_u_release for ${1}.\n"

	assert_equals "$(is_7_4_u_release "${1}")" "${2}"
}

function _test_release_common_is_early_product_version_than {
	set_actual_product_version "${1}" 

	echo -e "Running _test_release_common_is_early_product_version_than for ${1}.\n"

	assert_equals "$(is_early_product_version_than "${2}")" "${3}"
}

function _test_release_common_is_ga_release {
	echo -e "Running _test_release_common_is_ga_release for ${1}.\n"

	assert_equals "$(is_ga_release "${1}")" "${2}"
}

function _test_release_common_is_quarterly_release {
	echo -e "Running _test_release_common_is_quarterly_release for ${1}.\n"

	assert_equals "$(is_quarterly_release "${1}")" "${2}"
}

function _test_release_common_is_u_release {
	echo -e "Running _test_release_common_is_u_release for ${1}.\n"

	assert_equals "$(is_u_release "${1}")" "${2}"
}

main