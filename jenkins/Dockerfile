# Custom Jenkins image for DevSecOps Shield.
# Official Jenkins LTS + every CLI tool the pipeline needs, at pinned versions.
# Each downloaded binary is checked against a SHA-256 checksum, so a tampered
# or corrupted download makes the image build fail instead of being installed.

# Stage 1: borrow the Docker CLI + buildx plugin from Docker's official image.
FROM docker:29.9.3-cli AS dockercli

# Stage 2: the actual Jenkins image.
FROM jenkins/jenkins:2.580.2-lts-jdk21

ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG TRIVY_VERSION=0.76.1
ARG TRIVY_SHA256=c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0
ARG AWSCLI_VERSION=2.39.7
ARG AWSCLI_SHA256=707a900fde102f486d92e79f979493c747f475b9e2b94f2a42687d5d95129fb7
ARG ANSIBLE_CORE_VERSION=2.21.6
ARG BOTO3_VERSION=1.43.127
ARG AMAZON_AWS_COLLECTION_VERSION=11.5.1

USER root

# Python (for pytest and Ansible), jq (reads JSON from the AWS CLI),
# unzip (AWS CLI installer), ssh client (Ansible connects to EC2 over SSH).
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv python3-pip jq unzip curl ca-certificates openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI: talks to Docker Desktop through the mounted /var/run/docker.sock.
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

# Gitleaks: Security Gate 1 (secret scanning).
RUN curl -fsSLo /tmp/gitleaks.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
 && echo "${GITLEAKS_SHA256}  /tmp/gitleaks.tgz" | sha256sum -c - \
 && tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks \
 && rm /tmp/gitleaks.tgz

# Trivy: Security Gate 2 (container vulnerability scanning).
RUN curl -fsSLo /tmp/trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
 && echo "${TRIVY_SHA256}  /tmp/trivy.tgz" | sha256sum -c - \
 && tar -xzf /tmp/trivy.tgz -C /usr/local/bin trivy \
 && rm /tmp/trivy.tgz

# AWS CLI v2: ECR login, SSM parameters, ALB listener switching.
RUN curl -fsSLo /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" \
 && echo "${AWSCLI_SHA256}  /tmp/awscliv2.zip" | sha256sum -c - \
 && unzip -q /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install \
 && rm -rf /tmp/aws /tmp/awscliv2.zip

# Ansible + boto3 (needed by the aws_ec2 dynamic inventory) in their own
# virtual environment, plus the amazon.aws collection.
RUN python3 -m venv /opt/ansible \
 && /opt/ansible/bin/pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}" "boto3==${BOTO3_VERSION}" \
 && /opt/ansible/bin/ansible-galaxy collection install "amazon.aws:==${AMAZON_AWS_COLLECTION_VERSION}" -p /usr/share/ansible/collections
ENV PATH="/opt/ansible/bin:${PATH}"

# Jenkins start-up script: use one executor (one build at a time).
COPY --chown=jenkins:jenkins init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/
# Pre-defined jobs ("jobs as code"). The .override suffix makes Jenkins copy
# them into JENKINS_HOME on EVERY start, so the files in Git stay the source of truth.
COPY --chown=jenkins:jenkins jobs/splitease/config.xml /usr/share/jenkins/ref/jobs/splitease/config.xml.override
COPY --chown=jenkins:jenkins jobs/splitease-rollback/config.xml /usr/share/jenkins/ref/jobs/splitease-rollback/config.xml.override

USER jenkins

# Jenkins plugins the pipeline needs, installed at build time (reproducible).
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
