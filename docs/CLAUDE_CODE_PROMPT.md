# Prompt for Claude Code

You are a Staff Platform Engineer and AI Agent Architect. Build an enterprise-minded POC for autonomous, policy-controlled delivery from GitHub Pull Request through Jenkins CI, SonarQube, OCI Registry, GitOps/Argo CD and Kubernetes Kind.

## Stack
- GitHub Cloud with GitHub App and verified webhooks.
- Jenkins LTS for deterministic CI; Maven/JUnit/SonarQube; isolated OCI build executor.
- SonarQube Community Build, PostgreSQL, local Docker Registry.
- Agent: Python 3.12+, FastAPI, LangGraph, Pydantic, SQLAlchemy/Alembic, PostgreSQL. TypeScript/NestJS/LangGraph.js is acceptable only if you justify and document the choice.
- Java 21 Spring Boot demonstration app.
- Kind, Helm/Kustomize, Argo CD, Prometheus/Grafana optional.

## Architecture
- Modular agent service: API/webhooks, deterministic workflow state machine, AI reasoning nodes, GitHub/Jenkins/Sonar/Argo adapters, authorization policy engine, persistence, audit and telemetry.
- GitHub PR opens validation workflow; after merge and policy gates, immutable digest may be promoted to DEV. Production requires human approval.
- LangGraph makes diagnoses and suggestions; deterministic orchestration and policies decide actions.
- No arbitrary shell execution from LLM. No cluster-admin or Docker host socket in Jenkins controller. No automatic bypass of branch protection. Untrusted logs and PRs must not become instructions.
- Webhook replay/idempotency, concurrency locks, retry limits (max 2), timeouts, durable state and cancellation.

## Execution phases
Phase 1: inspect existing files; run `docker compose config`; correct structural errors; report resource constraints and security issues. Do not destroy volumes.
Phase 2: start and verify Jenkins, SonarQube, Postgres and Registry; secure credentials; add Jenkins Configuration as Code. Capture actual outputs.
Phase 3: build Java 21 demo app, tests, Dockerfile, Jenkinsfile; configure GitHub PR status checks and isolated image build agent.
Phase 4: create Kind with verified registry connectivity; install Argo CD; configure DEV GitOps with digest-pinned images.
Phase 5: build agent API and database; verify GitHub signatures and GitHub App tokens; implement GitHub/Jenkins adapters with mocked tests.
Phase 6: implement LangGraph CI diagnosis and constrained branch-based patch proposals; policy gate, approval, bounded retry.
Phase 7: integrate GitOps promotions, K8s health evaluation and revert-by-Git rollback.
Phase 8: add observability, security tests, end-to-end demonstrations and runbooks.

## Rules
For each phase: list planned files, implement only that phase, run available checks, report exact tested/not-tested status, stop and ask for approval. Never invent successful tool runs. Preserve secrets outside git and prompts. Prefer pinned compatible versions; verify official compatibility before changing versions. Keep README and CLAUDE.md current.

Begin with Phase 1 only.
