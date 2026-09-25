#!/bin/bash

source ../_liferay_common.sh
source ../_test_common.sh
source ./_hotfix.sh

function main {
	set_up

	test_hotfix_compare_jars

	tear_down
}

function set_up {
	export _BUILD_DIR=$(mktemp --directory)
	export _BUNDLES_DIR="${_BUILD_DIR}/bundles"
	export _RELEASE_DIR="${_BUILD_DIR}/release"

	mkdir --parents "${_BUNDLES_DIR}/osgi/modules" "${_RELEASE_DIR}/osgi/modules"

	_create_module_jar "${_BUNDLES_DIR}/osgi/modules/com.liferay.test.changed.impl.jar" "new content" "2020-01-01 00:00:00" "17.0.14"
	_create_module_jar "${_BUNDLES_DIR}/osgi/modules/com.liferay.test.rebuilt.impl.jar" "original content" "2021-01-01 00:00:00" "17.0.14"
	_create_module_jar "${_RELEASE_DIR}/osgi/modules/com.liferay.test.changed.impl.jar" "original content" "2020-01-01 00:00:00" "17.0.14"
	_create_module_jar "${_RELEASE_DIR}/osgi/modules/com.liferay.test.rebuilt.impl.jar" "original content" "2020-01-01 00:00:00" "17.0.18"

	_create_portal_bootstrap_jar "${_BUNDLES_DIR}/osgi/modules/com.liferay.test.portal.bootstrap.changed.jar" "1772646511768" "2.20.0"
	_create_portal_bootstrap_jar "${_BUNDLES_DIR}/osgi/modules/com.liferay.test.portal.bootstrap.rebuilt.jar" "1772646599999" "2.17.1"
	_create_portal_bootstrap_jar "${_RELEASE_DIR}/osgi/modules/com.liferay.test.portal.bootstrap.changed.jar" "1772646511768" "2.17.1"
	_create_portal_bootstrap_jar "${_RELEASE_DIR}/osgi/modules/com.liferay.test.portal.bootstrap.rebuilt.jar" "1772646511768" "2.17.1"
}

function tear_down {
	rm --force --recursive "${_BUILD_DIR}"

	unset _BUILD_DIR
	unset _BUNDLES_DIR
	unset _RELEASE_DIR
}

function test_hotfix_compare_jars {
	_test_hotfix_compare_jars "osgi/modules/com.liferay.test.changed.impl.jar" "0"
	_test_hotfix_compare_jars "osgi/modules/com.liferay.test.portal.bootstrap.changed.jar" "0"
	_test_hotfix_compare_jars "osgi/modules/com.liferay.test.portal.bootstrap.rebuilt.jar" "1"
	_test_hotfix_compare_jars "osgi/modules/com.liferay.test.rebuilt.impl.jar" "1"
}

function _create_module_jar {
	local packaged_jar_dir=$(mktemp --directory)

	echo "${2}" > "${packaged_jar_dir}/internal.txt"

	touch --date "${3}" "${packaged_jar_dir}/internal.txt"

	echo "Liferay-Created-By: ${4}" > "${packaged_jar_dir}/manifest"

	local module_jar_dir=$(mktemp --directory)

	mkdir --parents "${module_jar_dir}/lib"

	jar cfm "${module_jar_dir}/lib/internal.jar" "${packaged_jar_dir}/manifest" -C "${packaged_jar_dir}" internal.txt

	echo "external content" > "${module_jar_dir}/external.txt"

	touch --date "2020-01-01 00:00:00" "${module_jar_dir}/external.txt" "${module_jar_dir}/lib/internal.jar"

	jar cf "${1}" -C "${module_jar_dir}" external.txt -C "${module_jar_dir}" lib/internal.jar

	rm --force --recursive "${module_jar_dir}" "${packaged_jar_dir}"
}

function _create_portal_bootstrap_jar {
	local jar_dir=$(mktemp --directory)

	mkdir --parents "${jar_dir}/META-INF"

	(
		echo "Bnd-LastModified: ${2}"
		echo "Export-Package: org.apache.logging.log4j;version=\"${3}\",org.apa"
		echo " che.logging.log4j.spi;version=\"${3}\""
	) > "${jar_dir}/META-INF/system.packages.extra.mf"

	jar cf "${1}" -C "${jar_dir}" META-INF/system.packages.extra.mf

	rm --force --recursive "${jar_dir}"
}

function _test_hotfix_compare_jars {
	compare_jars "${1}" &> /dev/null

	assert_equals "${?}" "${2}"
}

main "${@}"