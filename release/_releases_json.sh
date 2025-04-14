#!/bin/bash

function generate_releases_json {
	if [ "${1}" = "regenerate" ]
	then
		_process_product dxp
		_process_product portal
	else
		_process_new_product

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi
	fi

	_promote_product_versions dxp
	_promote_product_versions portal
	_tag_recommended_product_versions

	_merge_json_snippets

	_upload_releases_json
}

function _generate_product_version_list {
	local release_directory_url="https://releases.liferay.com/${1}"

	lc_log INFO "Generating product version list from ${release_directory_url}."

	local directory_html=$(lc_curl "${release_directory_url}/")

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to download the product version list."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	echo "${directory_html}"
}

function _get_latest_product_version {
	local product_name=""
	local product_version="${1}"
	local product_version_regex="(?<=<a href=\")"

	if [ "${product_version}" == "dxp" ]
	then
		product_name="dxp"
		product_version_regex="${product_version_regex}(7\.3\.10-u\d+)"
	elif [ "${product_version}" == "ga" ]
	then
		product_name="portal"
		product_version_regex="${product_version_regex}(7\.4\.3\.\d+-ga\d+)"
	elif [ "${product_version}" == "quartely" ]
	then
		product_name="dxp"
		product_version_regex="${product_version_regex}(\d{4}\.q[1-4]\.\d+(-lts)?)"
	fi

	echo "$(_generate_product_version_list "${product_name}")" | \
		grep \
			--only-matching \
			--perl-regexp \
			"${product_version_regex}" | \
		tail -n 1
}

