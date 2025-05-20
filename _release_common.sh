#!/bin/bash

function get_product_group_version {
	if [ -n "${_PRODUCT_VERSION}" ]
	then
		echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2
	else
		echo "${1}" | cut -d '.' -f 1,2
	fi
}

function get_product_version {
	if [ -n "${_PRODUCT_VERSION}" ] && [ -z "${1}" ]
	then
		echo "${_PRODUCT_VERSION}"
	else
		echo "${1}"
	fi
}

function get_release_year {
	if [ -n "${_PRODUCT_VERSION}" ]
	then
		echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1
	else
		echo "${1}" | cut -d '.' -f 1
	fi
}

function is_7_3_ga_release {
	if [[ "$(get_product_version "${1}")" == 7.3.*-ga* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_7_3_release {
	if [[ "$(get_product_version "${1}")" == 7.3* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_7_3_u_release {
	if [[ "$(get_product_version "${1}")" == 7.3.*-u* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_7_4_ga_release {
	if [[ "$(get_product_version "${1}")" == 7.4.*-ga* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_7_4_release {
	if [[ "$(get_product_version "${1}")" == 7.4* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_7_4_u_release {
	if [[ "$(get_product_version "${1}")" == 7.4.*-u* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_early_product_version_than {
	local product_version_1=$(echo "$(get_product_version "${1}")" | sed -e "s/-lts//")
	local product_version_1_quarter
	local product_version_1_suffix

	IFS='.' read -r product_version_1_year product_version_1_quarter product_version_1_suffix <<< "${product_version_1}"

	product_version_1_quarter=$(echo "${product_version_1_quarter}" | sed -e "s/q//")

	local product_version_2=$(echo "${1}" | sed -e "s/-lts//")
	local product_version_2_quarter
	local product_version_2_suffix

	IFS='.' read -r product_version_2_year product_version_2_quarter product_version_2_suffix <<< "${product_version_2}"

	product_version_2_quarter=$(echo "${product_version_2_quarter}" | sed -e "s/q//")

	if [ "${product_version_1_year}" -lt "${product_version_2_year}" ]
	then
		echo "true"

		return
	elif [ "${product_version_1_year}" -gt "${product_version_2_year}" ]
	then
		echo "false"

		return
	fi

	if [ "${product_version_1_quarter}" -lt "${product_version_2_quarter}" ]
	then
		echo "true"

		return
	elif [ "${product_version_1_quarter}" -gt "${product_version_2_quarter}" ]
	then
		echo "false"

		return
	fi

	if [ "${product_version_1_suffix}" -lt "${product_version_2_suffix}" ]
	then
		echo "true"

		return
	elif [ "${product_version_1_suffix}" -gt "${product_version_2_suffix}" ]
	then
		echo "false"

		return
	fi

	echo "false"
}

function is_ga_release {
	if [[ "$(get_product_version "${1}")" == *-ga* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_quarterly_release {
	if [[ "$(get_product_version "${1}")" == *q* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function is_u_release {
	if [[ "$(get_product_version "${1}")" == *-u* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}