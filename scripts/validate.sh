#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh -n "$root/files/root/f50-wan-switch.sh"
sh -n "$root/install-openwrt.sh"

if grep -R -n -E 'user_password=|luci_password=|user_account=|CAMPUS_LOGIN_URL=.*(password|passwd|pwd)=|[0-9]{8,}@qq\.com|10\.2\.[0-9]+\.[0-9]+' "$root" \
	--exclude-dir=.git \
	--exclude=f50-wan-switch.conf.example \
	--exclude=validate.sh; then
	echo "Potential private value found." >&2
	exit 1
fi

echo "Validation passed."
