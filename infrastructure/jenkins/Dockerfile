FROM jenkins/jenkins:2.580.1-lts-jdk21
USER jenkins
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -XX:MaxRAMPercentage=60" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc/ /usr/share/jenkins/casc/
