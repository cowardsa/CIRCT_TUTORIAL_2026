FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    wget \
    cmake \
    ninja-build \
    build-essential \
    python3 \
    z3 \
    libz3-dev \
    libtinfo6 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt && \
    wget -qO /tmp/circt-full-shared-linux-x64.tar.gz \
        https://github.com/llvm/circt/releases/download/firtool-1.147.0/circt-full-shared-linux-x64.tar.gz && \
    tar -xzf /tmp/circt-full-shared-linux-x64.tar.gz -C /opt && \
    mv /opt/firtool-1.147.0 /opt/circt && \
    rm -f /tmp/circt-full-shared-linux-x64.tar.gz

ENV PATH="/opt/circt/bin:${PATH}"

WORKDIR /workspace

COPY rtl /workspace/rtl