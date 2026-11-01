#!/bin/bash
# Führt die Tests des Audio-/Sequencer-/Speicher-Kerns aus (macOS oder Linux mit Swift-Toolchain).
set -euo pipefail
cd "$(dirname "$0")/../Packages/NexoraCore"
swift test "$@"
