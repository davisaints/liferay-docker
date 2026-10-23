#!/bin/bash

source ../_liferay_common.sh
source ../_test_common.sh
source ./_patcher.sh

function main {
	set_up

	test_patcher_get_patcher_environment
	test_patcher_report_jenkins_url
	test_patcher_report_patcher_status

	tear_down
}

function set_up {
	export LIFERAY_RELEASE_HOTFIX_BUILD_ID="123456789"
	export LIFERAY_RELEASE_PATCHER_REQUEST_KEY="test-request-key"
	export LIFERAY_RELEASE_PATCHER_USER_ID="987654321"
	export _BUILD_DIR=$(mktemp --directory)
}

function tear_down {
	rm --force --recursive "${_BUILD_DIR}"

	unset LIFERAY_RELEASE_HOTFIX_BUILD_ID
	unset LIFERAY_RELEASE_PATCHER_REQUEST_KEY
	unset LIFERAY_RELEASE_PATCHER_USER_ID
	unset _BUILD_DIR
}

function test_patcher_get_patcher_environment {
	_test_patcher_get_patcher_environment "" "production"
	_test_patcher_get_patcher_environment "uat" "uat"
}

function test_patcher_report_jenkins_url {
	_test_patcher_report_jenkins_url "" "production"
	_test_patcher_report_jenkins_url "uat" "uat"
}

function test_patcher_report_patcher_status {
	_test_patcher_report_patcher_status "" "production"
	_test_patcher_report_patcher_status "uat" "uat"
}

function _test_patcher_get_patcher_environment {
	LIFERAY_RELEASE_PATCHER_ENVIRONMENT="${1}"

	assert_equals "$(_get_patcher_environment)" "${2}"

	unset LIFERAY_RELEASE_PATCHER_ENVIRONMENT
}

function _test_patcher_report_jenkins_url {
	LIFERAY_RELEASE_PATCHER_ENVIRONMENT="${1}"

	(report_jenkins_url) &> /dev/null

	assert_equals \
		"$(grep --count "\"status\": \"pending\"" "${_BUILD_DIR}/patcher-status/${2}/osbPatcherStatus/build/jenkins/${LIFERAY_RELEASE_HOTFIX_BUILD_ID}")" \
		"1"

	rm --force --recursive "${_BUILD_DIR}/patcher-status"

	unset LIFERAY_RELEASE_PATCHER_ENVIRONMENT
}

function _test_patcher_report_patcher_status {
	LIFERAY_RELEASE_PATCHER_ENVIRONMENT="${1}"

	mkdir --parents "${_BUILD_DIR}/patcher-status/${2}/osbPatcherStatus/build/jenkins"

	(report_patcher_status) &> /dev/null

	assert_equals \
		"$(grep --count "\"exitValue\": 0" "${_BUILD_DIR}/patcher-status/${2}/osbPatcherStatus/build/jenkins/${LIFERAY_RELEASE_HOTFIX_BUILD_ID}")" \
		"1"

	rm --force --recursive "${_BUILD_DIR}/patcher-status"

	unset LIFERAY_RELEASE_PATCHER_ENVIRONMENT
}

main "${@}"