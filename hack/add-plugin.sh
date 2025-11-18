#!/bin/bash

set -euo pipefail

COREDNS_PATH=$1
PLUGIN_PATH=$2

cd "${COREDNS_PATH}"

# Replace "github.com/openshift/coredns-ocp-dnsnameresolver" in the go.mod file to use the local code.
go mod edit -replace github.com/openshift/coredns-ocp-dnsnameresolver="${PLUGIN_PATH}"

# Run go commands to fetch the code required for the plugin.
go get github.com/openshift/coredns-ocp-dnsnameresolver

SERVER_QUIC="${COREDNS_PATH}/core/dnsserver/server_quic.go"
DOQ_WRITER="${COREDNS_PATH}/core/dnsserver/quic.go"
INFORMER="${COREDNS_PATH}/plugin/kubernetes/object/informer.go"
PLUGIN_CFG="${COREDNS_PATH}/plugin.cfg"

SED_BIN=sed
if command -v gsed >/dev/null 2>&1; then
	SED_BIN=gsed
fi
if ${SED_BIN} --version >/dev/null 2>&1; then
	HAVE_GNU_SED=1
	SED_INPLACE=(-i)
else
	HAVE_GNU_SED=0
	SED_INPLACE=(-i '')
fi

sed_replace() {
	local expr="$1"
	local file="$2"
	[ -f "$file" ] || return 0
	${SED_BIN} "${SED_INPLACE[@]}" "$expr" "$file"
}

sed_insert_before() {
	local pattern="$1"
	local line="$2"
	local file="$3"
	[ -f "$file" ] || return 0
	if [ "$HAVE_GNU_SED" -eq 1 ]; then
		${SED_BIN} -i "/${pattern}/i ${line}" "$file"
	else
		${SED_BIN} -i '' "/${pattern}/i\\
${line}
" "$file"
	fi
}

update_plugin_cfg() {
	local cfg="$1"
	local target="ocp_dnsnameresolver:github.com/openshift/coredns-ocp-dnsnameresolver"
	[ -f "$cfg" ] || return 0
	if grep -Fq "ocp_dnsnameresolver:" "$cfg"; then
		sed_replace "s#^ocp_dnsnameresolver:.*#${target}#" "$cfg"
	else
		if grep -q '^cache:cache$' "$cfg"; then
			sed_insert_before '^cache:cache$' "$target" "$cfg"
		else
			echo "$target" >> "$cfg"
		fi
	fi
}

update_plugin_cfg "$PLUGIN_CFG"
sed_replace 's/func (s \*ServerQUIC) serveQUICConnection(conn quic.Connection)/func (s *ServerQUIC) serveQUICConnection(conn *quic.Conn)/' "$SERVER_QUIC"
sed_replace 's/func (s \*ServerQUIC) serveQUICStream(stream quic.Stream, conn quic.Connection)/func (s *ServerQUIC) serveQUICStream(stream *quic.Stream, conn *quic.Conn)/' "$SERVER_QUIC"
sed_replace 's/func (s \*ServerQUIC) closeQUICConn(conn quic.Connection/func (s *ServerQUIC) closeQUICConn(conn *quic.Conn/' "$SERVER_QUIC"
sed_replace 's/stream     quic.Stream/stream     *quic.Stream/' "$DOQ_WRITER"
sed_replace '/RetryOnError:     false,/d' "$INFORMER"

# Generate the files related to the plugin.
GOFLAGS=-mod=mod go generate
# Run go commands to fetch the code required by the generated code.
go get

# Run go mod tidy/vendor/verify to update the dependecies.
go mod tidy
go mod vendor
go mod verify
