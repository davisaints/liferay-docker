#!/bin/bash

source ../_liferay_common.sh

function check_usage {
	if [ -z "${CROWDIN_PERSONAL_TOKEN}" ] ||
	   [ -z "${CROWDIN_PROJECT_ID}" ]
	then
		print_help
	fi

	lc_check_utils crowdin gh jq

	_CROWDIN_BRANCH_NAME="translations-$(date +%Y%m%d-%H%M%S)"
	_CROWDIN_DIR=$(dirname "$(readlink /proc/$$/fd/255 2>/dev/null)")
}

function close_existing_crowdin_pr {
	lc_log INFO "Checking for existing open Crowdin PR..."

	local existing_pr=$(gh pr list \
		--jq '.[0]' \
		--json number,headRefName \
		--repo "liferay/liferay-portal" \
		--search "head:crowdin/translations-" \
		--state open)

	if [ -z "${existing_pr}" ]
	then
		return
	fi

	local pr_number=$(echo "${existing_pr}" | jq --raw-output '.number')

	lc_log INFO "Closing existing Crowdin PR #${pr_number}..."

	gh pr close "${pr_number}" --delete-branch --repo "liferay/liferay-portal"
}

function commit_translations {
	local file_pattern='(Language|bundle)(_[a-zA-Z].*)?\.properties$'

	local changed_files=$(git diff --name-only | grep --extended-regexp "${file_pattern}")

	if [ -z "${changed_files}" ]
	then
		lc_log INFO "No translation changes. Nothing to do."

		exit 0
	fi

	echo "${changed_files}" | xargs git add --

	git config user.email "liferay-release@users.noreply.github.com"
	git config user.name "liferay-release"

	git commit -m "LPD-XXX Update translations from Crowdin"

	git show -1
}

function create_pr {
	lc_log INFO "Opening PR with new translation file(s)..."

	git push origin "${_CROWDIN_BRANCH_NAME}"

	gh pr create \
		--base "master" \
		--body "Automated translations update from Crowdin." \
		--head "${_CROWDIN_BRANCH_NAME}" \
		--repo "liferay/liferay-portal" \
		--title "LPD-XXXX Update translations from Crowdin"
}

function download_translations {
	lc_log INFO "Downloading translations from Crowdin..."

	crowdin download translations \
		--branch master-test \
		--language pt-PT \
		--verbose

	if [ "${?}" -ne 0 ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function upload_sources {
	lc_log INFO "Uploading sources to Crowdin..."

	crowdin upload sources \
		--branch master-test \
		--no-progress \
		--project-id="${CROWDIN_PROJECT_ID}" \
		--token="${CROWDIN_PERSONAL_TOKEN}" \
		--verbose
}

function set_up_liferay_portal_repository {
	lc_cd "liferay-portal"

	git reset --hard &> /dev/null && git clean -dfx &> /dev/null

	if (git remote get-url upstream &>/dev/null)
	then
		git remote set-url upstream "git@github.com:liferay/liferay-portal.git"
	fi

	git pull upstream master &> /dev/null

	git checkout master --force &> /dev/null

	git branch --list "translations-*" | xargs --no-run-if-empty git branch --delete --force

	git checkout -b "${_CROWDIN_BRANCH_NAME}"

	cp "${_CROWDIN_DIR}/crowdin.yml" .
}

function main {
	check_usage

	# close_existing_crowdin_pr

	# lc_time_run lc_clone_repository "liferay-portal"

	set_up_liferay_portal_repository

	# lc_time_run upload_sources

	lc_time_run download_translations

	lc_time_run commit_translations

	rm crowdin.yml

	# create_pr
}

function print_help {
	echo "Usage: ${0}"
	echo ""
	echo "The script reads the following environment variables:"
	echo ""
	echo "    CROWDIN_PERSONAL_TOKEN (required): Personal access token for Crowdin."
	echo "    CROWDIN_PROJECT_ID (required): Project ID in Crowdin."

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

main
