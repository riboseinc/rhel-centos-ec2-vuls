#!/bin/bash
#
# install-vuls.sh
#
# Install the Vuls vulnerability scanner (https://vuls.io/) on RHEL/CentOS on EC2
#
# Dependencies:
# 1) go
# 2) git 
# 3) gcc

set -uo pipefail

readonly __progname="$(basename "$0")"

errx() {
	echo -e "${__progname}: $*" >&2

	exit 1
}

main() {
	[ "${EUID}" -ne 0 ] && \
		errx "need root"

	for cmd in go git gcc; do
		which "${cmd}" >/dev/null || \
			errx "cannot execute '${cmd}'"
	done

	local -r vulsenv="/etc/profile.d/vuls-env.sh"
	echo "${__progname}: creating '${vulsenv}'"
	touch "${vulsenv}"
	chmod 755 "${vulsenv}"

	local -r vulspath="/usr/local/vuls"
	echo 'export GO=/usr/share/gocode' > "${vulsenv}"
	echo 'export GOROOT=/usr/share/gocode/go' >> "${vulsenv}"
	echo "export VULSPATH=${vulspath}" >> "${vulsenv}"
	echo 'export GOPATH=${VULSPATH}' >> "${vulsenv}"
	echo 'export PATH=${PATH}:${GOROOT}:${GOROOT}/bin:${GO}/bin:${VULSPATH}:${VULSPATH}/bin:${VULSPATH}/src:${VULSPATH}/src/bin' >> "${vulsenv}"

	echo "${__progname}: sourcing '${vulsenv}'"
	. "${vulsenv}" || \
		errx "cannot open '${vuls}'"

	if [ ! -d "${vulspath}" ]; then
		echo "${__progname}: creating '${vulspath}'"
		mkdir "${vulspath}"
	fi
	cd "${vulspath}"

	local -r vulslog="/var/log/vuls"
	if [ ! -d "${vulslog}" ]; then
		echo "${__progname}: creating '${vulslog}'"
		mkdir "${vulslog}"
	fi
	chmod 700 "${vulslog}"

	# deploy go-cve-dictionary

	local -r gocvedict="go-cve-dictionary"
	local -r gocvedictrepo="github.com/kotakanbe"
	local -r gocvedicturl="https://${gocvedictrepo}/${gocvedict}"
	echo "${__progname}: git clone '${gocvedict}'"
	mkdir -p "${vulspath}/src/${gocvedictrepo}"
	cd "${vulspath}/src/${gocvedictrepo}"

	git clone --no-progress "${gocvedicturl}" || \
		errx "git clone '${gocvedicturl}' failed"

	cd "${gocvedict}"
	make install 2>/dev/null || \
		errx "${gocvedict}: make install failed"

	# deploy goval-dictionary

	local -r govaldict="goval-dictionary"
	local -r govaldictrepo="github.com/kotakanbe"
	local -r govaldicturl="https://${govaldictrepo}/${govaldict}"
	echo "${__progname}: git clone '${govaldict}'"
	mkdir -p "${vulspath}/src/${govaldictrepo}"
	cd "${vulspath}/src/${govaldictrepo}"

	git clone --no-progress "${govaldicturl}" || \
		errx "git clone '${govaldicturl}' failed"

	cd "${govaldict}"
	make install 2>/dev/null || \
		errx "${govaldict}: make install failed"

	local -r updatecveoval="/usr/local/bin/update-cve-oval.sh"
	"${updatecveoval}" || \
		errx "'${updatecveoval}' failed"

	# deploy vuls

	local -r vuls="vuls"
	local -r vulsrepo="github.com/future-architect"
	local -r vulsurl="https://${vulsrepo}/${vuls}"
	echo "${__progname}: git clone '${vuls}'"
	mkdir -p "${vulspath}/src/${vulsrepo}"
	cd "${vulspath}/src/${vulsrepo}"

	git clone --no-progress "${vulsurl}" || \
		errx "git clone '${vulsurl}' failed"

	cd "${vuls}"
	make install 2>/dev/null || \
		errx "${vuls}: make install failed"

	rm -rf "${vulspath}/src"

	echo
	echo "${__progname}: Vuls installed"

	return 0
}

main

exit $?
