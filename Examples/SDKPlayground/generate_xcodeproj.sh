#!/bin/sh
# Regenerate SDKPlayground.xcodeproj and fix XcodeGen's missing local package links.
set -e
cd "$(dirname "$0")"
xcodegen generate
python3 fix_local_package_refs.py
echo "OK: SDKPlayground.xcodeproj is ready (local SPM links patched)."
