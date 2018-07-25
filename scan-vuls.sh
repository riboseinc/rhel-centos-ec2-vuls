#!/bin/bash
#
# scan-vuls.sh
#
# Execute a Vuls (https://vuls.io) scan for RHEL/CentOS on EC2
#
# This script does the following:
# 1) Create a basic localhost Vuls configuration
# 2) Run a scan
# 3) Convert the json report to text
# 4) Display the report
#
# Dependencies:
# 1) Installed Vuls (use: install-vuls.sh)

set -uo pipefail

readonly __progname="$(basename "$0")"

errx() {
	echo -e "${__progname}: $*" >&2

	exit 1
}

main() {
	[ "${EUID}" -ne 0 ] && \
		errx "need root"

	local -r vulsenv="/etc/profile.d/vuls-env.sh"

	echo "${__progname}: sourcing '${vulsenv}'"
	. "${vulsenv}" || \
		errx "cannot open '${vulsenv}'"

	for cmd in go vuls; do
		which "${cmd}" >/dev/null || \
			errx "cannot execute '${cmd}'"
	done

	local -r vulspath="/usr/local/vuls"
	local -r configpath="/usr/local/etc"
	local -r configfile="/${configpath}/vuls-config.toml"

	echo "${__progname}: creating '${configfile}'"
	echo '[servers]' > "${configfile}"
	echo "[servers.localhost]" >> "${configfile}"
	echo "host = \"localhost\"" >> "${configfile}"
	echo "port = \"local\"" >> "${configfile}"
	chmod 500 "${configfile}"

	echo "${__progname}: config file:"
	cat "${configfile}"

	echo "${__progname}: running 'vuls configtest'"
	vuls configtest -config="${configfile}" || \
		errx "vuls configtest failed"

	cd "${vulspath}"

	echo "${__progname}: running 'vuls scan'"
	vuls scan -deep -config="${configfile}" >/dev/null || \
		errx "vuls scan failed"

	# make Vuls convert the json report to text
	echo "${__progname}: running 'vuls report'"
	vuls report -format-full-text -to-localfile -config="${configfile}" >/dev/null

	local -r report="${vulspath}/results/current/localhost_full.txt"
	[ ! -f "${report}" ] && \
		errx "cannot open '${report}'"

	grep -v "No CVE-IDs" "${report}" | grep -q "CVE"
	if [ $? -eq 0 ]; then
		echo "${__progname}: vulnerabilities identified:"
		cat "${report}"
		echo

		return 1
	else
		echo "${__progname}: no vulnerabilities identified"
		echo
	fi

	return 0
}

main

exit $?
