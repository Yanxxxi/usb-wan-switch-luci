#!/bin/sh

set -eu

MODE="${1:-auto}"
TAG="f50-wan-switch"
CACHE_DIR="/root/.cache/f50-wan-switch"
HOLIDAY_API="https://timor.tech/api/holiday/info"
USER_AGENT="Mozilla/5.0"
CONFIG_FILE="/root/f50-wan-switch.conf"
CAMPUS_IFACE="eth1"
CAMPUS_CHECK_IP="223.5.5.5"
CAMPUS_LOGIN_URL=""

if [ -r "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
fi

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

choose_auto_mode() {
	hm="$(date +%H%M | sed 's/^0*//')"
	[ -n "$hm" ] || hm=0

	today="$(date_for_offset 0)"
	today_dow="$(dow_for_offset 0)"
	tomorrow="$(date_for_offset 1)"
	tomorrow_dow="$(dow_for_offset 1)"

	if [ "$hm" -lt 750 ]; then
		if is_workday "$today" "$today_dow"; then
			echo f50
		else
			echo campus
		fi
	elif [ "$hm" -ge 2320 ]; then
		if is_workday "$tomorrow" "$tomorrow_dow"; then
			echo f50
		else
			echo campus
		fi
	else
		echo campus
	fi
}

campus_online() {
	ping -I "$CAMPUS_IFACE" -c 1 -W 2 "$CAMPUS_CHECK_IP" >/dev/null 2>&1
}

login_campus() {
	[ -n "$CAMPUS_LOGIN_URL" ] || return 1

	curl -fsS \
		--interface "$CAMPUS_IFACE" \
		--connect-timeout 8 \
		--max-time 15 \
		"$CAMPUS_LOGIN_URL" >/tmp/f50-campus-login.last 2>/tmp/f50-campus-login.err
}

prepare_campus() {
	if campus_online; then
		return 0
	fi

	if login_campus; then
		sleep 2
		campus_online && return 0
	fi

	return 1
}

case "$MODE" in
	auto)
		MODE="$(choose_auto_mode)"
		;;
	day|campus|wan)
		MODE="campus"
		;;
	night|f50)
		MODE="f50"
		;;
	status|luci-status)
		today="$(date_for_offset 0)"
		today_dow="$(dow_for_offset 0)"
		tomorrow="$(date_for_offset 1)"
		tomorrow_dow="$(dow_for_offset 1)"
		echo "default_rule=$(uci -q get mwan3.default_rule.use_policy || true)"
		echo "https=$(uci -q get mwan3.https.use_policy || true)"
		echo "today=$today workday=$(workday_label "$today" "$today_dow")"
		echo "tomorrow=$tomorrow workday=$(workday_label "$tomorrow" "$tomorrow_dow")"
		if [ "$MODE" = "status" ]; then
			mwan3 status
		fi
		exit 0
		;;
	login|campus-login)
		if login_campus; then
			logger -t "$TAG" "campus login requested"
			exit 0
		fi
		logger -t "$TAG" "campus login failed"
		exit 1
		;;
	*)
		echo "Usage: $0 {auto|campus|f50|status|campus-login}" >&2
		exit 2
		;;
esac

case "$MODE" in
	campus)
		if ! prepare_campus; then
			logger -t "$TAG" "campus not ready, keep f50_first"
			policy="f50_first"
		else
			policy="campus_first"
		fi
		;;
	f50)
		policy="f50_first"
		;;
esac

current="$(uci -q get mwan3.default_rule.use_policy || true)"
if [ "$current" = "$policy" ]; then
	logger -t "$TAG" "policy already $policy"
	exit 0
fi

uci set mwan3.default_rule.use_policy="$policy"
if uci -q get mwan3.https >/dev/null; then
	uci set mwan3.https.use_policy="$policy"
fi
uci commit mwan3
/etc/init.d/mwan3 restart

logger -t "$TAG" "switched policy to $policy"
