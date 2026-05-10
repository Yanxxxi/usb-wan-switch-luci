#!/bin/sh

set -eu

MODE="${1:-auto}"
TAG="wan-usb-switch"
CACHE_DIR="/root/.cache/f50-wan-switch"
HOLIDAY_API="https://timor.tech/api/holiday/info"
USER_AGENT="Mozilla/5.0"

CAMPUS_IF="wan"
USB_IF="usb"
USB_DEV="usb0"
CAMPUS_POLICY="campus_only"
USB_POLICY="usb_only"
CAMPUS_LOGIN="/root/cumt/login.sh"
PORTAL_IP="10.2.5.251"

USB_PREPARE_START="2325"
USB_SWITCH_START="2330"
CAMPUS_PREPARE_START="0755"
CAMPUS_SWITCH_START="0800"

date_for_offset() {
	now="$(date +%s)"
	offset="${1:-0}"
	date -d "@$((now + offset * 86400))" +%F
}

dow_for_offset() {
	now="$(date +%s)"
	offset="${1:-0}"
	date -d "@$((now + offset * 86400))" +%u
}

time_hm() {
	hm="$(date +%H%M | sed 's/^0*//')"
	[ -n "$hm" ] || hm=0
	echo "$hm"
}

holiday_type_for_date() {
	day="$1"
	cache_file="$CACHE_DIR/$day.type"

	if [ -s "$cache_file" ]; then
		cat "$cache_file"
		return 0
	fi

	mkdir -p "$CACHE_DIR"
	body="$(
		curl -fsS \
			-A "$USER_AGENT" \
			--connect-timeout 5 \
			--max-time 8 \
			"$HOLIDAY_API/$day" 2>/dev/null
	)" || return 1

	code="$(printf '%s' "$body" | jsonfilter -e '@.code' 2>/dev/null || true)"
	holiday_type="$(printf '%s' "$body" | jsonfilter -e '@.type.type' 2>/dev/null || true)"

	if [ "$code" = "0" ] && [ -n "$holiday_type" ]; then
		printf '%s\n' "$holiday_type" > "$cache_file"
		printf '%s\n' "$holiday_type"
		return 0
	fi

	return 1
}

is_workday() {
	day="$1"
	dow="$2"

	if holiday_type="$(holiday_type_for_date "$day")"; then
		case "$holiday_type" in
			0|3)
				return 0
				;;
			1|2)
				return 1
				;;
		esac
	fi

	case "$dow" in
		1|2|3|4|5)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

workday_label() {
	day="$1"
	dow="$2"

	if is_workday "$day" "$dow"; then
		echo yes
	else
		echo no
	fi
}

ensure_interface_up() {
	iface="$1"

	if ifstatus "$iface" 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null | grep -q '^true$'; then
		return 0
	fi

	logger -t "$TAG" "bringing interface $iface up"
	ifup "$iface" 2>/dev/null || logger -t "$TAG" "ifup $iface failed"
	return 0
}

interface_value() {
	iface="$1"
	path="$2"
	ifstatus "$iface" 2>/dev/null | jsonfilter -e "$path" 2>/dev/null | head -n 1 || true
}

interface_device() {
	iface="$1"
	dev="$(interface_value "$iface" '@.l3_device')"
	[ -n "$dev" ] || dev="$(interface_value "$iface" '@.device')"
	[ -n "$dev" ] || dev="$(uci -q get network."$iface".device || true)"
	[ -n "$dev" ] || dev="$USB_DEV"
	printf '%s\n' "$dev"
}

interface_ipv4() {
	iface="$1"
	interface_value "$iface" '@["ipv4-address"][0].address'
}

interface_gateway() {
	iface="$1"
	dev="$(interface_device "$iface")"
	gw="$(interface_value "$iface" '@.route[@.target="0.0.0.0"].nexthop')"
	[ -n "$gw" ] || gw="$(interface_value "$iface" '@.route[0].nexthop')"
	[ -n "$gw" ] || gw="$(ip -4 route show dev "$dev" 2>/dev/null | awk '/default[[:space:]]+via/ { print $3; exit }')"

	if [ -z "$gw" ]; then
		ipaddr="$(interface_ipv4 "$iface")"
		case "$ipaddr" in
			*.*.*.*)
				gw="$(printf '%s\n' "$ipaddr" | awk -F. '{ print $1"."$2"."$3".1" }')"
				;;
		esac
	fi

	printf '%s\n' "$gw"
}

