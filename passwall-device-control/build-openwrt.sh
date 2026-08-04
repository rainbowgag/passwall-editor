#!/bin/sh

set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VERSION="$(tr -d '\r\n' < "$PROJECT_DIR/VERSION")"
BUILD_DIR="${TMPDIR:-/tmp}/passwall-device-ipk.$$"
OUTPUT_DIR="$PROJECT_DIR/dist"
OUTPUT="$OUTPUT_DIR/luci-app-passwall-device_${VERSION}_all.ipk"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT INT TERM
mkdir -p "$BUILD_DIR/control" "$BUILD_DIR/data" "$BUILD_DIR/archive" "$OUTPUT_DIR"
cp -a "$PROJECT_DIR/package/CONTROL/." "$BUILD_DIR/control/"
cp -a "$PROJECT_DIR/root/." "$BUILD_DIR/data/"
cp -p "$BUILD_DIR/data/etc/config/passwall_device" "$BUILD_DIR/data/usr/share/passwall-device/default-config"
rm -f "$BUILD_DIR/data/etc/config/passwall_device"

chmod 755 "$BUILD_DIR/control/postinst" "$BUILD_DIR/control/prerm"
chmod 755 "$BUILD_DIR/data/etc/init.d/passwall-device" "$BUILD_DIR/data/usr/share/passwall-device/app.lua" "$BUILD_DIR/data/usr/share/passwall-device/"*.sh
chmod 644 "$BUILD_DIR/data/usr/share/passwall-device/default-config" "$BUILD_DIR/data/usr/lib/lua/luci/controller/passwall_device.lua" "$BUILD_DIR/data/usr/lib/lua/luci/view/passwall_device/"*.htm "$BUILD_DIR/data/usr/share/rpcd/acl.d/luci-app-passwall-device.json" "$BUILD_DIR/data/usr/share/passwall-device/VERSION"

tar -czf "$BUILD_DIR/archive/control.tar.gz" -C "$BUILD_DIR/control" .
tar -czf "$BUILD_DIR/archive/data.tar.gz" -C "$BUILD_DIR/data" .
printf '2.0\n' > "$BUILD_DIR/archive/debian-binary"
tar -czf "$OUTPUT" -C "$BUILD_DIR/archive" debian-binary control.tar.gz data.tar.gz
echo "$OUTPUT"
