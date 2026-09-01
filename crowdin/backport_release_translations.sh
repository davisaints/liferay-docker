#!/bin/bash

source ../_liferay_common.sh
source ../release/_git.sh
source ../release/_releases_json.sh

function backport_release_branch_translations {
	local release_branch=${1}

	lc_cd "${_PROJECTS_DIR}/liferay-portal-ee"

	git checkout "${release_branch}"

	git reset --hard "origin/${release_branch}"

	git fetch upstream "master:refs/remotes/upstream/master"

	local language_properties_file="modules/apps/portal-language/portal-language-lang/src/main/resources/content/Language.properties"

	local master_english_file=$(mktemp)

	git show "upstream/master:${language_properties_file}" > "${master_english_file}"

	local locale_file

	while IFS= read -r locale_file
	do
		_update_locale_translation_file "${language_properties_file}" "${locale_file}" "${master_english_file}"
	done <<< "$(git ls-files ":(glob)$(dirname "${language_properties_file}")/Language_*.properties")"

	rm --force "${master_english_file}"

	local changed_files=$(git diff --name-only | grep --extended-regexp "(Language|bundle)(_[a-zA-Z].*)?\.properties$")

	if [ -z "${changed_files}" ]
	then
		lc_log INFO "No translations to backport into ${release_branch}."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	commit_changes "${changed_files}" "LPD-98784 Backport translations from master"

	if [ "${LIFERAY_RELEASE_TEST_MODE}" == "true" ]
	then
		return
	fi

	git push liferay-release "${release_branch}"
}

function check_usage {
	LIFERAY_COMMON_LOG_DIR="${PWD}/logs"

	_PROJECTS_DIR="/opt/dev/projects/github"

	if [ ! -d "${_PROJECTS_DIR}" ]
	then
		_PROJECTS_DIR=${PWD}
	fi
}

function fetch_release_branches {
	local refspecs=()

	local release_branch

	while IFS= read -r release_branch
	do
		local product_version=$(echo "${release_branch}" | sed --expression "s/^release-//")

		if _is_supported_product_version "${product_version}"
		then
			refspecs+=("${release_branch}:refs/remotes/origin/${release_branch}")
		fi
	done <<< "$( \
		git ls-remote --heads origin "release-*" | \
			sed --expression "s#.*refs/heads/##" | \
			grep --extended-regexp "^release-[0-9]{4}\.q[1-4]$")"

	if [ "${#refspecs[@]}" -eq 0 ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	git fetch origin "${refspecs[@]}"
}

function main {
	if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
	then
		return
	fi

	check_usage

	lc_background_run clone_repository liferay-portal-ee

	lc_wait

	lc_cd "${_PROJECTS_DIR}/liferay-portal-ee"

	lc_time_run fetch_release_branches

	local release_branch

	while IFS= read -r release_branch
	do
		lc_time_run backport_release_branch_translations "${release_branch}"
	done <<< "$(git for-each-ref --format="%(refname:strip=3)" "refs/remotes/origin/release-*" | grep --extended-regexp "^release-[0-9]{4}\.q[1-4]$")"
}

function _apply_new_translations {
	local head_translation_file=${1}
	local new_translation_file=${2}

	awk \
		-v head_translation_file="${head_translation_file}" \
		-v new_translation_file="${new_translation_file}" '
		function is_translation(line) {
			if (line ~ /^[#!]/ || line !~ /=/) {
				return 0
			}

			return 1
		}

		function parse_key(line) {
			sub(/=.*/, "", line)

			return line
		}

		FILENAME == new_translation_file {
			if (is_translation($0)) {
				key = parse_key($0)

				new_translations[key] = $0
			}
		}

		FILENAME == head_translation_file {
			if (!is_translation($0)) {
				print

				next
			}

			key = parse_key($0)

			if (key in new_translations) {
				print new_translations[key]
			} else {
				print
			}
		}
	' "${new_translation_file}" "${head_translation_file}"
}

function _filter_matching_english_keys {
	local branch_english_file=${1}
	local master_english_file=${2}
	local master_locale_file=${3}

	awk \
		-v branch_english_file="${branch_english_file}" \
		-v master_english_file="${master_english_file}" \
		-v master_locale_file="${master_locale_file}" '
		function is_translation(line) {
			if (line ~ /^[#!]/ || line !~ /=/) {
				return 0
			}

			return 1
		}

		function parse_key(line) {
			sub(/=.*/, "", line)

			return line
		}

		FILENAME == branch_english_file {
			if (is_translation($0)) {
				key = parse_key($0)

				branch_english[key] = $0
			}

			next
		}

		FILENAME == master_english_file {
			if (is_translation($0)) {
				key = parse_key($0)

				master_english[key] = $0
			}

			next
		}

		FILENAME == master_locale_file {
			if (!is_translation($0)) {
				next
			}

			key = parse_key($0)

			if ($0 ~ /\(Automatic Copy\)$/) {
				next
			}

			if ((key in master_english) && (key in branch_english) && master_english[key] == branch_english[key]) {
				print
			}
		}
	' "${branch_english_file}" "${master_english_file}" "${master_locale_file}"
}

function _has_new_translations {
	local head_translation_file=${1}
	local merged_translation_file=${2}

	! diff --brief \
		<(grep "=" "${head_translation_file}") \
		<(grep "=" "${merged_translation_file}") &> /dev/null
}

function _update_locale_translation_file {
	local branch_english_file=${1}
	local locale_file=${2}
	local master_english_file=${3}

	local master_locale_file=$(mktemp)

	if ! git show "upstream/master:${locale_file}" > "${master_locale_file}" 2> /dev/null
	then
		rm --force "${master_locale_file}"

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local filtered_locale_file=$(mktemp)

	_filter_matching_english_keys "${branch_english_file}" "${master_english_file}" "${master_locale_file}" > "${filtered_locale_file}"

	local head_locale_file=$(mktemp)

	git show "HEAD:${locale_file}" > "${head_locale_file}"

	local merged_locale_file=$(mktemp)

	_apply_new_translations "${head_locale_file}" "${filtered_locale_file}" > "${merged_locale_file}"

	if [ -n "$(tail --bytes=1 "${head_locale_file}")" ]
	then
		truncate --size=-1 "${merged_locale_file}"
	fi

	if _has_new_translations "${head_locale_file}" "${merged_locale_file}"
	then
		mv "${merged_locale_file}" "${locale_file}"
	else
		rm --force "${merged_locale_file}"
	fi

	rm --force "${filtered_locale_file}" "${head_locale_file}" "${master_locale_file}"
}

main "${@}"
