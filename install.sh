#!/bin/bash
# CloudStation Mesh — join a Linux machine to the mesh (SPEC-v8 §2).
#
#   curl -fsSL https://raw.githubusercontent.com/thecloudstation/connect-releases/main/install.sh \
#     | sudo bash -s -- --code CSM-XXXXX-XXXXX
#
# Published by make-app.sh --release, which stamps the @PIN@ placeholders:
# the script never floats — every binary it fetches is pinned by version and
# sha256 decided at release time. The code is single-use and 10-minute; the
# script never sees user credentials (SPEC-v8 §0.6).
set -euo pipefail

AGENT_TAG="v1.4.0"
AGENT_SHA_AMD64="bbbb23cc76f51ecb20021dbad7f69d1405f49036e95738c38edae8530fb77946"
AGENT_SHA_ARM64="6b4adac12cd0ccce9f31114412af4dbbecfda1f74d16408e1e6150b45c3eac7a"
NEBULA_VERSION="1.10.3"
NEBULA_SHA_AMD64="99ac335caeb69d02a6b6b00a3d4b5d0a36ec3971df480a1cc50e6db378342955"
NEBULA_SHA_ARM64="69b2764b0c27b04e4f3fb47764cf330555beb5a49e62e045ed5f208a14341343"

SERVER="https://mesh.cloud-station.io"
CODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --code)   CODE="${2:?--code needs a value}"; shift 2 ;;
    --server) SERVER="${2:?--server needs a value}"; shift 2 ;;
    --name)   shift 2 ;; # informational; the name lives on the host row
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "FAILED: $1" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "run as root:  curl -fsSL .../install.sh | sudo bash -s -- --code ..."
[ -n "$CODE" ] || fail "--code CSM-... is required (mint one in CloudStation Connect > Add a device)"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required (non-systemd distros are unsupported)"
[ -d /run/systemd/system ] || fail "systemd is not the running init on this machine"

case "$(uname -m)" in
  x86_64)  ARCH=amd64; AGENT_SHA="$AGENT_SHA_AMD64"; NEBULA_SHA="$NEBULA_SHA_AMD64" ;;
  aarch64) ARCH=arm64; AGENT_SHA="$AGENT_SHA_ARM64"; NEBULA_SHA="$NEBULA_SHA_ARM64" ;;
  *) fail "unsupported architecture $(uname -m) (supported: x86_64, aarch64)" ;;
esac

DIR=/var/lib/csmesh
# Same probe as the macOS helper (SPEC-v7 §4): the credential file IS the
# enrolled state. One agent per dir, ever.
[ ! -f "$DIR/credentials.json" ] || fail "this machine is already enrolled — to start over: systemctl disable --now csmesh-agent; rm -rf $DIR /etc/systemd/system/csmesh-agent.service"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "-> downloading csmesh-agent ($AGENT_TAG, linux-$ARCH)"
curl -fsSL -o "$TMP/csmesh-agent" \
  "https://github.com/thecloudstation/connect-releases/releases/download/$AGENT_TAG/csmesh-agent-linux-$ARCH"
echo "$AGENT_SHA  $TMP/csmesh-agent" | sha256sum -c - >/dev/null || fail "csmesh-agent checksum mismatch"

echo "-> downloading nebula v$NEBULA_VERSION"
curl -fsSL -o "$TMP/nebula.tar.gz" \
  "https://github.com/slackhq/nebula/releases/download/v$NEBULA_VERSION/nebula-linux-$ARCH.tar.gz"
echo "$NEBULA_SHA  $TMP/nebula.tar.gz" | sha256sum -c - >/dev/null || fail "nebula checksum mismatch"
tar -C "$TMP" -xzf "$TMP/nebula.tar.gz" nebula

install -m 0755 "$TMP/csmesh-agent" /usr/local/bin/csmesh-agent
install -m 0755 "$TMP/nebula" /usr/local/bin/csmesh-nebula
mkdir -p "$DIR" && chmod 0700 "$DIR"

echo "-> joining the network"
/usr/local/bin/csmesh-agent enroll -server "$SERVER" -code "$CODE" -dir "$DIR"

cat > /etc/systemd/system/csmesh-agent.service <<'UNIT'
[Unit]
Description=CloudStation Mesh agent (supervises nebula, keeps config current)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/csmesh-agent run -dir /var/lib/csmesh -nebula /usr/local/bin/csmesh-nebula
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now csmesh-agent.service

echo "-> waiting for the tunnel"
for _ in $(seq 1 30); do
  if [ -f "$DIR/state.json" ] && grep -q '"nebula_running": true' "$DIR/state.json"; then
    echo "OK: connected — this machine is on the mesh"
    exit 0
  fi
  sleep 1
done
echo "FAILED: enrolled, but the tunnel did not come up within 30s" >&2
echo "  check:  systemctl status csmesh-agent   and   journalctl -u csmesh-agent -n 50" >&2
exit 1
