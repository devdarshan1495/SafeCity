# ── SafeCity — Custom Jenkins Image ──────────────────────────────
FROM jenkins/jenkins:lts

# Skip initial setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx512m"

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Install Docker CLI and kubectl inside Jenkins
USER root
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && curl -fsSL https://get.docker.com | sh \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl \
    && apt-get clean

USER jenkins
