# Lambda Web Adapter を同梱した FastAPI コンテナ。
# Function URL 経由の HTTP リクエストを通常の ASGI アプリとして処理でき、
# ローカルでは `docker run -p 8080:8080` でそのまま動く。
FROM public.ecr.aws/docker/library/python:3.12-slim

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

# ビルド時にバージョン情報を焼き込む (build once の証跡)。
# RC ビルドでも "-rc.N" を除いた基底バージョンを渡すこと。
ARG APP_VERSION=local
ARG GIT_SHA=local
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PORT=8080

WORKDIR /app
RUN pip install --no-cache-dir "fastapi>=0.115" "uvicorn>=0.30"
COPY app ./app

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
