ARG PYTHON_VERSION=3.11
ARG BASE_IMAGE=python:${PYTHON_VERSION}-slim-trixie
ARG VENV_PATH=/prod_venv

FROM ${BASE_IMAGE} AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends python3-dev curl build-essential && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv

# Create virtual environment
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
RUN uv venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy storage metadata for editable dependency resolution
COPY storage/pyproject.toml storage/uv.lock storage/

# ========== Install kserve dependencies ==========
COPY kserve/pyproject.toml kserve/uv.lock kserve/
RUN cd kserve && uv sync --active --no-cache --no-dev

COPY kserve kserve
RUN cd kserve && uv sync --active --no-cache --no-dev

# ========== Install kserve storage dependencies ==========
COPY storage storage
RUN cd storage && uv pip install . --no-cache

# ========== Install sklearnserver dependencies ==========
COPY sklearnserver/pyproject.toml sklearnserver/uv.lock sklearnserver/
RUN cd sklearnserver && uv sync --active --no-cache --no-dev

COPY sklearnserver sklearnserver
RUN cd sklearnserver && uv sync --active --no-cache --no-dev

# Generate third-party licenses
COPY pyproject.toml pyproject.toml
COPY third_party/pip-licenses.py pip-licenses.py
RUN mkdir -p third_party/library && python3 pip-licenses.py


# =================== Final stage ===================
FROM ${BASE_IMAGE} AS prod

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN useradd kserve -m -u 1000 -d /home/kserve

# The base image ships pip/setuptools/wheel in the system site-packages; the
# runtime only uses the venv (built in the builder stage), so remove them
# outright. Upgrading instead would keep pip's vendored setuptools/msgpack
# copies around for scanners to flag.
RUN python -m pip uninstall -y pip setuptools wheel

# perl-base carries unfixable Criticals (CVE-2026-8376, CVE-2026-13221,
# CVE-2026-42496) and gzip an unfixable High (CVE-2026-41992); nothing in
# this image executes perl or the gzip binary (Python's gzip module uses
# zlib). Purging them leaves apt/dpkg and tar -z unusable in the final
# image. --force-depends: coreutils/sed/tar declare a dependency on gzip
# without linking it.
RUN dpkg --purge --force-remove-essential --force-depends perl-base gzip

COPY --from=builder --chown=kserve:kserve third_party third_party
COPY --from=builder --chown=kserve:kserve $VIRTUAL_ENV $VIRTUAL_ENV
COPY --from=builder kserve kserve
COPY --from=builder storage storage
COPY --from=builder sklearnserver sklearnserver

USER 1000
ENV PYTHONPATH=/sklearnserver
ENTRYPOINT ["python", "-m", "sklearnserver"]
