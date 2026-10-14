#!/usr/bin/env bash
# Loads (idempotently) the buildkitd-rootless AppArmor profile into the Colima VM.
# Run after "colima start" if the profile is not persisted through Colima provisioning.
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE=infrastructure/buildkit/apparmor-buildkitd-rootless
colima ssh -- sudo tee /etc/apparmor.d/buildkitd-rootless >/dev/null <"$PROFILE"
colima ssh -- sudo apparmor_parser -r -W /etc/apparmor.d/buildkitd-rootless
colima ssh -- sudo aa-status --json | grep -q '"buildkitd-rootless"' && echo "AppArmor profile buildkitd-rootless loaded"