wait_interface_ipv4() {
	iface="$1"
	tries="${2:-15}"

	while [ "$tries" -gt 0 ]; do
		if [ -n "$(interface_ipv4 "$iface")" ]; then
			return 0
		fi
		sleep 1
		tries=$((tries - 1))
	done

	logger -t "$TAG" "interface $iface has no IPv4 address after waiting"
	return 0
}

wait_interface_ipv4_required() {
	iface="$1"
	tries="${2:-20}"

	while [ "$tries" -gt 0 ]; do
		if [ -n "$(interface_ipv4 "$iface")" ]; then
			return 0
		fi
		sleep 1
		tries=$((tries - 1))
	done

	logger -t "$TAG" "interface $iface still has no IPv4 address; abort switch"
	return 1
}

force_campus_default_route() {
	dev="$(interface_device "$CAMPUS_IF")"
	gw="$(interface_gateway "$CAMPUS_IF")"

	ip -4 route del default dev "$USB_IF" 2>/dev/null || true
	ip -4 route del default dev "$USB_DEV" 2>/dev/null || true

	if [ -n "$gw" ]; then
		ip -4 route replace default via "$gw" dev "$dev" metric 10 2>/dev/null || logger -t "$TAG" "failed to force default route via $gw dev $dev"
	else
		ip -4 route replace default dev "$dev" metric 10 2>/dev/null || logger -t "$TAG" "failed to force default route dev $dev"
	fi

	ip -4 route flush cache 2>/dev/null || true
	return 0
}

force_usb_default_route() {
	dev="$(interface_device "$USB_IF")"
	gw="$(interface_gateway "$USB_IF")"

	ip -4 route del default dev "$CAMPUS_IF" 2>/dev/null || true
	ip -4 route del default dev wan 2>/dev/null || true

	if [ -n "$gw" ]; then
		ip -4 route replace default via "$gw" dev "$dev" metric 20 2>/dev/null || logger -t "$TAG" "failed to force default route via $gw dev $dev"
	else
		ip -4 route replace default dev "$dev" metric 20 2>/dev/null || logger -t "$TAG" "failed to force default route dev $dev"
	fi

	ip -4 route flush cache 2>/dev/null || true
	echo "nameserver 223.5.5.5" > /tmp/resolv.conf 2>/dev/null || true
	echo "nameserver 119.29.29.29" >> /tmp/resolv.conf 2>/dev/null || true
	return 0
}

refresh_route_cache() {
	ip -4 route flush cache 2>/dev/null || true
}

enable_billing_protection() {
	logger -t "$TAG" "enabling USB billing protection: disable mwan3 USB monitoring and bring USB down"

	if uci -q get mwan3."$USB_IF" >/dev/null; then
		uci set mwan3."$USB_IF".enabled='0' || logger -t "$TAG" "failed to disable mwan3.$USB_IF"
		uci commit mwan3 || logger -t "$TAG" "failed to commit mwan3 after disabling $USB_IF"
	else
		logger -t "$TAG" "mwan3.$USB_IF not found; skip disabling mwan3 monitoring"
	fi

	ifdown "$USB_IF" 2>/dev/null || logger -t "$TAG" "ifdown $USB_IF failed"
	return 0
}

disable_billing_protection_for_usb() {
	logger -t "$TAG" "disabling USB billing protection: bring USB up and enable mwan3 USB monitoring"

	ensure_interface_up "$USB_IF"
	wait_interface_ipv4_required "$USB_IF" 30 || return 1

	if uci -q get mwan3."$USB_IF" >/dev/null; then
		uci set mwan3."$USB_IF".enabled='1' || logger -t "$TAG" "failed to enable mwan3.$USB_IF"
		uci commit mwan3 || logger -t "$TAG" "failed to commit mwan3 after enabling $USB_IF"
	else
		logger -t "$TAG" "mwan3.$USB_IF not found; skip enabling mwan3 monitoring"
	fi

	return 0
}

restart_mwan3() {
	/etc/init.d/mwan3 restart >/dev/null 2>&1 || logger -t "$TAG" "mwan3 restart failed"
	return 0
}

