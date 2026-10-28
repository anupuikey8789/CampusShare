"""Local HTTP integration checks for the CampusShare backend.

These checks use a local PostgREST-shaped mock and never connect to Supabase.
Run with: python tests/test_api.py build-msvc/campusshare_backend.exe
"""

import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class MockSupabaseHandler(BaseHTTPRequestHandler):
    response_status = 200
    response_body = b'[{"mock":true}]'

    def do_GET(self):
        if self.path != "/rest/v1/categories?select=*&limit=100":
            self.send_error(404)
            return
        body = type(self).response_body
        self.send_response(type(self).response_status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        pass


def available_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request_json(url, origin=None):
    headers = {"Origin": origin} if origin else {}
    request = urllib.request.Request(url, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=3)
    except urllib.error.HTTPError as error:
        response = error
    return response.code, response.headers, response.read()


def wait_for_server(process, base_url):
    deadline = time.monotonic() + 8
    last_response = "no response yet"
    while time.monotonic() < deadline:
        if process.poll() is not None:
            _, stderr = process.communicate()
            raise AssertionError(
                f"backend exited during startup with code {process.returncode}: {stderr}"
            )
        try:
            status, _, body = request_json(base_url + "/api/health")
            if status == 200:
                return
            last_response = f"HTTP {status}: {body!r}"
        except (OSError, urllib.error.URLError):
            last_response = "connection refused or timed out"
            time.sleep(0.1)
    if process.poll() is None:
        process.terminate()
    stdout, stderr = process.communicate(timeout=5)
    raise AssertionError(
        f"backend did not become ready within 8 seconds ({last_response}); "
        f"stdout={stdout!r}; stderr={stderr!r}"
    )


def run():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python tests/test_api.py <backend-executable>")
    executable = Path(sys.argv[1]).resolve()
    if not executable.is_file():
        raise SystemExit(f"backend executable not found: {executable}")

    safe_env = {
        key: os.environ[key]
        for key in ("PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP")
        if key in os.environ
    }

    workdir = executable.parent
    if (workdir / ".env").exists():
        raise SystemExit("Refusing to run tests from a build directory containing .env")
    missing_config = subprocess.run(
        [str(executable)],
        cwd=workdir,
        env=safe_env,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert missing_config.returncode != 0
    assert "Missing SUPABASE_URL or SUPABASE_ANON_KEY" in missing_config.stderr

    mock = ThreadingHTTPServer(("127.0.0.1", 0), MockSupabaseHandler)
    mock_thread = threading.Thread(target=mock.serve_forever, daemon=True)
    mock_thread.start()
    port = available_port()
    base_url = f"http://127.0.0.1:{port}"
    env = dict(safe_env)
    env.update(
        {
            "SUPABASE_URL": f"http://127.0.0.1:{mock.server_port}",
            "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
            "SERVER_HOST": "127.0.0.1",
            "SERVER_PORT": str(port),
            "CORS_ALLOWED_ORIGINS": "http://localhost:5500",
        }
    )
    process = subprocess.Popen(
        [str(executable)],
        cwd=workdir,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_server(process, base_url)

        status, headers, body = request_json(
            base_url + "/api/health", "http://localhost:5500"
        )
        assert status == 200 and json.loads(body)["status"] == "ok"
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"

        status, _, body = request_json(base_url + "/api/test")
        test_result = json.loads(body)
        assert status == 200 and test_result["status"] == "success"

        status, _, body = request_json(base_url + "/api/categories")
        assert status == 200 and json.loads(body) == [{"mock": True}]

        MockSupabaseHandler.response_status = 403
        MockSupabaseHandler.response_body = b'{"message":"private mock detail"}'
        status, _, body = request_json(base_url + "/api/categories")
        error_result = json.loads(body)
        assert status == 502 and error_result["error"]["code"] == "upstream_error"
        assert b"private mock detail" not in body

        MockSupabaseHandler.response_status = 200
        MockSupabaseHandler.response_body = b"not-json"
        status, _, body = request_json(base_url + "/api/categories")
        assert status == 502
        assert json.loads(body)["error"]["code"] == "invalid_upstream_response"

        status, headers, _ = request_json(
            base_url + "/api/health", "http://untrusted.example"
        )
        assert status == 200
        assert headers.get("Access-Control-Allow-Origin") is None
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
        mock.shutdown()
        mock.server_close()
        mock_thread.join(timeout=2)

    print("PASS: missing-config startup, health, test, categories mock, upstream errors, JSON validation, and CORS")


if __name__ == "__main__":
    run()
