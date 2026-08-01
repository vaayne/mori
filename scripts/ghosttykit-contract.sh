#!/usr/bin/env bash
# Pinned source and compatibility contract for Mori-built GhosttyKit.
readonly MORI_GHOSTTYKIT_SOURCE_COMMIT="aeb8f73790946d9c9ad175b3dafaec9911ef36bb"
readonly MORI_GHOSTTYKIT_BASE_COMMIT="b213a72c03b427607b43c89ff4223a7baa079fe8"
# Explicitly bypass git tag auto-detection: the fork's artifact tags are not
# Ghostty app-version tags, and Ghostty intentionally rejects those as versions.
readonly MORI_GHOSTTYKIT_VERSION="1.3.2-dev"
readonly MORI_GHOSTTYKIT_MIN_IOS_MAJOR="17"
readonly MORI_GHOSTTYKIT_OPTIMIZE="ReleaseFast"
