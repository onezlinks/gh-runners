FROM ubuntu:24.04

ARG RUNNER_VERSION="2.331.0"
# Set automatically by `docker buildx`; defaults to amd64 for plain `docker build`
ARG TARGETARCH=amd64
ARG DEBIAN_FRONTEND=noninteractive

# Update and upgrade the system
RUN apt update -y && apt upgrade -y && rm -rf /var/lib/apt/lists/*

# Add a user named docker
RUN useradd -m docker

# Install necessary packages, GitHub CLI, and Docker CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    build-essential docker-buildx-plugin docker-ce-cli docker-compose-plugin gh git jq libffi-dev libssl-dev \
    python3 python3-dev python3-pip python3-venv ssh sudo \
    && rm -rf /var/lib/apt/lists/*

# Add docker user to docker group and allow GID fix at startup
RUN usermod -aG docker docker \
    && echo "docker ALL=(root) NOPASSWD: /usr/sbin/groupmod" >> /etc/sudoers

# Set up the actions runner for the target architecture
RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
    && case "${TARGETARCH}" in \
         amd64) RUNNER_ARCH=x64 ;; \
         arm64) RUNNER_ARCH=arm64 ;; \
         *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
    && tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz

# Change ownership to docker user and install dependencies
RUN chown -R docker /home/docker && /home/docker/actions-runner/bin/installdependencies.sh

# Copy the start script and make it executable
COPY --chmod=+x start.sh /start.sh

# Switch to docker user
USER docker

# Define the entrypoint
ENTRYPOINT ["/start.sh"]
