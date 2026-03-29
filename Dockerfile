FROM postgres:15

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-plpython3-15 \
    python3-pip \
    python3-setuptools \
    && pip3 install --no-cache-dir pyyaml --break-system-packages \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY pg_yaml_loader.control /usr/share/postgresql/15/extension/
COPY pg_yaml_loader--1.0.sql /usr/share/postgresql/15/extension/

USER postgres
