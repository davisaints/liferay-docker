#!/bin/bash

function is_early_product_version_than {
	local product_version_1=$(echo "${ACTUAL_PRODUCT_VERSION}" | sed -e "s/-lts//")
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

function is_quarterly_release {
	if [[ "${ACTUAL_PRODUCT_VERSION}" == *q* ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

function set_actual_product_version {
	if [ -n "${_PRODUCT_VERSION}" ]
	then
		ACTUAL_PRODUCT_VERSION="${_PRODUCT_VERSION}"
	else
		ACTUAL_PRODUCT_VERSION="${1}"
	fi
}

set_actual_product_version "${@}"