set_mwan_policy() {
	policy="$1"
	changed=0

	if [ "$(uci -q get mwan3.default_rule.use_policy || true)" != "$policy" ]; then
		if uci set mwan3.default_rule.use_policy="$policy"; then
			changed=1
		else
			logger -t "$TAG" "failed to set mwan3.default_rule.use_policy=$policy"
		fi
	fi

	if uci -q get mwan3.https >/dev/null; then
		if [ "$(uci -q get mwan3.https.use_policy || true)" != "$policy" ]; then
			if uci set mwan3.https.use_policy="$policy"; then
				changed=1
			else
				logger -t "$TAG" "failed to set mwan3.https.use_policy=$policy"
			fi
		fi
	fi

	if [ "$changed" = "1" ]; then
		uci commit mwan3 || logger -t "$TAG" "failed to commit mwan3 policy changes"
	fi

	return 0
}

run_campus_login() {
	if [ ! -x "$CAMPUS_LOGIN" ]; then
		logger -t "$TAG" "campus login script not executable: $CAMPUS_LOGIN"
		return 0
	fi

	logger -t "$TAG" "running campus login through $PORTAL_IP in background"
	(
		"$CAMPUS_LOGIN" >/dev/null 2>&1 || logger -t "$TAG" "campus login failed"
	) &
	return 0
}

prepare_usb() {
	logger -t "$TAG" "preparing metered USB network"
	disable_billing_protection_for_usb || {
		logger -t "$TAG" "USB is not ready during preheat"
		return 1
	}
	echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
	restart_mwan3
	force_usb_default_route
	refresh_route_cache
	return 0
}

prepare_campus() {
	logger -t "$TAG" "preparing campus network"
	ensure_interface_up "$CAMPUS_IF"
	wait_interface_ipv4_required "$CAMPUS_IF" 20 || return 1
	run_campus_login
	return 0
}

switch_to_campus() {
	current="$(uci -q get mwan3.default_rule.use_policy || true)"

	logger -t "$TAG" "switching to campus-only policy and enabling USB billing protection"
	prepare_campus || {
		logger -t "$TAG" "campus WAN is not ready; keep USB online and abort campus switch"
		return 1
	}
	set_mwan_policy "$CAMPUS_POLICY"
	force_campus_default_route
	enable_billing_protection
	restart_mwan3
	refresh_route_cache

	if [ "$current" = "$CAMPUS_POLICY" ]; then
		logger -t "$TAG" "policy already $CAMPUS_POLICY; refreshed campus login and enabled USB billing protection"
	else
		logger -t "$TAG" "switched policy to $CAMPUS_POLICY and enabled USB billing protection"
	fi

	return 0
}

switch_to_usb() {
	current="$(uci -q get mwan3.default_rule.use_policy || true)"

	logger -t "$TAG" "switching to USB-only policy and disabling USB billing protection"
	disable_billing_protection_for_usb || {
		logger -t "$TAG" "USB is not ready; abort USB switch"
		return 1
	}
	echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
	set_mwan_policy "$USB_POLICY"
	restart_mwan3
	force_usb_default_route
	refresh_route_cache

	if [ "$current" = "$USB_POLICY" ]; then
		logger -t "$TAG" "policy already $USB_POLICY; USB billing protection is disabled"
	else
		logger -t "$TAG" "switched policy to $USB_POLICY and disabled USB billing protection"
	fi

	return 0
}

shutdown_wan() {
	logger -t "$TAG" "safely shutting down campus WAN: switch to USB first"
	disable_billing_protection_for_usb || {
		logger -t "$TAG" "USB is not ready; abort campus WAN shutdown"
		return 1
	}
	echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
	set_mwan_policy "$USB_POLICY"
	restart_mwan3
	force_usb_default_route
	refresh_route_cache
	sleep 3
	ifdown "$CAMPUS_IF" 2>/dev/null || logger -t "$TAG" "ifdown $CAMPUS_IF failed"
	ip -4 route del default dev "$CAMPUS_IF" 2>/dev/null || true
	ip -4 route del default dev wan 2>/dev/null || true
	force_usb_default_route
	refresh_route_cache
	return 0
}

shutdown_usb() {
	logger -t "$TAG" "safely shutting down USB: switch to campus WAN first"
	prepare_campus || {
		logger -t "$TAG" "campus WAN is not ready; keep USB online and abort USB shutdown"
		return 1
	}
	set_mwan_policy "$CAMPUS_POLICY"
	force_campus_default_route
	enable_billing_protection
	restart_mwan3
	refresh_route_cache
	return 0
}

