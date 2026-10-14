# Agentic DevOps — local POC scaffold

## Prerequisites
Docker Engine with Compose v2. Validated runtime on macOS (Apple Silicon): Colima 4 CPU / 8 GiB / 100 GiB (`colima start --cpu 4 --memory 8 --disk 100 --vm-type vz --mount-type virtiofs`). 8 GiB fits Jenkins + SonarQube + both Postgres; Kind + Argo CD will need ~10 GiB (`colima stop && colima start --memory 10`, volumes are kept). Ollama in a container on macOS has no GPU access; prefer a native Ollama for local LLM tests. For Kind: kind and kubectl installed. GitHub remains cloud-hosted.

## Start
```bash
cp .env.example .env              # replace every CHANGE_ME (openssl rand -hex 24); set GITHUB_APP_ID / GITHUB_OWNER
./scripts/init-secrets.sh         # idempotent: admin passwords, agent SSH keys, BuildKit mTLS CA/certs in secrets/
# GitHub App private key (PKCS#8) -> secrets/github_app_key.pem (see "GitHub integration")
./scripts/colima-apparmor.sh      # macOS/Colima only: AppArmor profile required by rootless BuildKit
docker compose config --quiet
docker compose up -d --build
./scripts/bootstrap-sonarqube.sh  # idempotent: admin password + Jenkins analysis token
docker compose restart jenkins    # only if the bootstrap just generated a new token
./scripts/verify.sh               # non-destructive checks, prints no secrets
```
`.env`, `.env.bak` and `secrets/` are git-ignored. PostgreSQL only reads `POSTGRES_PASSWORD` when a volume is first initialized:
changing it later requires `ALTER USER` inside the database, not just editing `.env`.
Never use `docker compose down -v` unless you intend to delete all data.

Local endpoints (all bound to 127.0.0.1): Jenkins http://localhost:8080, SonarQube http://localhost:9000, Registry http://localhost:5001/v2/.
PostgreSQL is private to the Compose network; no host DB ports.

Optional components:
```bash
docker compose --profile agent up -d --build
docker compose --profile observability up -d
docker compose --profile local-llm up -d
```

The AI agent currently implements **only** `GET /health`; there are no GitHub/Jenkins/LLM integrations yet. The Prometheus config monitors only Prometheus itself.

## Kubernetes
```bash
bash scripts/create-kind.sh
```
Argo CD installation and Kind-to-registry configuration are **Phase 4 tasks**, not implemented yet. Kind node `localhost` is not host `localhost`: do not assume images from host port 5001 are pullable in Kind without explicit registry/containerd setup. GitHub webhook delivery to a local host requires a secured tunnel or a public ingress; avoid exposing Jenkins directly.

## Jenkins configuration (JCasC)
Jenkins is configured from `infrastructure/jenkins/casc/jenkins.yaml`, baked into the image and re-applied at every start
(setup wizard disabled). Admin user `admin`, password from the Compose secret `jenkins_admin_password` (file in `/run/secrets`,
not an environment variable). Anonymous access denied, signup disabled, 0 executors on the controller, inbound agent port disabled.
To change the config: edit the YAML, then `docker compose up -d --build jenkins`.

Plugins: `plugins.requested.txt` lists what we ask for; `plugins.txt` is the generated lock (86 plugins). To add or upgrade:
edit `plugins.requested.txt`, run `./scripts/jenkins-plugins-lock.sh`, review the diff, then `docker compose up -d --build jenkins`.

JCasC also declares: the `build-agent-1` node, credentials (agent SSH key, SonarQube token, GitHub App) read from
`/run/secrets` files, the `sonarqube` server, and the `demo-app` multibranch job (Job DSL).

## Jenkins build isolation
```
jenkins (controller, 0 executors) --SSH, pinned ed25519 host key--> jenkins-agent (JDK 21, mvnw, buildctl; no Docker socket)
jenkins-agent --mTLS (private CA, client cert)--> buildkitd (rootless, uid 1000, not privileged) --HTTP--> registry:5000
```
- Networks: `devops` (controller, agent, SonarQube, DBs, registry) and `build` (agent, buildkitd, registry only).
- The agent's secrets are mounted as files: its entrypoint never puts secrets in env (`setup-sshd` copies env into `/etc/environment`).
- BuildKit rootless needs user namespaces. Ubuntu 24.04 (Colima VM) restricts them with AppArmor; instead of disabling the
  restriction globally, `scripts/colima-apparmor.sh` loads a dedicated profile (`infrastructure/buildkit/apparmor-buildkitd-rootless`)
  used only by the buildkitd container. Re-run the script if the Colima VM is recreated.
- Never mount `/var/run/docker.sock` into the controller or agents.

## GitHub integration
- Demo app repository: `rojorabelisoa/agentic-devops-demo-app` (private). Sources are also kept in `demo-app/`.
- Jenkins authenticates as a GitHub App (`GITHUB_APP_ID` in `.env`, key in `secrets/github_app_key.pem`, PKCS#8:
  `openssl pkcs8 -topk8 -nocrypt -in downloaded.pem -out secrets/github_app_key.pem`).
  Required repository permissions: Checks RW, Commit statuses RW, Contents R, Pull requests R. Install it on the demo repo only.
- Events: Jenkins **polls** GitHub every 2 minutes (no inbound exposure). Signed webhooks arrive with the AI agent (Phase 5).
- Statuses published: `continuous-integration/jenkins/branch` (main) and `continuous-integration/jenkins/pr-merge` (PRs).
- Fork pull requests are not discovered.

