"""Minimal HTTP API used as the deployable workload for this demo."""

import os

from fastapi import FastAPI

SERVICE_NAME = "gha-ecs-oidc-demo"

# Interactive docs are disabled: this is a public endpoint with nothing to explore.
app = FastAPI(title=SERVICE_NAME, docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/")
def root() -> dict[str, str]:
    # APP_VERSION is baked into the image at build time (the git commit SHA).
    return {"service": SERVICE_NAME, "version": os.getenv("APP_VERSION", "dev")}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
