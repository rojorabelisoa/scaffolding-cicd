#!/usr/bin/env bash
# Idempotent SonarQube bootstrap: replaces the default admin/admin password with
# the one stored in secrets/sonarqube_admin_password. Safe to run repeatedly.
# Secrets are passed to curl through a 0600 temp config file, never via argv or logs.
set -euo pipefail
cd "$(dirname "$0")/.."

SONAR_URL="http://127.0.0.1:${SONAR_PORT:-9000}"
SECRET_FILE="secrets/sonarqube_admin_password"
[[ -s "$SECRET_FILE" ]] || { echo "missing $SECRET_FILE" >&2; exit 1; }
NEW_PW="$(<"$SECRET_FILE")"

umask 077
CFG="$(mktemp)"
trap 'rm -f "$CFG"' EXIT

# curl config quoting: escape backslashes and double quotes.
q() { local s="${1//\\/\\\\}"; printf '"%s"' "${s//\"/\\\"}"; }

for _ in $(seq 1 60); do
  curl -fsS "$SONAR_URL/api/system/status" 2>/dev/null | grep -q '"status":"UP"' && break
  sleep 5
done
curl -fsS "$SONAR_URL/api/system/status" | grep -q '"status":"UP"' || { echo "SonarQube not UP" >&2; exit 1; }

valid() {  # $1 = password
  printf 'user = %s\n' "$(q "admin:$1")" >"$CFG"
  curl -fsS -K "$CFG" "$SONAR_URL/api/authentication/validate" | grep -q '"valid":true'
}

if valid "$NEW_PW"; then
  echo "admin password already set from $SECRET_FILE (no change)"
elif valid "admin"; then
  {
    printf 'user = %s\n' "$(q "admin:admin")"
    printf 'data-urlencode = %s\n' "$(q "login=admin")"
    printf 'data-urlencode = %s\n' "$(q "previousPassword=admin")"
    printf 'data-urlencode = %s\n' "$(q "password=$NEW_PW")"
  } >"$CFG"
  curl -fsS -o /dev/null -K "$CFG" -X POST "$SONAR_URL/api/users/change_password"
  valid "$NEW_PW" && echo "admin password changed from default to $SECRET_FILE"
else
  echo "admin login fails with both default and stored password; manual action required" >&2
  exit 1
fi

# admin_api METHOD PATH [key=value ...]: authenticated call, form values passed through the config file.
admin_api() {
  local method="$1" path="$2"; shift 2
  {
    printf 'user = %s\n' "$(q "admin:$NEW_PW")"
    for kv in "$@"; do printf 'data-urlencode = %s\n' "$(q "$kv")"; done
  } >"$CFG"
  if [[ "$method" == GET ]]; then
    curl -fsS -G -K "$CFG" "$SONAR_URL$path"
  else
    curl -fsS -K "$CFG" -X "$method" "$SONAR_URL$path"
  fi
}

# --- Analysis token used by Jenkins (secrets/sonarqube_jenkins_token, mounted into the controller).
TOKEN_FILE="secrets/sonarqube_jenkins_token"
token_valid() {
  [[ -s "$TOKEN_FILE" ]] || return 1
  printf 'user = %s\n' "$(q "$(<"$TOKEN_FILE"):")" >"$CFG"
  curl -fsS -K "$CFG" "$SONAR_URL/api/authentication/validate" | grep -q '"valid":true'
}
if token_valid; then
  echo "jenkins analysis token valid (no change)"
else
  admin_api POST /api/user_tokens/revoke "login=admin" "name=jenkins" >/dev/null 2>&1 || true
  admin_api POST /api/user_tokens/generate "name=jenkins" "type=GLOBAL_ANALYSIS_TOKEN" \
    | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["token"])' >"$TOKEN_FILE.tmp"
  mv "$TOKEN_FILE.tmp" "$TOKEN_FILE"; chmod 644 "$TOKEN_FILE"
  token_valid && echo "jenkins analysis token generated into $TOKEN_FILE (restart jenkins to load it)"
fi

# No SonarQube -> Jenkins webhook: SonarQube rejects private (site-local) webhook targets as SSRF
# protection, and we keep that protection on. The scanner waits for the quality gate instead
# (sonar.qualitygate.wait=true in the Jenkinsfile).
