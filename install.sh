#!/bin/bash

if [ "${EUID}" -ne 0 ]; then
	echo "need root"

	exit 1
fi

readonly dest="/usr/local/bin"
find . -name "*.sh" | grep -v "install" | while read bin; do
	echo "copying '$(basename "${bin}")' to '${dest}'"

	install -m 0755 -o root -g root "${bin}" "${dest}" || \
		exit 1
done

./install-vuls.sh || \
	exit 1
