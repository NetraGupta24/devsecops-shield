"""SplitEase: a small, stateless bill-splitting web app.

Stateless means nothing is stored on the server. That matters because Auto
Scaling and Blue-Green deployment create and destroy servers all the time.
"""

import os
import signal
import subprocess
import sys
import threading

from flask import Flask, abort, jsonify, render_template, request

from splitter import SplitError, clean_names, format_paise, split_equal, to_paise

APP_VERSION = "1.0.0"
MAX_CPU_SECONDS = 300

# Code run by each CPU-burning child process for the /cpu chaos endpoint.
_BURN_CODE = "import sys, time\nend = time.time() + int(sys.argv[1])\nwhile time.time() < end:\n    pass\n"


def _env_flag(name):
    return os.environ.get(name, "false").strip().lower() == "true"


def create_app(test_config=None):
    app = Flask(__name__)
    app.config.from_mapping(
        APP_VERSION=APP_VERSION,
        BUILD_NUMBER=os.environ.get("BUILD_NUMBER", "local"),
        CHAOS_MODE=_env_flag("CHAOS_MODE"),
        MAX_CONTENT_LENGTH=16 * 1024,  # reject request bodies over 16 KB
    )
    if test_config:
        app.config.update(test_config)

    @app.after_request
    def add_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'"
        )
        return response

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.post("/api/split")
    def api_split():
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            return jsonify(error="Send a JSON object with 'total' and 'people'"), 400
        try:
            total_paise = to_paise(data.get("total"))
            names = clean_names(data.get("people"))
            shares = split_equal(total_paise, names)
        except SplitError as err:
            return jsonify(error=str(err)), 400
        return jsonify(
            mode="equal",
            total=format_paise(total_paise),
            total_paise=total_paise,
            shares=[{"name": n, "amount": format_paise(p), "paise": p} for n, p in shares],
        )

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/version")
    def version():
        return jsonify(app="splitease", version=app.config["APP_VERSION"], build=app.config["BUILD_NUMBER"])

    # ---- Chaos endpoints: only exist when CHAOS_MODE=true -------------------

    @app.get("/crash")
    def crash():
        if not app.config["CHAOS_MODE"]:
            abort(404)
        # Under Gunicorn this code runs in a *worker* process. Killing only the
        # worker is useless: the Gunicorn master would silently start a new one.
        # So we signal the master (our parent), which shuts down the whole
        # server; the container then exits and Docker's restart policy restarts it.
        under_gunicorn = request.environ.get("SERVER_SOFTWARE", "").startswith("gunicorn")
        target_pid = os.getppid() if under_gunicorn else os.getpid()
        app.logger.warning("CHAOS: /crash called, sending SIGINT to pid %s", target_pid)
        # Wait half a second so this response reaches the caller first.
        threading.Timer(0.5, os.kill, args=(target_pid, signal.SIGINT)).start()
        return jsonify(status="crashing", signalled_pid=target_pid), 202

    @app.get("/cpu")
    def cpu():
        if not app.config["CHAOS_MODE"]:
            abort(404)
        try:
            seconds = int(request.args.get("seconds", "60"))
        except ValueError:
            return jsonify(error="seconds must be a whole number"), 400
        if seconds < 1:
            return jsonify(error="seconds must be at least 1"), 400
        seconds = min(seconds, MAX_CPU_SECONDS)
        # Start one busy process per CPU core and return immediately.
        # (Gunicorn kills a worker that blocks a request for more than 30 s.)
        processes = os.cpu_count() or 1
        for _ in range(processes):
            subprocess.Popen(  # noqa: S603 - fixed command, no user input in argv except an int
                [sys.executable, "-c", _BURN_CODE, str(seconds)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        app.logger.warning("CHAOS: /cpu burning %s CPU(s) for %s s", processes, seconds)
        return jsonify(status="burning", seconds=seconds, processes=processes), 202

    return app


app = create_app()

if __name__ == "__main__":
    # Local development only. In Docker the app runs under Gunicorn instead.
    app.run(host="127.0.0.1", port=5000)
