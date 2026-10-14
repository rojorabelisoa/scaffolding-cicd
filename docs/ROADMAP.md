# Implementation plan
1. Scaffold and validate Compose / docs (done).
2. Boot Jenkins, SonarQube, DBs, Registry; set up Jenkins Configuration as Code and secured admin bootstrap (done).
3. Add isolated Jenkins build agent, Maven/JUnit/Sonar scans and OCI image build (done).
4. Create Java 21 Spring Boot demo app and GitHub PR pipeline with checks (done, Phase 3).
5. Create Kind, configure containerd to access Registry, install Argo CD, implement GitOps DEV.
6. Implement FastAPI agent persistence, GitHub App auth/webhook verification, event idempotency.
7. Add LangGraph diagnosis agent, typed tool APIs, policy engine, structured audit.
8. Add safe branch-only patches, bounded retries and approvals.
9. Implement GitOps promotions, health verification and reversible rollback.
10. Test failure scenarios, observability and security hardening.
