FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    jq \
    osmium-tool \
    osm2pgsql \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /pipelines
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --break-system-packages -r /tmp/requirements.txt

CMD ["/bin/bash"]