function _merge_json_snippets {
	if (! jq -s add $(ls ./*.json | sort -r) > releases.json)
	then
		lc_log ERROR "Detected invalid JSON."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _process_new_product {
	if [[ $(echo "${_PRODUCT_VERSION}" | grep "7.4") ]] &&
	   [[ $(echo "${_PRODUCT_VERSION}" | cut -d 'u' -f 2) -gt 112 ]]
	then
		lc_log INFO "${_PRODUCT_VERSION} should not be added to releases.json."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local releases_json="${_PROMOTION_DIR}/0000-00-00-releases.json"

	if [ ! -f "${releases_json}" ]
	then
		lc_log INFO "Downloading https://releases.liferay.com/releases.json to ${releases_json}."

		LIFERAY_COMMON_DOWNLOAD_SKIP_CACHE="true" lc_download https://releases.liferay.com/releases.json "${releases_json}"
	fi

	if (grep "${_PRODUCT_VERSION}" "${releases_json}")
	then
		lc_log INFO "The version ${_PRODUCT_VERSION} is already in releases.json."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local product_group_version="$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)"

	jq "map(
			if .product == \"${LIFERAY_RELEASE_PRODUCT_NAME}\" and .productGroupVersion == \"${product_group_version}\"
			then
				.promoted = \"false\"
			else
				.
			end
		)" "${releases_json}" > temp_file.json && mv temp_file.json "${releases_json}"

	if [ "${product_group_version}" == 7.3 ] || [ "${product_group_version}" == 7.4 ]
	then
		jq "map(
				if .product == \"${LIFERAY_RELEASE_PRODUCT_NAME}\" and .productGroupVersion == \"${product_group_version}\"
				then
					del(.tags)
				else
					.
				end
			)" "${releases_json}" > temp_file.json && mv temp_file.json "${releases_json}"
	elif [[ "${product_group_version}" == *q* ]] && [ "$(_get_latest_product_version "quartely")" == "${_PRODUCT_VERSION}" ]
	then
		jq 'map(
				if .productGroupVersion | test("q")
				then
					del(.tags)
				else
					.
				end
			)' "${releases_json}" > temp_file.json && mv temp_file.json "${releases_json}"
	fi

	_process_product_version "${LIFERAY_RELEASE_PRODUCT_NAME}" "${_PRODUCT_VERSION}"
}

function _process_product {
	local product_name="${1}"

	local release_directory_url="https://releases.liferay.com/${product_name}"

	for product_version in  $(echo -en "$(_generate_product_version_list "${product_name}")" | \
		grep \
			--extended-regexp \
			--only-matching \
			"(20[0-9]+\.q[0-9]\.[0-9]+(-lts)?|7\.[0-9]+\.[0-9]+[a-z0-9\.-]+)/" | \
		tr -d "/" | \
		uniq)
	do
		if [[ $(echo "${product_version}" | grep "7.4") ]] && [[ $(echo "${product_version}" | cut -d 'u' -f 2) -gt 112 ]]
		then
			continue
		fi

		_process_product_version "${product_name}" "${product_version}"
	done
}

function _process_product_version {
	local product_name=${1}
	local product_version=${2}

	lc_log INFO "Processing ${product_name} ${product_version}."

	local release_properties_file

	#
	# Define release_properties_file in a separate line to capture the exit code.
	#

	release_properties_file=$(lc_download "https://releases.liferay.com/${product_name}/${product_version}/release.properties")

	local exit_code=${?}

	if [ "${exit_code}" == "${LIFERAY_COMMON_EXIT_CODE_MISSING_RESOURCE}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	elif [ "${exit_code}" == "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local release_date=$(lc_get_property "${release_properties_file}" release.date)

	if [ -z "${release_date}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	tee "${release_date}-${product_name}-${product_version}.json" <<- END
	[
	    {
	        "product": "${product_name}",
	        "productGroupVersion": "$(echo "${product_version}" | sed -r "s@(^[0-9]+\.[0-9a-z]+)\..*@\1@")",
	        "productVersion": "$(lc_get_property "${release_properties_file}" liferay.product.version)",
	        "promoted": "false",
	        "releaseKey": "$(echo "${product_name}-${product_version}" | sed "s/\([0-9]\+\)\.\([0-9]\+\)\.[0-9]\+\(-\|[^0-9]\)/\1.\2\3/g" | sed -e "s/portal-7\.4\.[0-9]*-ga/portal-7.4-ga/")",
	        "targetPlatformVersion": "$(lc_get_property "${release_properties_file}" target.platform.version)",
	        "url": "https://releases-cdn.liferay.com/${product_name}/${product_version}"
	    }
	]
	END
}

function _promote_product_versions {
	local product_name=${1}

	while read -r group_version || [ -n "${group_version}" ]
	do
		# shellcheck disable=SC2010
		last_version=$(ls "${_PROMOTION_DIR}" | grep "${product_name}-${group_version}" | tail -n 1 2>/dev/null)

		if [ -n "${last_version}" ]
		then
			lc_log INFO "Promoting ${last_version}."

			sed -i 's/"promoted": "false"/"promoted": "true"/' "${last_version}"
		else
			lc_log INFO "No product version found to promote for ${product_name}-${group_version}."
		fi
	done < "${_RELEASE_ROOT_DIR}/supported-${product_name}-versions.txt"
}

function _tag_recommended_product_versions {
	for product_version in "dxp" "ga" "quartely"
	do
		local latest_product_version_json=$(ls "${_PROMOTION_DIR}" | grep "$(_get_latest_product_version "${product_version}")")

		if [ -f "${latest_product_version_json}" ]
		then
			jq "map(
					(. + {tags: [\"recommended\"]})
					| to_entries
					| sort_by(.key)
					| from_entries
				)" "${latest_product_version_json}" > "${latest_product_version_json}.tmp" && mv "${latest_product_version_json}.tmp" "${latest_product_version_json}"

			lc_log INFO "Tagging ${latest_product_version_json} as recommended."
		else
			lc_log INFO "Unable to find JSON file for ${product_version}."
		fi
	done
}

function _upload_releases_json {
	ssh root@lrdcom-vm-1 "exit" &> /dev/null

	if [ "${?}" -eq 0 ]
	then
		lc_log INFO "Backing up to /www/releases.liferay.com/releases.json.BACKUP."

		ssh root@lrdcom-vm-1 cp -f "/www/releases.liferay.com/releases.json" "/www/releases.liferay.com/releases.json.BACKUP"

		lc_log INFO "Uploading ${_PROMOTION_DIR}/releases.json to /www/releases.liferay.com/releases.json."

		scp "${_PROMOTION_DIR}/releases.json" "root@lrdcom-vm-1:/www/releases.liferay.com/releases.json.upload"

		ssh root@lrdcom-vm-1 mv -f "/www/releases.liferay.com/releases.json.upload" "/www/releases.liferay.com/releases.json"
	fi

	lc_log INFO "Backing up to gs://liferay-releases/releases.json.BACKUP."

	gsutil cp "gs://liferay-releases/releases.json" "gs://liferay-releases/releases.json.BACKUP"

	lc_log INFO "Uploading ${_PROMOTION_DIR}/releases.json to gs://liferay-releases/releases.json."

	gsutil cp "${_PROMOTION_DIR}/releases.json" "gs://liferay-releases/releases.json.upload"

	gsutil mv "gs://liferay-releases/releases.json.upload" "gs://liferay-releases/releases.json"
}