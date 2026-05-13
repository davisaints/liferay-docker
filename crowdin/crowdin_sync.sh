#!/bin/bash

source "$(dirname "$(readlink -f "$0")")/../_common.sh"

set -euo pipefail

PORTAL_REPO="${PORTAL_REPO:-liferay-release/liferay-portal}"
BASE_BRANCH="${BASE_BRANCH:-master}"
BRANCH_NAME="crowdin/translations-$(date +%Y%m%d-%H%M%S)"

function close_existing_crowdin_pr {
	echo "Checking for existing open Crowdin PR..."

	local existing_pr

	existing_pr=$(gh pr list \
		--repo "${PORTAL_REPO}" \
		--search "head:crowdin/translations-" \
		--state open \
		--json number,headRefName \
		--jq '.[0]')

	if [[ -z "${existing_pr}" ]]; then
		return
	fi

	local pr_number old_branch

	pr_number=$(echo "${existing_pr}" | jq -r '.number')
	old_branch=$(echo "${existing_pr}" | jq -r '.headRefName')

	echo "Closing existing Crowdin PR #${pr_number} (${old_branch})..."

	gh pr close "${pr_number}" --repo "${PORTAL_REPO}"

	git push \
		"https://x-access-token:${LIFERAY_RELEASE_GITHUB_PAT}@github.com/${PORTAL_REPO}.git" \
		--delete "${old_branch}" 2>/dev/null || true
}

function clone_portal {
	echo "Cloning ${PORTAL_REPO}..."

	git clone --depth=1 \
		"https://x-access-token:${LIFERAY_RELEASE_GITHUB_PAT}@github.com/${PORTAL_REPO}.git" \
		portal
}

function download_translations {
	echo "Downloading translations from Crowdin..."

	crowdin download translations \
		--no-progress \
		--project-id="${CROWDIN_PROJECT_ID}" \
		--token="${CROWDIN_PERSONAL_TOKEN}"
}

function create_pr {
	local changed_file_count="${1}"

	echo "Opening PR with ${changed_file_count} changed translation file(s)..."

	git push \
		"https://x-access-token:${LIFERAY_RELEASE_GITHUB_PAT}@github.com/${PORTAL_REPO}.git" \
		"${BRANCH_NAME}"

	gh pr create \
		--repo "${PORTAL_REPO}" \
		--base "${BASE_BRANCH}" \
		--head "${BRANCH_NAME}" \
		--title "TRL-0000 Update translations from Crowdin" \
		--body "Automated translations update from Crowdin.

Contains only \`Language*.properties\` and \`bundle*.properties\` changes. Do not edit this PR manually."
}

function main {
	close_existing_crowdin_pr

	clone_portal

	cd portal

	git checkout -b "${BRANCH_NAME}"

	download_translations

	mapfile -t changed_files < <(git diff --name-only | \
		grep -E '(Language|bundle)(_[a-zA-Z].*)?\.properties$' || true)

	if [[ ${#changed_files[@]} -eq 0 ]]; then
		echo "No translation changes. Nothing to do."

		exit 0
	fi

	git add -- "${changed_files[@]}"

	git config user.email "crowdin-bot@users.noreply.github.com"
	git config user.name "crowdin-bot"

	git commit -m "TRL-0000 Update translations from Crowdin"

	create_pr "${#changed_files[@]}"
}

main
