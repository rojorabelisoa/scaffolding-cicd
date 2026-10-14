#!/usr/bin/env bash
# Idempotent creation of local runtime secrets in secrets/ (git-ignored).
# Existing files are never overwritten. Prints file names only, never values.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p secrets secrets/buildkit
chmod 700 secrets

created() { echo "created $1"; }
rand_file() {  # $1 = name, $2 = generator command
  [[ -s "secrets/$1" ]] && return 0
  eval "$2" | tr -d '\n' >"secrets/$1"; created "secrets/$1"
}

rand_file jenkins_admin_password   'openssl rand -hex 24'
# SonarQube password policy: >= 12 chars with upper, lower, digit and special character.
rand_file sonarqube_admin_password 'printf "%sAa9#" "$(openssl rand -hex 16)"'
# Filled by scripts/bootstrap-sonarqube.sh; must exist for Compose to start.
[[ -e secrets/sonarqube_jenkins_token ]] || { : >secrets/sonarqube_jenkins_token; created "secrets/sonarqube_jenkins_token (empty)"; }

# SSH: controller -> build agent (client key) and the agent's sshd host key (pinned by the controller).
for k in jenkins_agent_ssh_key jenkins_agent_host_key; do
  if [[ ! -s "secrets/$k" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "$k" -f "secrets/$k"
    created "secrets/$k(.pub)"
  fi
  # Single-line public key without trailing newline (consumed by JCasC readFile).
  awk '{printf "%s %s", $1, $2}' "secrets/$k.pub" >"secrets/$k.pub.tmp" && mv "secrets/$k.pub.tmp" "secrets/$k.pub"
done

# BuildKit mTLS: private CA, server cert for "buildkitd", client cert for the build agent.
B=secrets/buildkit
if [[ ! -s $B/ca.pem ]]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 825 \
    -subj "/CN=agentic-devops-buildkit-ca" -keyout $B/ca-key.pem -out $B/ca.pem 2>/dev/null
  created "$B/ca.pem"
fi
issue() {  # $1 = name, $2 = CN, $3 = extensions
  [[ -s $B/$1.pem ]] && return 0
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=$2" \
    -keyout $B/$1-key.pem -out $B/$1.csr 2>/dev/null
  openssl x509 -req -in $B/$1.csr -CA $B/ca.pem -CAkey $B/ca-key.pem -CAcreateserial \
    -days 825 -out $B/$1.pem -extfile <(printf '%s' "$3") 2>/dev/null
  rm -f $B/$1.csr
  created "$B/$1.pem"
}
issue server buildkitd "subjectAltName=DNS:buildkitd
extendedKeyUsage=serverAuth"
issue client jenkins-agent "extendedKeyUsage=clientAuth"

# Files are bind-mounted into containers running as non-root uids; the 0700 directory keeps them private on the host.
chmod 700 secrets secrets/buildkit
find secrets -type f ! -name 'ca-key.pem' -exec chmod 644 {} +
chmod 600 secrets/buildkit/ca-key.pem
echo "secrets ready"
