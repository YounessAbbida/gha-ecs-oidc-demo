# checkov:skip=CKV_DOCKER_2: ECS ignores Dockerfile HEALTHCHECK; the ALB target group checks /health instead.

# ---- build stage: install dependencies into an isolated virtualenv ----
FROM python:3.12-slim-trixie AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --requirement /tmp/requirements.txt

# ---- runtime stage: no pip cache, no build files, non-root ----
FROM python:3.12-slim-trixie

# PYTHONDONTWRITEBYTECODE: never write .pyc files, so the root filesystem can
# stay read-only (ECS readonlyRootFilesystem).
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY main.py .

# Declared last so a new version only rebuilds this layer.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

USER 10001:10001
EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
