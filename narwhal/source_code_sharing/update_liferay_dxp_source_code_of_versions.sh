#!/bin/bash

# shellcheck disable=2002,2013

set -o pipefail

source "$(dirname "$(readlink /proc/$$/fd/255 2>/dev/null)")/_common.sh"

BASE_DIR="${PWD}"

REPO_PATH_DXP="${BASE_DIR}/liferay-dxp"
REPO_PATH_EE="${BASE_DIR}/liferay-portal-ee"

TAGS_FILE_DXP="/tmp/tags_file_dxp.txt"
TAGS_FILE_EE="/tmp/tags_file_ee.txt"
TAGS_FILE_NEW="/tmp/tags_file_new.txt"

function check_new_tags {
	if [ ! -f "${TAGS_FILE_NEW}" ]
	then
		echo "No new tags found."

		exit 0
	fi
}

function check_usage {
	LIFERAY_COMMON_LOG_DIR="${PWD}/logs"
	RUN_FETCH_REPOSITORY="true"
	RUN_PUSH_TO_ORIGIN="true"

	while [ "$#" -gt "0" ]
	do
		case "${1}" in
			--debug)
				LIFERAY_COMMON_DEBUG_ENABLED="true"
				LIFERAY_COMMON_LOG_LEVEL="DEBUG"

				;;

			--logdir)
				LIFERAY_COMMON_LOG_DIR="${2}"

				shift 1

				;;

			--no-fetch)
				RUN_FETCH_REPOSITORY="false"

				;;

			--no-push)
				RUN_PUSH_TO_ORIGIN="false"

				;;

			*)
				print_help

				;;
		esac

		shift 1
	done
}

function checkout_branch {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	local branch_name="${2}"

	lc_cd "${BASE_DIR}/${1}"

	git reset --hard
	git clean -fdX

	if (git show-ref --quiet "${branch_name}")
	then
		git checkout -f -q "${branch_name}"

		if [ "${RUN_FETCH_REPOSITORY}" == "true" ]
		then
			git pull origin "${branch_name}"
		fi
	else
		git branch "${branch_name}"
		git checkout -f -q "${branch_name}"
	fi
}

function copy_tag {
	local tag_name="${1}"

	lc_time_run checkout_tag liferay-portal-ee "${tag_name}"

	lc_cd "${REPO_PATH_DXP}"

	lc_time_run run_git_maintenance

	lc_time_run run_rsync "${tag_name}"

	lc_time_run commit_and_tag "${tag_name}"
}

function delete_if_exists {
	local ref="${1}"

	if git show-ref --quiet --verify "refs/heads/${ref}"
	then
		git branch -D "${ref}"
	fi

	if git show-ref --quiet --verify "refs/tags/${ref}"
	then
		git tag -d "${ref}"
	fi
}

function get_all_tags {
	local repository="${1}"

	lc_cd "${BASE_DIR}/${repository}"

	git tag -l --sort=creatordate --format='%(refname:short)' "20*.q*.[0-9]" "20*.q*.[0-9][0-9]" "7.[0-9].[0-9]-u[0-9]*" "7.[0-9].[0-9][0-9]-u[0-9]*"
}

function get_baseline_version {
	local tag_name="${1}"

	local http_response=$(\
		curl \
			"https://api.github.com/repos/liferay/liferay-portal-ee/contents/release.properties?ref=${tag_name}" \
			--header "Accept: application/vnd.github.v3.raw" \
			--header "Authorization: token ${LIFERAY_RELEASE_GITHUB_PAT}" \
			--include \
			--max-time 10 \
			--request GET \
			--retry 3 \
			--silent \
			--write-out "%{http_code}")

	local release_version_trivial=$(\
		echo "${http_response}" | \
		grep "release.info.version.trivial=" | \
		cut --delimiter='=' --fields=2)

	if [[ ! "${release_version_trivial}" =~ ^[0-9]{1,4}$ ]]
	then
		echo ""

		return
	fi

	echo "7.4.13-u${release_version_trivial}"
}

function get_new_tags {
	get_all_tags liferay-portal-ee > "${TAGS_FILE_EE}"

	get_all_tags liferay-dxp > "${TAGS_FILE_DXP}"

	local tag_name

	rm -f "${TAGS_FILE_NEW}"

	# shellcheck disable=SC2013
	for tag_name in $(cat "${TAGS_FILE_EE}")
	do
		if (! grep -qw "^${tag_name}$" "${TAGS_FILE_DXP}")
		then
			echo "${tag_name}" >> "${TAGS_FILE_NEW}"
		fi
	done
}

