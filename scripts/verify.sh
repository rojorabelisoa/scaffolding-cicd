#!/usr/bin/env bash
# Non-destructive checks of the core stack. Prints no secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a

fail=0
check() {  # $1 = label, rest = command
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "OK   $label"; else echo "FAIL $label"; fail=1; fi
}
auth_cfg() {  # $1 = user, $2 = secret file -> curl config file path on stdout
  local f; f="$(mktemp)"; printf 'user = "%s:%s"\n' "$1" "$(<"$2")" >"$f"; echo "$f"
}

docker compose config --quiet
docker compose ps --format 'table {{.Service}}\t{{.Status}}'

J="http://127.0.0.1:${JENKINS_PORT:-8080}"
S="http://127.0.0.1:${SONAR_PORT:-9000}"
R="http://127.0.0.1:${REGISTRY_PORT:-5001}"

umask 077
JCFG="$(auth_cfg admin secrets/jenkins_admin_password)"
SCFG="$(auth_cfg admin secrets/sonarqube_admin_password)"
trap 'rm -f "$JCFG" "$SCFG"' EXIT

check "jenkins: anonymous access denied" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' $J/api/json)\" = 403 ]"
check "jenkins: admin authenticated" bash -c "curl -fsS -K '$JCFG' $J/whoAmI/api/json | grep -q '\"authenticated\":true'"
check "jenkins: JCasC applied (0 controller executors)" bash -c "curl -fsS -K '$JCFG' '$J/computer/api/json?tree=computer%5BnumExecutors%5D' | grep -q '\"numExecutors\":0'"
check "jenkins: build-agent-1 online" bash -c "curl -fsS -K '$JCFG' '$J/computer/build-agent-1/api/json?tree=offline' | grep -q '\"offline\":false'"
check "jenkins: demo-app multibranch job exists" curl -fsS -K "$JCFG" "$J/job/demo-app/api/json?tree=name"
check "buildkitd: mTLS worker reachable from agent" docker compose exec -T -u jenkins jenkins-agent buildctl --addr tcp://buildkitd:1234 \
  --tlsservername buildkitd --tlscacert /run/secrets/buildkit/ca.pem --tlscert /run/secrets/buildkit/client.pem \
  --tlskey /run/secrets/buildkit/client-key.pem debug workers
check "buildkitd: connection without client cert rejected" bash -c "! docker compose exec -T -u jenkins jenkins-agent buildctl \
  --addr tcp://buildkitd:1234 --tlsservername buildkitd --tlscacert /run/secrets/buildkit/ca.pem debug workers"
check "buildkitd: not privileged" bash -c "[ \"\$(docker inspect -f '{{.HostConfig.Privileged}}' \$(docker compose ps -q buildkitd))\" = false ]"
check "sonarqube: status UP" bash -c "curl -fsS $S/api/system/status | grep -q '\"status\":\"UP\"'"
check "sonarqube: default admin/admin rejected" bash -c "! curl -fsS -u admin:admin $S/api/authentication/validate | grep -q '\"valid\":true'"
check "sonarqube: admin secret valid" bash -c "curl -fsS -K '$SCFG' $S/api/authentication/validate | grep -q '\"valid\":true'"
check "registry: /v2/ reachable" curl -fsS "$R/v2/"
check "sonar-db: pg_isready" docker compose exec -T sonar-db pg_isready -U sonar -d sonar
check "agent-db: pg_isready" docker compose exec -T agent-db pg_isready -U agent -d agentdb

if docker compose ps --services --status running | grep -qx ai-agent; then
  check "ai-agent: /health" curl -fsS "http://127.0.0.1:${AGENT_PORT:-8000}/health"
fi
exit "$fail"
