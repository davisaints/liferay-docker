#!/bin/bash

source ../_gh_pr.sh
source ../_liferay_common.sh
source ../release/_git.sh

function check_translations_sync {
	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	if ! git remote get-url brianchandotcom &> /dev/null
	then
		git remote add brianchandotcom "git@github.com:brianchandotcom/liferay-portal.git"
	fi

	git fetch --force brianchandotcom "master:refs/remotes/brianchandotcom/master"

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to fetch master from brianchandotcom/liferay-portal."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	if [ -n "$( \
		git log \
			-1 \
			--format="%H" \
			--grep="LPD-91206 Update Translations" \
			master..brianchandotcom/master)" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	_TRANSLATIONS_SYNCED=true
}

function check_usage {
	if [ -z "${CROWDIN_API_TOKEN}" ] ||
	   [ -z "${CROWDIN_PROJECT_ID}" ]
	then
		print_help
	fi

	_CROWDIN_DIR=${PWD}

	LIFERAY_COMMON_LOG_DIR="${_CROWDIN_DIR}/logs"

	_LANG_BUILDER_LIB_DIR="tools/sdk/dependencies/com.liferay.lang.builder/lib"

	_PROJECTS_DIR="/opt/dev/projects/github"

	if [ ! -d "${_PROJECTS_DIR}" ]
	then
		_PROJECTS_DIR=${_CROWDIN_DIR}
	fi

	_TRANSLATION_FILE_REGEX="(Language|bundle)(_[a-zA-Z].*)?\.properties$"
}

function download_translations {
	lc_log INFO "Downloading translations from Crowdin."

	crowdin download translations \
		--branch "master" \
		--export-only-approved \
		--no-progress \
		--plain \
		--verbose

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to download translations from Crowdin."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function main {
	if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
	then
		return
	fi

	check_usage

	lc_time_run close_pull_request \
		"head:crowdin-translations" \
		"liferay-release/liferay-portal"

	if [ "${_PROJECTS_DIR}" == "${_CROWDIN_DIR}" ]
	then
		lc_background_run clone_repository liferay-portal

		lc_wait
	fi

	lc_time_run update_portal_repository

	lc_time_run check_translations_sync

	if [ "${_TRANSLATIONS_SYNCED}" != "true" ]
	then
		lc_log INFO "Skipping the Crowdin synchronization because the latest translations commit was not synced to liferay/liferay-portal."

		exit "${LIFERAY_COMMON_EXIT_CODE_OK}"
	fi

	lc_time_run set_up_branch

	lc_time_run set_up_lang_builder

	lc_time_run normalize_translations

	lc_time_run upload_sources

	lc_time_run download_translations

	lc_time_run merge_and_commit_translations

	if [ "${_CREATE_PULL_REQUEST}" != "true" ]
	then
		lc_log INFO "Skipping pull request creation because there are no new translations."

		exit "${LIFERAY_COMMON_EXIT_CODE_OK}"
	fi

	lc_time_run push_branch_to_liferay_release_fork \
		"${_TEMP_BRANCH}" \
		"liferay-portal"

	lc_time_run create_pull_request \
		"master" \
		"${_TEMP_BRANCH}" \
		"liferay-release/liferay-portal" \
		"LPD-91206 Update Translations"
}

