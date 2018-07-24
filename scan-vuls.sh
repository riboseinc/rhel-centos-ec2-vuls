#!/bin/bash
#
# scan-vuls.sh
#
# Setup and execute the Vuls vulnerability scanner (https://vuls.io/) for RHEL/CentOS on EC2
#
# This script does the following:
# 1) Create a basic Vuls configuration using the ec2-user
# 2) Create a SSH keypair so Vuls can ssh into localhost
# 3) Run a scan
# 4) Convert the json report to text
# 5) Delete the keypair and temporary files
# 6) Display the report
#
# Dependencies:
# 1) Installed Vuls (use: install-vuls.sh)
# 2) Installed ssh-keygen and ssh-keyscan

set -uo pipefail

readonly __progname="$(basename "$0")"

errx() {
	echo -e "${__progname}: $*" >&2

	exit 1
}

main() {
	[ "${EUID}" -ne 0 ] && \
		errx "need root"

	local -r vulsenv="/etc/profile.d/vulsenv.sh"

	echo "${__progname}: sourcing '${vulsenv}'"
	. "${vulsenv}" || \
		errx "cannot open '${vulsenv}'"

	for cmd in go ssh-keygen ssh-keyscan vuls; do
		which "${cmd}" >/dev/null || \
			errx "cannot execute '${cmd}'"
	done

	local -r vulspath="/usr/local/vuls"
	local -r configpath="/usr/local/etc"
	local -r user="ec2-user"

	local -r configfile="/${configpath}/vuls-config.toml"
	local -r ip="$(curl -s curl http://169.254.169.254/latest/meta-data/local-ipv4)"
	local -r idrsa="/home/${user}/.ssh/vuls_id_rsa"
	local -r idrsapub="/home/${user}/.ssh/vuls_id_rsa.pub"
	local -r host="local"

	echo "${__progname}: creating '${configfile}'"
	echo '[default]' > "${configfile}"
	echo 'port = "22"' >> "${configfile}"
	echo "user = \"${user}\"" >> "${configfile}"
	echo "keyPath = \"${idrsa}\"" >> "${configfile}"
	echo '[servers]' >> "${configfile}"
	echo "[servers.${host}]" >> "${configfile}"
	echo "host = \"${ip}\"" >> "${configfile}"
	chmod 500 "${configfile}"

	echo "${__progname}: config file:"
	cat "${configfile}"

	echo "${__progname}: creating SSH keypair in '${idrsa}'"
	ssh-keygen -t rsa -N '' -C 'vuls' -f "${idrsa}"
	local -r authkey="/home/${user}/.ssh/authorized_keys"
	cat "${idrsapub}" >> "${authkey}"
	rm -f "${idrsapub}"

	local -r known="/root/.ssh/known_hosts"
	touch "${known}"
	local -r key="$(ssh-keyscan -t rsa -H "${ip}" 2>/dev/null | awk '{ print $3 }')"
	grep -q "${key}" "${known}" || \
		ssh-keyscan -t rsa -H "${ip}" 2>/dev/null >> "${known}"

	echo "${__progname}: running 'vuls configtest'"
	vuls configtest -config="${configfile}" || \
		errx "vuls configtest failed"

	local -r osrelease="/etc/os-release"
	# check if we're on RHEL or CentOS:
	. "${osrelease}" || \
		errx "cannot open '${osrelease}'"

	local rhel=1
	echo "${NAME}" | grep -q "Red Hat Enterprise Linux" && \
		local rhel=0

	if [ "${rhel}" -eq 0 ]; then
		# on RHEL 7 the yum repo keys and certificates not readable for the ec2-user:
		#
		# /etc/pki/rhui:
		# -rw-------. 1 root root 11001 Nov  3  2017 cdn.redhat.com-chain.crt
		# -rw-------. 1 root root  1675 Nov  3  2017 content-rhel7.key
		# -rw-------. 1 root root  1679 Nov  3  2017 rhui-client-config-server-7.key
		#
		# /etc/pki/rhui/product:
		# -rw-------. 1 root root  6530 Nov  3  2017 content-rhel7.crt
		# -rw-------. 1 root root  2098 Nov  3  2017 rhui-client-config-server-7.crt
		#
		# Thus a vulnerability scan executed as the ec2-user will fail.

		echo "${__progname}: temporarily setting read permissions on '/etc/pki/rhui/*.{key,crt}'"
		chmod 755 /etc/pki/rhui/*.{key,crt}
		chmod 755 /etc/pki/rhui/product/*.crt
	fi

	cd "${vulspath}"

	echo "${__progname}: running 'vuls scan -deep -config=${configfile}'"
	vuls scan -deep -config="${configfile}" >/dev/null || \
		errx "vuls scan failed"

	# make Vuls convert the json report to text
	vuls report -to-localfile -config="${configfile}" >/dev/null

	if [ "${rhel}" -eq 0 ]; then
		echo "${__progname}: reverting read permissions on '/etc/pki/rhui/*.{key,crt}'"
		chmod 600 /etc/pki/rhui/*.{key,crt}
		chmod 600 /etc/pki/rhui/product/*.crt
	fi

	# now clean up
	rm -f "${configfile}"

	echo "${__progname}: removing 'vuls' from '${authkey}'"
	sed -i '/vuls/d' "${authkey}"

	echo "${__progname}: removing '${idrsa}' and '${idrsapub}'"
	rm -f "${idrsa}" "${idrsapub}"

	local -r report="${vulspath}/results/current/${host}_short.txt"
	[ ! -f "${report}" ] && \
		errx "cannot open '${report}'"

	grep -v "No CVE-IDs" "${report}" | grep -q "CVE"
	if [ $? -eq 0 ]; then
		echo "${__progname}: vulnerabilities identified:"
		cat "${report}"

		return 1
	else
		echo "${__progname}: no vulnerabilities identified"
	fi

	return 0
}

main

exit $?
