# Isolated Jenkins build agent: JDK 21 + git (base image) + buildctl client.
# No Docker daemon or socket: images are built by the remote rootless BuildKit daemon over mTLS.
FROM moby/buildkit:v0.34.0-rootless AS buildkit

FROM jenkins/ssh-agent:9.1.0-jdk21
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
COPY sshd-hardening.conf /etc/ssh/sshd_config.d/10-hardening.conf
COPY --chmod=755 agent-entrypoint.sh /usr/local/bin/agent-entrypoint
# unzip: the Maven wrapper verifies the SHA-256 of the .zip distribution, which needs unzip.
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*
# Pre-create volume mount points so named volumes inherit jenkins ownership.
RUN install -d -o jenkins -g jenkins /home/jenkins/.m2 /home/jenkins/agent
ENTRYPOINT ["agent-entrypoint"]
