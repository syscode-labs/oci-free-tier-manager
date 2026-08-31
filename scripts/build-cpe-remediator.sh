#!/usr/bin/env bash
set -euo pipefail

# A stale externally-exported GOROOT can pair a new Go compiler with an old
# standard library. Let the selected go binary determine its own toolchain.
unset GOROOT

mkdir -p artifacts

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -buildvcs=false \
  -trimpath \
  -ldflags='-s -w -buildid=' \
  -o artifacts/cpe-remediator \
  ./cmd/cpe-remediator

# OCI's object provider includes the source file mtime in a saved plan. Keep
# it stable because CI builds the artifact once for plan and again for apply.
touch -t 200001010000 artifacts/cpe-remediator