function print_help {
	echo ""
	echo "Usage:"
	echo ""
	echo "${0} [--logdir <logdir>] [--version <version>] [--no-fetch] [--no-push]"
	echo ""
	echo "    --debug (optional):                   Enabling debug mode"
	echo "    --logdir <logdir> (optional):         Logging directory, defaults to \"\${PWD}/logs\""
	echo "    --version <version> (optional):       Version to handle, defaults to \"7.[0-9].1[03]\""
	echo "    --no-fetch (optional):                Do not fetch DXP repo"
	echo "    --no-push (optional):                 Do not push to origin"
	echo ""
	echo "Default (equals to no arguments):"
	echo ""
	echo "${0} --logdir \"\$PWD/logs\" --version \"7.[0-9].[0-9] 7.[0-9].1[0-9]\""
	echo ""

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

function main {
	check_usage "${@}"

	prepare_repositories

	get_new_tags

	check_new_tags

	local tag_name

	for tag_name in $(cat "${TAGS_FILE_NEW}")
	do
		echo ""

		echo "Processing: ${tag_name}"

		lc_time_run lc_clone_repository liferay-portal-ee "${REPO_PATH_EE}"

		lc_time_run prepare_branch_in_portal_ee "${tag_name}"

		lc_time_run prepare_branch_in_dxp "${tag_name}"

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
		then
			echo "Could not prepare branch in liferay-dxp for ${tag_name}"

			rm -fr "${REPO_PATH_EE}"

			continue
		fi

		rm -fr "${REPO_PATH_EE}"
	done
}

function prepare_branch_in_dxp {
	local tag_name="${1}"

	lc_cd "${REPO_PATH_DXP}"

	git checkout master

	if [[ "${tag_name}" == *q* ]]
	then
		local quarterly_release_baseline_version=$(get_baseline_version "${tag_name}")

		if [ -z "${quarterly_release_baseline_version}" ]
		then
			echo "Unable to get baseline version for ${tag_name}"

			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi

		echo "Baseline version for ${tag_name} is ${quarterly_release_baseline_version}"

		delete_if_exists "${quarterly_release_baseline_version}"

		delete_if_exists "${tag_name}"

		git fetch upstream "refs/tags/${quarterly_release_baseline_version}:refs/tags/${quarterly_release_baseline_version}"

		git checkout -b "${tag_name}" "${quarterly_release_baseline_version}"
	else
		delete_if_exists "7.4.13"

		git checkout -b 7.4.13 upstream/7.4.13
	fi

	rsync -avz --exclude='.git/' --exclude='.github/' "${REPO_PATH_EE}/" "${REPO_PATH_DXP}"

	git add . --force

	git commit -m "${tag_name}"

	git tag --force "${tag_name}"

	if [[ "${tag_name}" == 7.4.13-u* ]]
	then
		git push --force upstream 7.4.13
	fi

	git push --force --verbose upstream "refs/tags/${tag_name}"

	git checkout master --force
}

function prepare_branch_in_portal_ee {
	local tag_name="${1}"

	lc_cd "${REPO_PATH_EE}"

	git fetch upstream "refs/tags/${1}:refs/tags/${1}" --no-tags

	git checkout -b "${1}-branch" "${1}"

	local commit_hash=$(git log -1 --format="%H")

	git filter-branch -f \
		--commit-filter 'git_commit_non_empty_tree "$@"' \
		--index-filter 'git rm -fr --cached --ignore-unmatch \
		":(glob)**/*.gradle" \
		":(glob)**/build*.xml" \
		":(glob)*.properties" \
		":(glob)gradle/**" \
		":(glob)modules/**/gradle.properties" \
		":(glob)portal-web/test-ant-templates/**" \
		":(glob)portal-web/test/com/**" \
		git* \
		gradle* \
		modules/*.report.properties \
		modules/dxp/apps/akismet/* \
		modules/dxp/apps/commerce-demo-pack/* \
		modules/dxp/apps/commerce-punchout/* \
		modules/dxp/apps/commerce-salesforce-connector/* \
		modules/dxp/apps/documentum/* \
		modules/dxp/apps/oauth/* \
		modules/dxp/apps/osb/* \
		modules/dxp/apps/portal-mobile-device-detection-fiftyonedegrees-enterprise/* \
		modules/dxp/apps/portal-search-elasticsearch-cross-cluster-replication/* \
		modules/dxp/apps/portal-search-elasticsearch-monitoring/* \
		modules/dxp/apps/portal-search-learning-to-rank/* \
		modules/dxp/apps/sync/sync/* \
		modules/dxp/apps/sync/vldap/*' \
		--msg-filter 'read message; echo "$message ($GIT_COMMIT)"' \
		"${commit_hash}~1..HEAD" > /dev/null 2>&1

	find . -type f -size +100M -exec rm -f {} \;
}

main "${@}"