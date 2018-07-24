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
	echo 'export PATH=${PATH}:${GOROOT}:${GOROOT}/bin:${VULSPATH}:${VULSPATH}/bin:${VULSPATH}/src:${VULSPATH}/src/bin' >> "${vulsenv}"

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

	local -r gocvedict="github.com/kotakanbe/go-cve-dictionary"
	echo "${__progname}: go get '${gocvedict}'"
	go get "${gocvedict}" || \
		errx "go get '${gocvedict}' failed"

	for year in {2004..2018}; do
		echo "${__progname}: go-cve-dictionary fetchnvd -years '${year}'"
		go-cve-dictionary fetchnvd -years "${year}" || \
			errx "go-cve-dictionary fetchnvd -year '${year}' failed"
	done

	local -r govaldict="goval-dictionary"
	local -r govaldicturl="https://github.com/kotakanbe/${govaldict}"
	echo "${__progname}: git clone '${govaldict}'"
	mkdir -p "${vulspath}/src"
	cd "${vulspath}/src"

	git clone --no-progress "${govaldicturl}" || \
		errx "git clone '${govaldicturl}' failed"

	cd "${govaldict}"
	make install || \
		errx "make install failed"

	echo "${__progname}: goval-dictionary fetch-redhat 7"
	goval-dictionary fetch-redhat 7 || \
		errx "goval-dictionary fetch-redhat 7 failed"

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

	echo "${__progname}: vuls installed"

	return 0
}

main

exit $?