## Demo pipeline (demo-app/Jenkinsfile)
1. `./mvnw -B verify` (Maven 3.9.16, distribution SHA-256 verified by the wrapper), JUnit report, JaCoCo coverage.
2. SonarQube analysis with `sonar.qualitygate.wait=true`: the build fails if the quality gate fails. No SonarQube->Jenkins
   webhook is used, because SonarQube rightly refuses webhooks to private addresses (SSRF protection kept on).
3. Image build through BuildKit: pushed as `registry:5000/demo-app:<git sha>` from `main` only; PRs build without pushing.
   The resulting `repo@sha256:...` reference is archived as `image-ref.txt` for GitOps (Phase 4).

## SonarQube prerequisites
On Linux hosts, SonarQube may require `vm.max_map_count` tuning (consult your image's official documentation). SonarQube needs ~1-2 min and ~1.7 GiB RAM to initialize. Telemetry is disabled. The default admin/admin password is replaced by `scripts/bootstrap-sonarqube.sh`.

## Security notes
Local POC only. Registry is HTTP without authentication, bound to loopback; do not expose publicly. Rotate default/placeholder passwords. Pin container images by digest before production usage. Treat logs, PR content and model output as untrusted.

## Pinned versions
All image tags are pinned to explicit versions (verified to exist with linux/arm64 manifests on 2026-10-13):
Jenkins `2.580.1-lts-jdk21`, SonarQube `26.10.0.133078-community` (supports PostgreSQL 15–18), PostgreSQL `16.15-alpine`,
Registry `2.8.3`, Prometheus `v3.2.1`, Grafana `11.5.2`, Ollama `0.40.3`, Python `3.12.15-slim`,
BuildKit `v0.34.0-rootless`, Jenkins SSH agent `9.1.0-jdk21`, demo runtime `eclipse-temurin:21.0.12.1_1-jre-noble` (by digest),
Spring Boot `4.1.1`, Maven `3.9.16`.
Do not change the PostgreSQL major version on existing volumes without a dump/restore. Digest pinning is planned before any deployment.
Jenkins plugins are fully pinned (see "Jenkins configuration").

## Validation status
Phase 1 (2026-10-13), static validation:
Executed on macOS 26.3.1 arm64, Docker Engine 29.5.2 (Colima), Compose 5.6.0:
- `docker compose config --quiet` without `.env`: fails as intended (required secrets missing).
- `docker compose --env-file .env.example --profile '*' config --quiet`: OK (9 services).
- `yamllint` on `compose.yaml` and `infrastructure/`: OK. `bash -n scripts/*.sh`: OK.
- `docker compose build ai-agent` + standalone run: `/health` OK, runs as uid 10001, Docker healthcheck `healthy`.
- `docker compose build jenkins`: OK, plugins resolved, runs as uid 1000.

Phase 2 (2026-10-13), core stack `docker compose up -d` (no optional profiles):
- All 5 services reach `healthy` (Docker healthchecks): jenkins, sonarqube, sonar-db, agent-db, registry.
- `scripts/verify.sh`: 9/9 OK (Jenkins anonymous 403, admin auth, JCasC 0 executors; SonarQube UP, admin/admin rejected,
  admin secret valid; registry /v2/; both pg_isready). Negative tests: wrong passwords give Jenkins 401 / SonarQube `valid:false`.
- `scripts/bootstrap-sonarqube.sh` run 3 times: changes the password once, then reports "no change".
- Registry: push `localhost:5001/smoke/hello:phase2`, pull back by digest OK.
- `docker compose down` (without `-v`) + `up -d`: volumes kept, all healthy in ~30 s, password and registry content persisted.
- Secret scan: 0 secret values found in `docker compose logs` or in `docker inspect` of Jenkins.
- Memory at idle: SonarQube 1.65 GiB, Jenkins 366 MiB, Postgres 55 + 18 MiB, Registry 7 MiB (~2.1 GiB of the 8 GiB VM).

Phase 3 (2026-10-13), CI pipeline:
- BuildKit rootless (uid 1000, not privileged, AppArmor profile `buildkitd-rootless`): build + push from the agent over mTLS OK;
  connections without client certificate or without TLS rejected.
- Jenkins agent: SSH connection with pinned host key ("SSH host key matched the key required"), online with labels `build linux`.
- `demo-app` multibranch job created by JCasC/Job DSL, repository indexed through the GitHub App.
- `main` #1: SUCCESS in 61 s - 5/5 tests, quality gate PASSED (coverage 86.7 %, 0 bugs/vulnerabilities/code smells),
  image pushed `registry:5000/demo-app@sha256:4588880516c08f0c406adfaf3c2d4f6240bf8385b04baca47a002979ce9ebe50`,
  GitHub status `continuous-integration/jenkins/branch = success`.
- Image pulled back by digest and run: readiness UP, `/api/greeting` OK, uid 10001, arm64.
- PR #1 (discovered by polling, merged with main): SUCCESS - 6/6 tests, gate PASSED, image built **not** pushed,
  GitHub status `continuous-integration/jenkins/pr-merge = success`.
- `scripts/verify.sh`: 14/14 OK. Secret scan: 0 values in compose logs or in `docker inspect` (jenkins, agent, buildkitd).
- Memory: ~2.7 GiB of 8 GiB at idle (SonarQube 1.97 GiB, Jenkins 432 MiB, agent 168 MiB, buildkitd 71 MiB).
- Branch protection on `main`: **refused by GitHub** (private repo on a free plan, HTTP 403). Not in place.

Not tested: optional profiles (agent with DB, observability, local-llm), failing quality gate / failing tests scenario, Kind, Argo CD.
