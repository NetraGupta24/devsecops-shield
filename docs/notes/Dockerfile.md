# `Dockerfile`

**What it does:** The recipe Docker follows to build the SplitEase *image*: a packaged, read-only
bundle with Linux, Python, the app's packages and the code. Jenkins builds it as
`splitease:build-<BUILD_NUMBER>`.

**Line by line (the important parts):**
- `FROM python:3.14.10-slim-trixie`: start from the official Python image on Debian "slim". Slim
  images leave out compilers and extra tools, so they are smaller and have fewer vulnerabilities for
  Trivy to find. The exact version is pinned so builds are repeatable.
- `ENV PYTHONUNBUFFERED=1`: print logs immediately (important for `docker logs` and CloudWatch).
- `apt-get upgrade`: installs Debian security fixes published *after* the base image was built.
  Without it, Trivy failed the build on 2 HIGH `zlib1g` CVEs that already had fixes.
- `groupadd` / `useradd`: create user `app` (uid 10001). **Running as non-root** means that if an
  attacker ever breaks into the app, they are an unprivileged user, not root.
- `COPY requirements.txt` then `pip install`, *before* copying the code: Docker caches each layer.
  The slow `pip install` layer is reused until `requirements.txt` changes.
- `pip uninstall -y pip`: the running app never needs pip. Removing it shrinks the attack surface,
  and pip's bundled `urllib3`/`msgpack`/`setuptools` copies had HIGH CVEs that Trivy flagged.
- `COPY app/ .`: copy the code. The files stay owned by root, so the `app` user can read them but
  not change them.
- `ARG BUILD_NUMBER` / `ENV BUILD_NUMBER`: Jenkins passes `--build-arg BUILD_NUMBER=17`. The app
  shows it at `/version`, which is how the pipeline proves the *new* build is running.
- `ENV CHAOS_MODE=false`: chaos endpoints are off unless the server explicitly enables them.
- `USER app`: everything from here on (including the running app) is non-root.
- `CMD ["gunicorn", ...]`: start Gunicorn, a production web server (Flask's built-in server is
  for development only). It runs 2 worker processes on port 5000 and logs to stdout. The "exec
  form" `[...]` makes Gunicorn PID 1 in the container, so signals reach it directly.

**How it connects:** Jenkins `docker build` → Trivy scans the image → pushed to ECR → EC2 runs it with
`docker run --restart unless-stopped`.
