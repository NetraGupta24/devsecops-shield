# SplitEase production image.
# Small "slim" Debian base + only the runtime packages + a non-root user.
FROM python:3.14.10-slim-trixie

# PYTHONDONTWRITEBYTECODE: don't write .pyc files; PYTHONUNBUFFERED: logs appear immediately.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# A dedicated, unprivileged user to run the app (never run web apps as root).
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# Install dependencies first, in their own layer: Docker re-uses this layer from
# cache as long as requirements.txt does not change, which makes rebuilds fast.
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code (owned by root, so the app user cannot modify it).
COPY app/ .

# Jenkins passes its build number in; /version reports it.
ARG BUILD_NUMBER=local
ENV BUILD_NUMBER=${BUILD_NUMBER} \
    CHAOS_MODE=false

USER app
EXPOSE 5000

# Gunicorn: production web server. 2 worker processes, logs to stdout/stderr
# (so `docker logs` and the CloudWatch awslogs driver can collect them).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