function merge_and_commit_translations {
	local changed_files=$( \
		git diff --name-only | grep --extended-regexp "${_TRANSLATION_FILE_REGEX}")

	if [ -z "${changed_files}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_log INFO "Merging approved translations into translation files."

	local translation_file

	while IFS= read -r translation_file
	do
		_merge_translation_file "${translation_file}"
	done <<< "${changed_files}"

	local merged_files=$( \
		git diff --name-only | grep --extended-regexp "${_TRANSLATION_FILE_REGEX}")

	if [ -z "${merged_files}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_log INFO "Normalizing merged translations with the Lang Builder."

	_run_lang_builder_on_files "${merged_files}"

	if [ "${?}" -ne 0 ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	merged_files=$( \
		git diff --name-only | grep --extended-regexp "${_TRANSLATION_FILE_REGEX}")

	if [ -z "${merged_files}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if [ "${_LANG_BUILDER_COMMITTED}" == "true" ]
	then
		local merged_file

		while IFS= read -r merged_file
		do
			git add "${merged_file}"
		done <<< "${merged_files}"

		git commit --amend --message "LPD-91206 Update Translations"
	else
		commit_changes "${merged_files}" "LPD-91206 Update Translations"
	fi

	_CREATE_PULL_REQUEST=true
}

function normalize_translations {
	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	lc_log INFO "Normalizing translation files with the Lang Builder."

	_run_lang_builder "modules/apps/portal-language/portal-language-lang/src/main/resources/content" "Language"

	if [ "${?}" -ne 0 ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local changed_files=$( \
		git diff --name-only | grep --extended-regexp "${_TRANSLATION_FILE_REGEX}")

	if [ -z "${changed_files}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	commit_changes "${changed_files}" "LPD-91206 Normalize existing translations"

	_LANG_BUILDER_COMMITTED=true
}

function print_help {
	echo "Usage: ${0}"
	echo ""
	echo "The script reads the following environment variables:"
	echo ""
	echo "    CROWDIN_API_TOKEN: Crowdin API token."
	echo "    CROWDIN_PROJECT_ID: Crowdin project ID."
	echo ""

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

function set_up_branch {
	_TEMP_BRANCH="crowdin-translations-$(date "+%Y%m%d%H%M%S")"

	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	git checkout -b "${_TEMP_BRANCH}"

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to create branch ${_TEMP_BRANCH}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	cp "${_CROWDIN_DIR}/crowdin.yml" "${_PROJECTS_DIR}/liferay-portal"
}

function set_up_lang_builder {
	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	if [ -d "${_LANG_BUILDER_LIB_DIR}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_log INFO "Setting up portal tools to install the Lang Builder."

	./gradlew --build-file="modules/util.gradle" setUpPortalTools

	if [ ! -d "${_LANG_BUILDER_LIB_DIR}" ]
	then
		lc_log ERROR "Unable to set up the Lang Builder."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function update_portal_repository {
	trap "return ${LIFERAY_COMMON_EXIT_CODE_BAD}" ERR

	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	git checkout master --force

	git reset --hard && git clean -dfx

	if ! git remote get-url upstream &> /dev/null
	then
		git remote add upstream "git@github.com:liferay/liferay-portal.git"
	fi

	git fetch upstream "master:refs/remotes/upstream/master"

	git reset --hard upstream/master

	if ! git remote get-url liferay-release &> /dev/null
	then
		git remote add liferay-release "git@github.com:liferay-release/liferay-portal.git"
	fi

	git push liferay-release master

	git log -1
}

function upload_sources {
	lc_log INFO "Uploading source files to Crowdin."

	crowdin upload sources \
		--branch "master" \
		--no-progress \
		--plain \
		--verbose

	if [[ "${?}" -ne 0 ]]
	then
		lc_log ERROR "Unable to upload source files to Crowdin."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _apply_crowdin_translations {
	local crowdin_translation_file=${1}
	local head_translation_file=${2}

	awk \
		-v crowdin_translation_file="${crowdin_translation_file}" \
		-v head_translation_file="${head_translation_file}" '
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

		FILENAME == crowdin_translation_file {
			if (is_translation($0)) {
				key = parse_key($0)

				crowdin_translations[key] = $0
			}
		}

		FILENAME == head_translation_file {
			if (!is_translation($0)) {
				print

				next
			}

			key = parse_key($0)

			if (key in crowdin_translations) {
				print crowdin_translations[key]
			} else {
				print
			}
		}
	' "${crowdin_translation_file}" "${head_translation_file}"
}

function _has_new_translations {
	local head_translation_file=${1}
	local merged_translation_file=${2}

	! diff --brief \
		<(grep "=" "${head_translation_file}") \
		<(grep "=" "${merged_translation_file}") &> /dev/null
}

function _merge_translation_file {
	local crowdin_translation_file=${1}

	local head_translation_file=$(mktemp)

	git show "HEAD:${crowdin_translation_file}" > "${head_translation_file}"

	local merged_translation_file=$(mktemp)

	_apply_crowdin_translations "${crowdin_translation_file}" "${head_translation_file}" > "${merged_translation_file}"

	if [ -z "$(tail --bytes=1 "${merged_translation_file}")" ]
	then
		truncate --size=-1 "${merged_translation_file}"
	fi

	if _has_new_translations "${head_translation_file}" "${merged_translation_file}"
	then
		mv "${merged_translation_file}" "${crowdin_translation_file}"
	else
		cp "${head_translation_file}" "${crowdin_translation_file}"
	fi

	rm --force "${head_translation_file}" "${merged_translation_file}"
}

function _run_lang_builder {
	local lang_dir=${1}
	local lang_file=${2}

	lc_cd "${_PROJECTS_DIR}/liferay-portal"

	java \
		-Dfile.encoding=UTF-8 \
		-Duser.country=US \
		-Duser.language=en \
		-classpath "${_LANG_BUILDER_LIB_DIR}/*" \
		com.liferay.lang.builder.LangBuilder \
		"lang.dir=${lang_dir}" \
		"lang.file=${lang_file}" \
		"lang.translate=false"

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to run the Lang Builder in ${lang_dir}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _run_lang_builder_on_files {
	local changed_files=${1}

	local lang_dir

	while IFS= read -r lang_dir
	do
		local lang_file="bundle"

		if [ "${lang_dir##*/}" != "app.bnd-localization" ]
		then
			lang_file="Language"
		fi

		_run_lang_builder "${lang_dir}" "${lang_file}"

		if [ "${?}" -ne 0 ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done <<< "$(echo "${changed_files}" | xargs dirname | sort --unique)"
}

main "${@}"
