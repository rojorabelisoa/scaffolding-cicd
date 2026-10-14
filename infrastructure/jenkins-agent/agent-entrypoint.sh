#!/bin/bash
# Installs the pinned sshd host key and the controller's public key from mounted files,
# then hands over to the upstream setup-sshd. Secrets are never passed via environment
# variables because setup-sshd copies the environment into /etc/environment.
set -euo pipefail
install -m 600 -o root -g root /run/secrets/jenkins_agent_host_key /etc/ssh/ssh_host_ed25519_key
install -m 644 -o root -g root /run/secrets/jenkins_agent_host_key.pub /etc/ssh/ssh_host_ed25519_key.pub
JENKINS_AGENT_SSH_PUBKEY="$(cat /run/secrets/jenkins_agent_ssh_key.pub)"
export JENKINS_AGENT_SSH_PUBKEY
exec setup-sshd "$@"