choose_auto_action() {
	hm="$(time_hm)"

	today="$(date_for_offset 0)"
	today_dow="$(dow_for_offset 0)"
	tomorrow="$(date_for_offset 1)"
	tomorrow_dow="$(dow_for_offset 1)"

	if [ "$hm" -lt "$CAMPUS_PREPARE_START" ]; then
		if is_workday "$today" "$today_dow"; then
			echo usb
		else
			echo campus
		fi
	elif [ "$hm" -lt "$CAMPUS_SWITCH_START" ]; then
		if is_workday "$today" "$today_dow"; then
			echo prepare-campus
		else
			echo campus
		fi
	elif [ "$hm" -ge "$USB_SWITCH_START" ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo usb
		else
			echo campus
		fi
	elif [ "$hm" -ge "$USB_PREPARE_START" ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo prepare-usb
		else
			echo campus
		fi
	else
		echo campus
	fi
}

next_action_label() {
	hm="$(time_hm)"
	today="$(date_for_offset 0)"
	today_dow="$(dow_for_offset 0)"
	tomorrow="$(date_for_offset 1)"
	tomorrow_dow="$(dow_for_offset 1)"

	if [ "$hm" -lt "$CAMPUS_PREPARE_START" ]; then
		if is_workday "$today" "$today_dow"; then
			echo "07:55 预认证校园网，08:00 切回校园 WAN"
		else
			echo "保持校园 WAN"
		fi
	elif [ "$hm" -lt "$CAMPUS_SWITCH_START" ]; then
		if is_workday "$today" "$today_dow"; then
			echo "08:00 切回校园 WAN 并关闭 USB 计费网络"
		else
			echo "保持校园 WAN"
		fi
	elif [ "$hm" -ge "$USB_SWITCH_START" ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo "明早 07:55 预认证校园网"
		else
			echo "保持校园 WAN"
		fi
	elif [ "$hm" -ge "$USB_PREPARE_START" ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo "23:30 切到 USB 随身 WiFi"
		else
			echo "保持校园 WAN"
		fi
	else
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo "23:25 预热 USB，23:30 切到 USB"
		else
			echo "保持校园 WAN"
		fi
	fi
}

policy_to_mode() {
	policy="$1"

	case "$policy" in
		"$USB_POLICY"|usb_first|f50_first)
			echo usb
			;;
		"$CAMPUS_POLICY"|campus_first)
			echo campus
			;;
		*)
			echo unknown
			;;
	esac
}

print_luci_status() {
	today="$(date_for_offset 0)"
	today_dow="$(dow_for_offset 0)"
	tomorrow="$(date_for_offset 1)"
	tomorrow_dow="$(dow_for_offset 1)"
	policy="$(uci -q get mwan3.default_rule.use_policy || true)"
	https_policy="$(uci -q get mwan3.https.use_policy || true)"
	usb_mwan_enabled="$(uci -q get mwan3."$USB_IF".enabled || true)"

	echo "mode=$(policy_to_mode "$policy")"
	echo "policy=$policy"
	echo "default_rule=$policy"
	echo "https=$https_policy"
	echo "usb_mwan_enabled=$usb_mwan_enabled"
	echo "today=$today workday=$(workday_label "$today" "$today_dow")"
	echo "tomorrow=$tomorrow workday=$(workday_label "$tomorrow" "$tomorrow_dow")"
	echo "auto_action=$(choose_auto_action)"
	echo "next_action=$(next_action_label)"
}

case "$MODE" in
	auto)
		MODE="$(choose_auto_action)"
		;;
	day|campus|wan)
		MODE="campus"
		;;
	night|usb|f50)
		MODE="usb"
		;;
	prepare-usb|preheat-usb)
		MODE="prepare-usb"
		;;
	prepare-campus|preauth-campus)
		MODE="prepare-campus"
		;;
	down-wan|wan-down|stop-wan)
		MODE="down-wan"
		;;
	down-usb|usb-down|stop-usb)
		MODE="down-usb"
		;;
	login)
		MODE="login"
		;;
	status|luci-status)
		print_luci_status
		if [ "$MODE" = "status" ]; then
			mwan3 status
		fi
		exit 0
		;;
	*)
		echo "Usage: $0 {auto|campus|usb|prepare-usb|prepare-campus|down-wan|down-usb|login|status}" >&2
		exit 2
		;;
esac

case "$MODE" in
	campus)
		switch_to_campus
		;;
	usb)
		switch_to_usb
		;;
	prepare-usb)
		prepare_usb
		;;
	prepare-campus)
		prepare_campus
		;;
	down-wan)
		shutdown_wan
		;;
	down-usb)
		shutdown_usb
		;;
	login)
		run_campus_login
		;;
esac
