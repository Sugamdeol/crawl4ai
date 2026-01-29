FROM python:3.12-slim-bookworm AS build

# C4ai version & Env setup
ARG C4AI_VER=0.8.0
ENV C4AI_VERSION=$C4AI_VER \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright

ARG APP_HOME=/app
ARG GITHUB_REPO=https://github.com/unclecode/crawl4ai.git
ARG GITHUB_BRANCH=main
ARG TARGETARCH

# 1. Install System Dependencies (Root)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl wget gnupg git cmake pkg-config python3-dev \
    libjpeg-dev redis-server supervisor \
    libglib2.0-0 libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libdbus-1-3 libxcb1 libxkbcommon0 libx11-6 \
    libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2 libatspi2.0-0 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Setup User
RUN groupadd -r appuser && useradd --no-log-init -r -g appuser appuser
RUN mkdir -p /home/appuser/.cache && chown -R appuser:appuser /home/appuser
WORKDIR ${APP_HOME}

# 3. Install Python Deps (Root)
COPY deploy/docker/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 4. Setup Crawl4AI (Logic from your script)
COPY . /tmp/project/
RUN pip install --no-cache-dir /tmp/project/ && \
    crawl4ai-setup

# 5. The Playwright Fix (Switch to User BEFORE installing browsers)
USER appuser
RUN playwright install chromium --with-deps

# 6. Final Code Setup
USER root
COPY deploy/docker/* ${APP_HOME}/
COPY deploy/docker/static ${APP_HOME}/static
RUN chown -R appuser:appuser ${APP_HOME} && \
    mkdir -p /var/lib/redis /var/log/redis && \
    chown -R appuser:appuser /var/lib/redis /var/log/redis

# 7. Runtime
USER appuser
ENV PYTHON_ENV=production
EXPOSE 11235 6379

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD redis-cli ping > /dev/null && curl -f http://localhost:11235/health || exit 1

CMD ["supervisord", "-c", "supervisord.conf"]
