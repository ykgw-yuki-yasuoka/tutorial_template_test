"""バージョン情報を返すだけの最小 API。

APP_VERSION / GIT_SHA はイメージビルド時に焼き込まれる (Dockerfile の ARG)。
IMAGE_DIGEST / APP_ENV はデプロイ時に Lambda の環境変数として注入される。
=> 「同一アーティファクトが環境を渡り歩く」ことを /api/version で観測できる。
"""

import os

from fastapi import FastAPI

app = FastAPI()


@app.get("/api/version")
def version() -> dict:
    return {
        "service": "backend",
        "version": os.getenv("APP_VERSION", "local"),
        "git_sha": os.getenv("GIT_SHA", "local"),
        "image_digest": os.getenv("IMAGE_DIGEST"),
        "environment": os.getenv("APP_ENV", "local"),
    }


@app.get("/api/healthz")
def healthz() -> dict:
    return {"ok": True}
