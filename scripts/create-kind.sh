#!/usr/bin/env bash
set -euo pipefail
kind create cluster --config infrastructure/kind/kind-config.yaml
# Registry access from Kind nodes needs additional containerd registry configuration.
# See README; do not assume host localhost:5001 resolves inside nodes.
