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
