# Ubuntu 24.04 with CRIU and Bun built from oven-sh/bun#45631 (the --aot PR).
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip iproute2 software-properties-common gpg-agent \
 && add-apt-repository -y ppa:criu/ppa && apt-get install -y --no-install-recommends criu && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH=/root/.bun/bin:$PATH
# bun-pr installs into a temporary directory when run through bunx, so keep a copy on PATH.
RUN bunx bun-pr 45631 && cp /tmp/bun-node-*/bun-*-pr45631 /usr/local/bin/bun-45631 && bun-45631 --revision
WORKDIR /repro
COPY hello.ts repro.sh diagnose.sh ./
CMD ["./repro.sh"]
