# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Liferay's Docker image build system. Builds, tests, and releases Docker images for Liferay Portal/DXP and supporting services (Batch, Job Runner, Node Runner, JAR Runner, Caddy, Squid, Zabbix, etc.).

## Key Commands

```bash
# Build all images
./build_all_images.sh

# Build a specific bundle image
./build_bundle_image.sh

# Build base image
./build_base_image.sh

# Run tests (routes automatically based on changed files via git diff)
./run_tests.sh

# Run a specific test script
./test_build_bundle_image.sh
./test_bundle_image.sh

# Bump version (supports major/minor/micro)
./release_notes.sh

# Build a full release
./release/build_release.sh
```

## Repository Structure

```
/                           # Root: build/test scripts + shared utilities
  build_*_image.sh          # Per-service image builders
  test_*.sh                 # Per-service test scripts
  run_tests.sh              # Test orchestrator (routes by changed files)
  _common.sh                # Docker build utilities (buildx, downloads, temp dirs)
  _env_common.sh            # Environment detection (CI slave, release slave, local)
  _liferay_common.sh        # Curl with retries, background process management
  _github.sh                # GitHub integration helpers
  _release_common.sh        # Release workflow functions
  _test_common.sh           # Test infrastructure utilities
  bundles.yml               # Central config: ALL supported Liferay versions, URLs, fix packs

templates/                  # Dockerfile templates per service
  base/                     # Ubuntu base image with Java
  bundle/                   # Main Portal/DXP image (Tomcat)
  _jdk/                     # JDK base layers (JDK 8, 11, 21)
  batch/, job-runner/, ...  # Supporting service templates
  _common/                  # Shared resources across templates

release/                    # Release pipeline
  build_release.sh          # Main release orchestrator
  release_gold.sh           # Gold/GA release automation
  rebuild_bom_files.sh      # Bill of Materials management
  _bom.sh, _hotfix.sh, ...  # Release component utilities

narwhal/                    # Extended tooling: Jenkins integration, Puppet config, Docker Compose samples
```

## Architecture

**Build flow**: `build_all_images.sh` → per-service `build_*_image.sh` scripts → read from `bundles.yml` → download artifacts → construct Dockerfile from `templates/` → `docker buildx build` → push to Docker Hub.

**bundles.yml** is the source of truth for every supported version. Each entry defines bundle URLs, fix packs, hotfixes, JDK version, and test configuration. Most scripts iterate over or query this file.

**Shared utilities** (`_*.sh`) are sourced by build/test scripts — not executed directly. `_common.sh` handles Docker mechanics; `_liferay_common.sh` handles network/git/process utilities.

**Testing**: `run_tests.sh` uses `git diff` against the previous commit to determine which test scripts to run. Container tests launch Docker containers with network/volume setup and validate health, patches, file structure.

**Release versioning**: `release_notes.sh` manages semantic versioning (MAJOR.MINOR.MICRO). Commit messages with issue prefixes (`LPD-*`, `LCD-*`, `DOCKER-*`) trigger version bumps; `#majorchange`/`#minorchange` in commit messages control the jump level. Snapshots include the git hash when there are unreleased changes.

## Environment Variables

| Variable | Purpose |
|---|---|
| `LIFERAY_DOCKER_REPOSITORY` | Docker Hub repository to push images to |
| `LIFERAY_DOCKER_IMAGE_PLATFORMS` | Multi-platform targets (e.g. `linux/amd64,linux/arm64`) |
| `LIFERAY_DOCKER_DEVELOPER_MODE` | Enables local development shortcuts |
| `LIFERAY_DOCKER_FIX_PACK_URL` | Override fix pack download URL |

## Multi-Platform Builds

Images are built via `docker buildx`. Platform targets are controlled by `LIFERAY_DOCKER_IMAGE_PLATFORMS`. The build scripts set up a buildx builder instance if one doesn't exist.

## Local Development

Scripts detect whether they're running on a CI slave, release slave, or local machine via `_env_common.sh`. When local copies of dependencies exist under `/home/me/dev/projects/`, they are used instead of fetching remote versions.
