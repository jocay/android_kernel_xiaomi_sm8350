#!/bin/sh
# Builds the installable module zip: ./pack.sh [output directory]
# Install on the device with: ksud module install venus_server-<version>.zip
set -eu
cd "$(dirname "$0")"
version=$(sed -n 's/^version=//p' module.prop)
out="${1:-.}/venus_server-$version.zip"
rm -f "$out"
zip -q -X "$out" module.prop config.sh post-fs-data.sh service.sh uninstall.sh
echo "$out"
