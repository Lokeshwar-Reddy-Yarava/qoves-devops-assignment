FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    bash \
    openssl \
    tar \
    gzip \
    unzip \
    python3 \
    python3-pip \
    conntrack \
    iptables \
    iproute2 \
    dnsutils \
    netcat-openbsd \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
      > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)" \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# minikube
RUN curl -fsSL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o /usr/local/bin/minikube \
    && chmod +x /usr/local/bin/minikube

# helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# argocd CLI
RUN ARGOCD_VERSION="$(curl -L -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r .tag_name)" \
    && curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" -o /usr/local/bin/argocd \
    && chmod +x /usr/local/bin/argocd

# kubeseal (for Sealed Secrets later)
RUN KUBESEAL_VERSION="$(curl -L -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | jq -r .tag_name | sed 's/^v//')" \
    && curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
      | tar -xz -C /usr/local/bin kubeseal \
    && chmod +x /usr/local/bin/kubeseal

WORKDIR /workspace

# Reuse the default ubuntu user (UID 1000) and grant access to host docker.sock (GID 986)
RUN groupadd -g 986 docker || true \
    && usermod -aG docker ubuntu \
    && mkdir -p /home/ubuntu/.kube /home/ubuntu/.minikube \
    && chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.minikube

USER ubuntu
ENV HOME=/home/ubuntu
CMD ["sleep", "infinity"]
