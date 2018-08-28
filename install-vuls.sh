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

	local -r gocvedict="go-cve-dictionary"
	local -r gocvedicturl="https://github.com/kotakanbe/${gocvedict}"
	echo "${__progname}: git clone '${gocvedict}'"
	mkdir -p "${vulspath}/src"
	cd "${vulspath}/src"

	git clone --no-progress "${gocvedicturl}" || \
		errx "git clone '${gocvedicturl}' failed"

	cd "${gocvedict}"
	make install 2>/dev/null || \
		errx "make install failed"

	local -r govaldict="goval-dictionary"
	local -r govaldicturl="https://github.com/kotakanbe/${govaldict}"
	echo "${__progname}: git clone '${govaldict}'"
	mkdir -p "${vulspath}/src"
	cd "${vulspath}/src"

	git clone --no-progress "${govaldicturl}" || \
		errx "git clone '${govaldicturl}' failed"

	cd "${govaldict}"
	make install 2>/dev/null || \
		errx "make install failed"

	local -r updatecveoval="/usr/local/bin/update-cve-oval.sh"
	"${updatecveoval}" || \
		errx "'${updatecveoval}' failed"

	local -r vulsurl="https://github.com/future-architect/vuls"
	cd "${vulspath}/src"

	echo "${__progname}: git clone '${vulsurl}'"
	git clone --no-progress "${vulsurl}" || \
		errx "git clone '${vulsurl}' failed"

	cd vuls

	make >/dev/null || \
		errx "make failed"

	make install >/dev/null || \
		errx "make install failed"

	rm -rf "${vulspath}/src"

	echo
	echo "${__progname}: Vuls installed"

	return 0
}

main

exit $?
