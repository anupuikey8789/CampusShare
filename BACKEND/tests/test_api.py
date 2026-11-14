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
    categories_body = b'[{"mock":true}]'
    resources_body = b'[{"id":"resource-1","title":"Book","owner_id":"owner-1","category_id":"cat-1","resource_type":"book","availability_status":"available","created_at":"2026-01-01T00:00:00Z"}]'
    image_slots_body = b'[]'
    image_remaining_body = b'[]'
    image_reorder_body = b'[]'
    image_registration_body = b'[{"id":42,"resource_id":123,"storage_path":"user-123/123/photo.jpg","alt_text":"Front","sort_order":0,"created_at":"2026-11-12T00:00:00Z"}]'
    resource_owner_id = "owner-1"
    resource_availability = "available"
    resource_write_status = 200
    borrow_write_status = 201
    borrow_conflict_body = b"[]"
    rpc_status = 200
    rpc_body = b'[{"id":123,"resource_id":123,"borrower_id":"user-123","requested_at":"2026-01-01T00:00:00Z","due_at":null,"returned_at":null,"status":"pending"}]'
    status_rpc_body = b'[{"id":123,"resource_id":123,"borrower_id":"user-123","requested_at":"2026-01-01T00:00:00Z","due_at":null,"returned_at":null,"status":"approved"}]'
    rpc_delay_seconds = 0
    auth_status = 200
    requests = []

    def _reply(self, status, body, request_body=None):
        if request_body is None and self.command in ("POST", "PATCH", "PUT"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        type(self).requests.append(
            (self.command, self.path, self.headers.get("Authorization"), self.headers.get("apikey"), request_body or b"")
        )
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if body:
                self.wfile.write(body)
        except OSError:
            # Expected when a timeout test closes the RPC connection first.
            pass

    def do_GET(self):
        if self.path == "/auth/v1/user":
            if type(self).auth_status != 200:
                self._reply(type(self).auth_status, b'{"message":"mock auth unavailable"}')
            elif self.headers.get("Authorization") == "Bearer valid-token":
                self._reply(200, b'{"id":"user-123","is_anonymous":false}')
            elif self.headers.get("Authorization") == "Bearer owner-token":
                self._reply(200, b'{"id":"owner-1","is_anonymous":false}')
            elif self.headers.get("Authorization") == "Bearer other-user-token":
                self._reply(200, b'{"id":"user-456","is_anonymous":false}')
            elif self.headers.get("Authorization") == "Bearer anonymous-token":
                self._reply(200, b'{"id":"anonymous-789","is_anonymous":true}')
            else:
                self._reply(401, b'{"message":"invalid token"}')
            return
        if not self.path.startswith("/rest/v1/"):
            self._reply(404, b'{"message":"not found"}')
            return
        if type(self).response_status != 200:
            self._reply(type(self).response_status, type(self).response_body)
            return
        if self.path.startswith("/rest/v1/categories"):
            self._reply(200, type(self).categories_body)
        elif self.path.startswith("/rest/v1/resources"):
            if "select=id,owner_id,availability_status" in self.path:
                body = json.dumps([{
                    "id": "resource-1",
                    "owner_id": type(self).resource_owner_id,
                    "availability_status": type(self).resource_availability,
                }]).encode()
                self._reply(200, body)
            elif "select=id,owner_id&id=eq." in self.path:
                body = json.dumps([{
                    "id": "resource-1",
                    "owner_id": type(self).resource_owner_id,
                }]).encode()
                self._reply(200, body)
            else:
                self._reply(200, type(self).resources_body)
        elif self.path.startswith("/rest/v1/resource_transfer_requests"):
            self._reply(200, b'[{"id":51,"resource_id":123,"owner_id":"owner-1","requester_id":"user-123","request_type":"sell","status":"pending","requested_at":"2026-11-12T00:00:00Z","completed_at":null}]')
        elif self.path.startswith("/rest/v1/resource_images"):
            if "select=id&resource_id=" in self.path:
                self._reply(200, type(self).image_remaining_body)
            elif "select=id,sort_order" in self.path:
                self._reply(200, type(self).image_slots_body)
            elif "select=id,resource_id,storage_path" in self.path and self.headers.get("Authorization") == "Bearer owner-token":
                self._reply(200, b'[{"id":42,"resource_id":123,"storage_path":"owner-1/123/photo.jpg"}]')
            else:
                self._reply(200, b'[{"id":42,"resource_id":123,"storage_path":"user-123/123/photo.jpg","alt_text":"","sort_order":0,"created_at":"2026-11-12T00:00:00Z"}]')
        elif self.path.startswith("/rest/v1/resource_handover_details"):
            self._reply(200, b'[{"resource_id":123,"pickup_location":"Main library","meeting_point":"Student center","preferred_pickup_time":null,"instructions":null,"updated_at":"2026-11-12T00:00:00Z"}]')
        elif self.path.startswith("/rest/v1/resource_listing_reports"):
            self._reply(200, b'[{"id":7,"resource_id":123,"reporter_id":"user-123","reason":"other","details":null,"status":"pending","created_at":"2026-11-12T00:00:00Z"}]')
        elif self.path.startswith("/rest/v1/borrow_requests"):
            if "status=in." in self.path:
                self._reply(200, type(self).borrow_conflict_body)
            else:
                self._reply(200, b'[{"resource_id":"resource-1","borrower_id":"user-123","requested_at":"2026-10-29T00:00:00Z","status":"pending"},{"resource_id":"resource-2","borrower_id":"user-456","requested_at":"2026-10-29T00:00:00Z","status":"pending"}]')
        else:
            self._reply(404, b'{"message":"not found"}')

    def do_POST(self):
        if self.path.startswith("/rest/v1/rpc/"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            if type(self).rpc_delay_seconds:
                time.sleep(type(self).rpc_delay_seconds)
            if self.path == "/rest/v1/rpc/reorder_resource_images":
                self._reply(200, type(self).image_reorder_body, request_body)
                return
            if self.path == "/rest/v1/rpc/register_resource_images":
                self._reply(200, type(self).image_registration_body, request_body)
                return
            if self.path == "/rest/v1/rpc/delete_resource_image_metadata":
                self._reply(200, b"true", request_body)
                return
            if (self.path == "/rest/v1/rpc/update_resource_atomic" and
                    self.headers.get("Authorization") == "Bearer anonymous-token"):
                self._reply(401, b'{"code":"28000","message":"private authentication detail"}', request_body)
                return
            if (self.path == "/rest/v1/rpc/update_resource_atomic" and
                    self.headers.get("Authorization") != "Bearer owner-token"):
                self._reply(403, b'{"code":"42501","message":"private authorization detail"}', request_body)
                return
            if self.path in (
                "/rest/v1/rpc/approve_borrow_request",
                "/rest/v1/rpc/reject_borrow_request",
                "/rest/v1/rpc/return_borrowed_resource",
                "/rest/v1/rpc/approve_resource_transfer_request",
                "/rest/v1/rpc/reject_resource_transfer_request",
                "/rest/v1/rpc/complete_resource_sale",
                "/rest/v1/rpc/complete_resource_donation",
            ):
                if self.headers.get("Authorization") == "Bearer anonymous-token":
                    self._reply(401, b'{"code":"28000","message":"private authentication detail"}', request_body)
                    return
                if self.headers.get("Authorization") != "Bearer owner-token":
                    self._reply(403, b'{"code":"42501","message":"private authorization detail"}', request_body)
                    return
                if type(self).rpc_status != 200:
                    self._reply(type(self).rpc_status, type(self).rpc_body, request_body)
                    return
                self._reply(200, type(self).status_rpc_body, request_body)
                return
            self._reply(type(self).rpc_status, type(self).rpc_body, request_body)
        elif self.path.startswith("/rest/v1/resources"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            try:
                resource = json.loads(request_body)
            except (json.JSONDecodeError, UnicodeDecodeError):
                resource = {}
            if resource.get("category_id") == 99999:
                self._reply(400, b'{"message":"mock foreign key violation"}', request_body)
                return
            if type(self).resource_write_status != 200:
                self._reply(type(self).resource_write_status, b'{"message":"mock RLS or constraint detail"}', request_body)
                return
            self._reply(201, b'[{"id":"resource-1","owner_id":"user-123","title":"Book"}]', request_body)
        elif self.path.startswith("/rest/v1/resource_images"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self._reply(201, b'[{"id":42,"resource_id":123,"storage_path":"user-123/123/photo.jpg","alt_text":"","sort_order":0,"created_at":"2026-11-12T00:00:00Z"}]', request_body)
        elif self.path.startswith("/rest/v1/resource_handover_details"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self._reply(201, b'[{"resource_id":123,"pickup_location":"Main library","meeting_point":"Student center","preferred_pickup_time":null,"instructions":null,"updated_at":"2026-11-12T00:00:00Z"}]', request_body)
        elif self.path.startswith("/rest/v1/resource_listing_reports"):
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self._reply(201, b'[{"id":7,"resource_id":123,"reporter_id":"user-123","reason":"other","details":null,"status":"pending","created_at":"2026-11-12T00:00:00Z"}]', request_body)
        elif self.path.startswith("/rest/v1/borrow_requests"):
            if type(self).borrow_write_status != 201:
                self._reply(type(self).borrow_write_status, b'{"message":"mock unique constraint detail"}')
                return
            borrower_id = "user-456" if self.headers.get("Authorization") == "Bearer other-user-token" else "user-123"
            body = json.dumps([{
                "resource_id": "resource-1",
                "borrower_id": borrower_id,
                "status": "pending",
            }]).encode()
            self._reply(201, body)
        else:
            self._reply(404, b'{"message":"not found"}')

    def do_PATCH(self):
        if self.path.startswith("/rest/v1/resources"):
            if self.headers.get("Authorization") != "Bearer owner-token":
                self._reply(403, b'{"message":"row level security denied update"}')
                return
            if type(self).resource_write_status != 200:
                self._reply(type(self).resource_write_status, b'{"message":"mock RLS or constraint detail"}')
                return
            self._reply(200, b'[{"id":"resource-1","owner_id":"user-123","title":"Updated"}]')
            return
        self._reply(404, b'{"message":"not found"}')

    def do_DELETE(self):
        if self.path == "/storage/v1/object/campusshare-resource-images":
            request_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            if self.headers.get("Authorization") != "Bearer owner-token":
                self._reply(403, b'{"message":"storage owner policy denied delete"}', request_body)
                return
            self._reply(200, b'{"message":"removed"}', request_body)
            return
        if self.path.startswith("/rest/v1/resource_images"):
            self._reply(200, b'[{"id":"image-1"}]')
            return
        if self.path.startswith("/rest/v1/resources"):
            if self.headers.get("Authorization") != "Bearer owner-token":
                self._reply(403, b'{"message":"row level security denied delete"}')
                return
            if type(self).resource_write_status != 200:
                self._reply(type(self).resource_write_status, b'{"message":"mock RLS or constraint detail"}')
                return
            self._reply(204, b"")
            return
        self._reply(404, b'{"message":"not found"}')

    def log_message(self, _format, *_args):
        pass


def available_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request_json(url, origin=None, method=None, body=None, token=None, timeout=3):
    headers = {"Origin": origin} if origin else {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=timeout)
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

    for unsafe_key in (
        "sb_secret_mock_only",
        "a.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x",
    ):
        unsafe_env = dict(safe_env)
        unsafe_env.update(
            {
                "SUPABASE_URL": "https://mock.supabase.co",
                "SUPABASE_ANON_KEY": unsafe_key,
            }
        )
        rejected_key = subprocess.run(
            [str(executable)],
            cwd=workdir,
            env=unsafe_env,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert rejected_key.returncode != 0
        assert "service_role key is not allowed" in rejected_key.stderr
        assert unsafe_key not in rejected_key.stderr

    placeholder_env = dict(safe_env)
    placeholder_key = "your-staging-publishable-key"
    placeholder_env.update(
        {
            "SUPABASE_URL": "https://mock.supabase.co",
            "SUPABASE_ANON_KEY": placeholder_key,
        }
    )
    rejected_placeholder = subprocess.run(
        [str(executable)], cwd=workdir, env=placeholder_env,
        text=True, capture_output=True, timeout=10,
    )
    assert rejected_placeholder.returncode != 0
    assert "not a recognized publishable/anon key" in rejected_placeholder.stderr
    assert placeholder_key not in rejected_placeholder.stderr

    conflicting_env = dict(safe_env)
    conflicting_env.update({
        "SUPABASE_URL": "https://mock.supabase.co",
        "SUPABASE_ANON_KEY": "sb_publishable_first_mock",
        "SUPABASE_API_KEY": "sb_publishable_second_mock",
    })
    conflicting_keys = subprocess.run(
        [str(executable)], cwd=workdir, env=conflicting_env,
        text=True, capture_output=True, timeout=10,
    )
    assert conflicting_keys.returncode != 0
    assert "Conflicting Supabase public API key variables" in conflicting_keys.stderr
    assert "sb_publishable_first_mock" not in conflicting_keys.stderr
    assert "sb_publishable_second_mock" not in conflicting_keys.stderr

    invalid_flag_env = dict(safe_env)
    invalid_flag_env.update(
        {
            "SUPABASE_URL": "https://mock.supabase.co",
            "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
            "SUPABASE_RPC_CREATE_BORROW_REQUEST": "sometimes",
        }
    )
    invalid_flag = subprocess.run(
        [str(executable)], cwd=workdir, env=invalid_flag_env,
        text=True, capture_output=True, timeout=10,
    )
    assert invalid_flag.returncode != 0
    assert "Invalid SUPABASE_RPC_CREATE_BORROW_REQUEST" in invalid_flag.stderr
    assert "sb_publishable_mock_only" not in invalid_flag.stderr

    invalid_status_flag_env = dict(safe_env)
    invalid_status_flag_env.update(
        {
            "SUPABASE_URL": "https://mock.supabase.co",
            "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
            "SUPABASE_RPC_BORROW_STATUS": "enabled",
        }
    )
    invalid_status_flag = subprocess.run(
        [str(executable)], cwd=workdir, env=invalid_status_flag_env,
        text=True, capture_output=True, timeout=10,
    )
    assert invalid_status_flag.returncode != 0
    assert "Invalid SUPABASE_RPC_BORROW_STATUS" in invalid_status_flag.stderr
    assert "sb_publishable_mock_only" not in invalid_status_flag.stderr

    invalid_marketplace_flag_env = dict(safe_env)
    invalid_marketplace_flag_env.update({
        "SUPABASE_URL": "https://mock.supabase.co",
        "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
        "SUPABASE_MARKETPLACE_ENABLED": "on-ish",
    })
    invalid_marketplace_flag = subprocess.run(
        [str(executable)], cwd=workdir, env=invalid_marketplace_flag_env,
        text=True, capture_output=True, timeout=10,
    )
    assert invalid_marketplace_flag.returncode != 0
    assert "Invalid SUPABASE_MARKETPLACE_ENABLED" in invalid_marketplace_flag.stderr
    assert "sb_publishable_mock_only" not in invalid_marketplace_flag.stderr

    invalid_images_flag_env = dict(safe_env)
    invalid_images_flag_env.update({
        "SUPABASE_URL": "https://mock.supabase.co",
        "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
        "SUPABASE_RESOURCE_IMAGES_ENABLED": "sometimes",
    })
    invalid_images_flag = subprocess.run(
        [str(executable)], cwd=workdir, env=invalid_images_flag_env,
        text=True, capture_output=True, timeout=10,
    )
    assert invalid_images_flag.returncode != 0
    assert "Invalid SUPABASE_RESOURCE_IMAGES_ENABLED" in invalid_images_flag.stderr
    assert "sb_publishable_mock_only" not in invalid_images_flag.stderr

    unsafe_status_only_env = dict(safe_env)
    unsafe_status_only_env.update(
        {
            "SUPABASE_URL": "https://mock.supabase.co",
            "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
            "SUPABASE_RPC_BORROW_STATUS": "true",
            "SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE": "false",
        }
    )
    unsafe_status_only = subprocess.run(
        [str(executable)], cwd=workdir, env=unsafe_status_only_env,
        text=True, capture_output=True, timeout=10,
    )
    assert unsafe_status_only.returncode != 0
    assert "requires SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE=true" in unsafe_status_only.stderr
    assert "sb_publishable_mock_only" not in unsafe_status_only.stderr

    mock = ThreadingHTTPServer(("127.0.0.1", 0), MockSupabaseHandler)
    mock_thread = threading.Thread(target=mock.serve_forever, daemon=True)
    mock_thread.start()
    port = available_port()
    base_url = f"http://127.0.0.1:{port}"

    # SUPABASE_API_KEY is accepted when the canonical ANON_KEY alias is absent.
    api_alias_port = available_port()
    api_alias_env = dict(safe_env)
    api_alias_env.update(
        {
            "SUPABASE_URL": f"http://127.0.0.1:{mock.server_port}",
            "SUPABASE_API_KEY": "sb_publishable_mock_only",
            "SERVER_HOST": "127.0.0.1",
            "SERVER_PORT": str(api_alias_port),
            "CORS_ALLOWED_ORIGINS": "http://localhost:5500",
        }
    )
    api_alias_process = subprocess.Popen(
        [str(executable)], cwd=workdir, env=api_alias_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        wait_for_server(api_alias_process, f"http://127.0.0.1:{api_alias_port}")
        alias_status, _, alias_body = request_json(
            f"http://127.0.0.1:{api_alias_port}/api/health"
        )
        assert alias_status == 200 and json.loads(alias_body)["status"] == "ok"
    finally:
        if api_alias_process.poll() is None:
            api_alias_process.terminate()
        api_alias_process.communicate(timeout=5)

    env = dict(safe_env)
    env.update(
        {
            "SUPABASE_URL": f"http://127.0.0.1:{mock.server_port}",
            "SUPABASE_ANON_KEY": "sb_publishable_mock_only",
            "SUPABASE_API_KEY": "sb_publishable_mock_only",
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
    rpc_process = None
    marketplace_process = None
    image_only_process = None
    try:
        wait_for_server(process, base_url)

        status, headers, body = request_json(
            base_url + "/api/health", "http://localhost:5500"
        )
        health_body = json.loads(body)
        assert status == 200 and health_body["status"] == "ok"
        assert health_body["features"]["borrow_request_rpc_enabled"] is False
        assert health_body["features"]["atomic_resource_update_rpc_enabled"] is False
        assert health_body["features"]["borrow_status_rpc_enabled"] is False
        assert health_body["features"]["resource_images_enabled"] is False
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"

        image_gate_before = len(MockSupabaseHandler.requests)
        status, _, body = request_json(
            base_url + "/api/resources/123/images", token="valid-token",
        )
        assert status == 503 and json.loads(body)["error"]["code"] == "resource_images_disabled"
        assert len(MockSupabaseHandler.requests) == image_gate_before + 1  # Auth only; image table untouched

        status, _, body = request_json(base_url + "/api/test")
        test_result = json.loads(body)
        assert status == 200 and test_result["status"] == "success"

        status, _, body = request_json(base_url + "/api/categories")
        assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
        protected_requests = [
            ("GET", "/api/resources", None),
            ("GET", "/api/resources/resource-1", None),
            ("POST", "/api/resources", b"{}"),
            ("PATCH", "/api/resources/resource-1", b"{}"),
            ("DELETE", "/api/resources/resource-1", None),
            ("GET", "/api/borrow-requests", None),
            ("POST", "/api/borrow-requests", b"{}"),
        ]
        for method, path, payload in protected_requests:
            status, _, body = request_json(base_url + path, method=method, body=payload)
            assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized", path
        for action in ("approve", "reject", "return"):
            status, _, body = request_json(
                base_url + f"/api/borrow-requests/123/{action}", method="POST", body=b"{}",
            )
            assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
            status, _, body = request_json(
                base_url + f"/api/borrow-requests/123/{action}", method="POST",
                body=b"{}", token="owner-token",
            )
            assert status == 503 and json.loads(body)["error"]["code"] == "borrow_status_pending"

        status, headers, body = request_json(
            base_url + "/api/categories", "http://localhost:5500", token="valid-token"
        )
        assert status == 200 and json.loads(body) == [{"mock": True}]
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"
        status, headers, body = request_json(
            base_url + "/api/resources", "http://localhost:5500", token="valid-token"
        )
        assert status == 200 and json.loads(body)[0]["id"] == "resource-1"
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"

        categories_read = [entry for entry in MockSupabaseHandler.requests if entry[0] == "GET" and "/rest/v1/categories" in entry[1]][-1]
        resources_read = [entry for entry in MockSupabaseHandler.requests if entry[0] == "GET" and "/rest/v1/resources" in entry[1] and "id=eq." not in entry[1]][-1]
        auth_check = [entry for entry in MockSupabaseHandler.requests if entry[0] == "GET" and entry[1] == "/auth/v1/user"][-1]
        assert auth_check[2] == "Bearer valid-token"
        assert auth_check[3] == "sb_publishable_mock_only"
        for read in (categories_read, resources_read):
            assert read[2] == "Bearer valid-token"
            assert read[3] == "sb_publishable_mock_only"
        assert "select=id,name,created_at" in categories_read[1]
        assert "select=id,title,description,category_id,owner_id,resource_type,availability_status,created_at" in resources_read[1]

        MockSupabaseHandler.categories_body = b"[]"
        MockSupabaseHandler.resources_body = b"[]"
        status, _, body = request_json(base_url + "/api/categories", token="valid-token")
        assert status == 200 and json.loads(body) == []
        status, _, body = request_json(base_url + "/api/resources", token="valid-token")
        assert status == 200 and json.loads(body) == []

        MockSupabaseHandler.response_status = 500
        MockSupabaseHandler.response_body = b'{"message":"private mock detail"}'
        for path in ("/api/categories", "/api/resources"):
            status, _, body = request_json(base_url + path, token="valid-token")
            error_result = json.loads(body)
            assert status == 502 and error_result["error"]["code"] == "upstream_error"
            assert b"private mock detail" not in body

        MockSupabaseHandler.response_status = 200
        MockSupabaseHandler.categories_body = b"not-json"
        MockSupabaseHandler.resources_body = b"not-json"
        for path in ("/api/categories", "/api/resources"):
            status, _, body = request_json(base_url + path, token="valid-token")
            assert status == 502
            assert json.loads(body)["error"]["code"] == "invalid_upstream_response"

        MockSupabaseHandler.response_status = 200
        MockSupabaseHandler.categories_body = b'[{"mock":true}]'
        MockSupabaseHandler.resources_body = b'[{"id":"resource-1","title":"Book","owner_id":"user-123"}]'

        status, headers, _ = request_json(
            base_url + "/api/health", "http://untrusted.example"
        )
        assert status == 200
        assert headers.get("Access-Control-Allow-Origin") is None

        status, headers, body = request_json(
            base_url + "/api/unknown", "http://localhost:5500"
        )
        assert status == 404 and json.loads(body)["error"]["code"] == "not_found"
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"

        status, _, body = request_json(
            base_url + "/api/unknown", method="POST", body=b"{malformed"
        )
        assert status == 404 and json.loads(body)["error"]["code"] == "not_found"

        status, headers, _ = request_json(
            base_url + "/api/resources", "http://localhost:5500", method="OPTIONS"
        )
        assert status == 204
        assert headers.get("Access-Control-Allow-Origin") == "http://localhost:5500"
        assert headers.get("Access-Control-Allow-Methods") == "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        assert headers.get("Access-Control-Allow-Headers") == "Content-Type, Authorization"

        status, headers, _ = request_json(
            base_url + "/api/categories", "http://untrusted.example", method="OPTIONS"
        )
        assert status == 204
        assert headers.get("Access-Control-Allow-Origin") is None

        status, _, body = request_json(base_url + "/api/resources")
        assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
        status, _, body = request_json(base_url + "/api/resources", token="invalid-token")
        assert status == 401 and json.loads(body)["error"]["code"] == "auth_rejected"
        status, _, body = request_json(base_url + "/api/resources", token="expired-token")
        assert status == 401 and json.loads(body)["error"]["code"] == "auth_rejected"
        status, _, body = request_json(base_url + "/api/resources", token="not a token")
        assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
        MockSupabaseHandler.auth_status = 503
        status, _, body = request_json(base_url + "/api/resources", token="valid-token")
        assert status == 503 and json.loads(body)["error"]["code"] == "auth_unavailable"
        MockSupabaseHandler.auth_status = 429
        status, _, body = request_json(base_url + "/api/resources", token="valid-token")
        assert status == 503 and json.loads(body)["error"]["code"] == "auth_unavailable"
        MockSupabaseHandler.auth_status = 200

        status, _, body = request_json(base_url + "/api/resources", token="valid-token")
        assert status == 200 and json.loads(body)[0]["id"] == "resource-1"
        status, _, body = request_json(base_url + "/api/resources/resource-1", token="valid-token")
        assert status == 200 and json.loads(body)[0]["id"] == "resource-1"

        create_resource = json.dumps({"title": "Textbook", "category_id": "10", "resource_type": "book", "owner_id": "attacker"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=create_resource, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        create_resource = json.dumps({"title": "Textbook", "category_id": "10", "availability_status": "borrowed"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=create_resource, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_availability_status"
        create_resource = json.dumps({"title": "   "}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=create_resource, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=b"{malformed", token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=b" " * (16 * 1024 + 1), token="valid-token")
        assert status == 413 and json.loads(body)["error"]["code"] == "payload_too_large"
        create_resource = json.dumps({"title": "Textbook", "category_id": "10", "resource_type": "book", "availability_status": "available"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=create_resource, token="valid-token")
        assert status == 201 and json.loads(body)[0]["owner_id"] == "user-123"
        posted = [entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and "resources" in entry[1]][-1]
        assert posted[2] == "Bearer valid-token"
        assert json.loads(posted[4])["owner_id"] == "user-123"
        assert json.loads(posted[4])["category_id"] == 10
        missing_category = json.dumps({"title": "Textbook", "resource_type": "book"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=missing_category, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_category_id"
        malformed_category = json.dumps({"title": "Textbook", "category_id": "not-a-bigint", "resource_type": "book"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=malformed_category, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_category_id"
        invalid_category = json.dumps({"title": "Textbook", "category_id": "99999", "resource_type": "book"}).encode()
        status, _, body = request_json(base_url + "/api/resources", method="POST", body=invalid_category, token="valid-token")
        assert status == 422 and json.loads(body)["error"]["code"] == "invalid_data"
        assert b"mock foreign key violation" not in body

        spoofed_update = json.dumps({"title": "Hacked", "owner_id": "attacker"}).encode()
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=spoofed_update, token="owner-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        update_resource = json.dumps({"title": "Updated", "availability_status": "unavailable"}).encode()
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=update_resource, token="owner-token")
        assert status == 200 and json.loads(body)[0]["title"] == "Updated"
        patched = [entry for entry in MockSupabaseHandler.requests if entry[0] == "PATCH" and "resources" in entry[1]][-1]
        assert patched[2] == "Bearer owner-token"
        assert "owner_id" not in json.loads(patched[4])
        MockSupabaseHandler.resource_write_status = 403
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=update_resource, token="owner-token")
        assert status == 403 and json.loads(body)["error"]["code"] == "permission_denied"
        assert b"mock RLS or constraint detail" not in body
        MockSupabaseHandler.resource_write_status = 200
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=update_resource, token="valid-token")
        assert status == 403 and json.loads(body)["error"]["code"] == "forbidden"
        invalid_update = json.dumps({"availability_status": "borrowed"}).encode()
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=invalid_update, token="owner-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_availability_status"
        invalid_category_update = json.dumps({"category_id": "not-a-bigint"}).encode()
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=invalid_category_update, token="owner-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_category_id"
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="PATCH", body=b" " * (16 * 1024 + 1), token="owner-token")
        assert status == 413 and json.loads(body)["error"]["code"] == "payload_too_large"

        status, _, body = request_json(base_url + "/api/resources/resource-1", method="DELETE", token="owner-token")
        assert status == 204
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="DELETE", token="valid-token")
        assert status == 403 and json.loads(body)["error"]["code"] == "forbidden"
        MockSupabaseHandler.resource_write_status = 409
        status, _, body = request_json(base_url + "/api/resources/resource-1", method="DELETE", token="owner-token")
        assert status == 409 and json.loads(body)["error"]["code"] == "conflict"
        MockSupabaseHandler.resource_write_status = 200

        invalid_borrow = json.dumps({"resource_id": "resource-1", "borrower_id": "attacker"}).encode()
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=invalid_borrow, token="valid-token")
        assert status == 400
        invalid_status = json.dumps({"resource_id": "resource-1", "status": "approved"}).encode()
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=invalid_status, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=b" " * (16 * 1024 + 1), token="valid-token")
        assert status == 413 and json.loads(body)["error"]["code"] == "payload_too_large"
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=b"{malformed", token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        invalid_date = json.dumps({"resource_id": "resource-1", "due_at": "2020-01-01T00:00:00Z"}).encode()
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=invalid_date, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_date"
        invalid_date = json.dumps({"resource_id": "resource-1", "due_at": "2026-02-31T00:00:00Z"}).encode()
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=invalid_date, token="valid-token")
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_date"

        future = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 86400))
        valid_borrow = json.dumps({"resource_id": 123, "due_at": future}).encode()
        MockSupabaseHandler.requests.clear()
        status, _, body = request_json(base_url + "/api/borrow-requests", method="POST", body=valid_borrow, token="valid-token")
        pending_body = json.loads(body)
        assert status == 503 and pending_body["error"]["code"] == "borrow_requests_pending"
        assert "secure Supabase RPC" in pending_body["error"]["message"]
        assert len(MockSupabaseHandler.requests) == 1
        assert MockSupabaseHandler.requests[0][1] == "/auth/v1/user"
        assert not any(entry[0] == "POST" and entry[1].startswith("/rest/v1/borrow_requests")
                       for entry in MockSupabaseHandler.requests)
        assert not any(entry[0] == "GET" and entry[1].startswith("/rest/v1/resources")
                       for entry in MockSupabaseHandler.requests)

        status, _, body = request_json(base_url + "/api/borrow-requests", token="valid-token")
        own_and_owner_requests = json.loads(body)
        assert status == 200 and len(own_and_owner_requests) == 2
        assert own_and_owner_requests[0]["borrower_id"] == "user-123"
        borrow_read = [entry for entry in MockSupabaseHandler.requests if entry[0] == "GET" and "borrow_requests" in entry[1]][-1]
        assert borrow_read[2] == "Bearer valid-token"
        assert "borrower_id=eq." not in borrow_read[1]

        status, _, body = request_json(
            base_url + "/api/borrow-requests/request-1",
            method="PATCH",
            body=b'{"status":"approved"}',
            token="valid-token",
        )
        assert status == 404 and json.loads(body)["error"]["code"] == "not_found"
        assert not any(
            entry[0] in ("PATCH", "PUT") and "borrow_requests" in entry[1]
            for entry in MockSupabaseHandler.requests
        )
        status, _, body = request_json(
            base_url + "/api/borrow-requests/request-1",
            method="DELETE",
            token="valid-token",
        )
        assert status == 404 and json.loads(body)["error"]["code"] == "not_found"
        assert not any(
            entry[0] == "DELETE" and "borrow_requests" in entry[1]
            for entry in MockSupabaseHandler.requests
        )

        # Marketplace endpoints remain closed by default, even when the caller
        # has a valid Auth identity. No database/RPC request is made.
        marketplace_before = len(MockSupabaseHandler.requests)
        status, _, body = request_json(base_url + "/api/marketplace/transfer-requests")
        assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
        status, _, body = request_json(base_url + "/api/marketplace/transfer-requests", token="valid-token")
        assert status == 503 and json.loads(body)["error"]["code"] == "marketplace_disabled"
        assert len(MockSupabaseHandler.requests) == marketplace_before + 1  # Auth verification only for the authorized attempt.

        # Mock-only opt-in tests verify transport contracts. The staging SQL is
        # not deployed or exercised, and no feature flag is changed in .env.
        marketplace_port = available_port()
        marketplace_base = f"http://127.0.0.1:{marketplace_port}"
        marketplace_env = dict(env)
        marketplace_env.update({
            "SERVER_PORT": str(marketplace_port),
            "SUPABASE_MARKETPLACE_ENABLED": "true",
            "SUPABASE_RESOURCE_IMAGES_ENABLED": "true",
            "SUPABASE_RPC_CREATE_BORROW_REQUEST": "false",
            "SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE": "false",
            "SUPABASE_RPC_BORROW_STATUS": "false",
        })
        MockSupabaseHandler.requests.clear()
        marketplace_process = subprocess.Popen(
            [str(executable)], cwd=workdir, env=marketplace_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        wait_for_server(marketplace_process, marketplace_base)
        status, _, body = request_json(marketplace_base + "/api/health")
        features = json.loads(body)["features"]
        assert status == 200 and features["marketplace_enabled"] is True
        assert features["borrow_request_rpc_enabled"] is False
        assert features["atomic_resource_update_rpc_enabled"] is False
        assert features["borrow_status_rpc_enabled"] is False
        assert features["resource_images_enabled"] is True

        status, _, body = request_json(marketplace_base + "/api/marketplace/transfer-requests", token="valid-token")
        assert status == 200 and json.loads(body)[0]["status"] == "pending"
        transfer_read = [entry for entry in MockSupabaseHandler.requests if entry[1].startswith("/rest/v1/resource_transfer_requests")][-1]
        assert transfer_read[2] == "Bearer valid-token" and transfer_read[3] == "sb_publishable_mock_only"

        MockSupabaseHandler.rpc_body = b'[{"id":51,"resource_id":123,"owner_id":"owner-1","requester_id":"user-123","request_type":"sell","status":"pending"}]'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/transfer-requests", method="POST",
            body=b'{"request_type":"sell"}', token="valid-token",
        )
        assert status == 201 and json.loads(body)[0]["request_type"] == "sell"
        create_transfer = [entry for entry in MockSupabaseHandler.requests if entry[1] == "/rest/v1/rpc/create_resource_transfer_request"][-1]
        assert create_transfer[2] == "Bearer valid-token" and create_transfer[3] == "sb_publishable_mock_only"
        assert json.loads(create_transfer[4]) == {"p_resource_id": 123, "p_request_type": "sell"}

        MockSupabaseHandler.status_rpc_body = b'[{"id":51,"resource_id":123,"owner_id":"owner-1","requester_id":"user-123","request_type":"sell","status":"approved"}]'
        status, _, body = request_json(
            marketplace_base + "/api/marketplace/transfer-requests/51/approve",
            method="POST", body=b"{}", token="valid-token",
        )
        assert status == 403 and json.loads(body)["error"]["code"] == "permission_denied"
        for suffix, function in (("approve", "approve_resource_transfer_request"),
                                 ("reject", "reject_resource_transfer_request"),
                                 ("complete-sale", "complete_resource_sale"),
                                 ("complete-donation", "complete_resource_donation")):
            status, _, body = request_json(
                marketplace_base + f"/api/marketplace/transfer-requests/51/{suffix}",
                method="POST", body=b"{}", token="owner-token",
            )
            assert status == 200 and isinstance(json.loads(body), list)
            rpc = [entry for entry in MockSupabaseHandler.requests if entry[1] == f"/rest/v1/rpc/{function}"][-1]
            assert rpc[2] == "Bearer owner-token" and rpc[3] == "sb_publishable_mock_only"
            assert json.loads(rpc[4]) == {"p_request_id": 51}
        status, _, body = request_json(
            marketplace_base + "/api/marketplace/transfer-requests/51/cancel",
            method="POST", body=b"{}", token="valid-token",
        )
        assert status == 200 and isinstance(json.loads(body), list)
        cancel_rpc = [entry for entry in MockSupabaseHandler.requests if entry[1] == "/rest/v1/rpc/cancel_resource_transfer_request"][-1]
        assert cancel_rpc[2] == "Bearer valid-token" and json.loads(cancel_rpc[4]) == {"p_request_id": 51}

        MockSupabaseHandler.rpc_body = b'[{"id":123,"owner_id":"owner-1","listing_mode":"sell","sale_price":80}]'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123", method="PATCH",
            body=b'{"listing_mode":"sell","sale_price":80}', token="owner-token",
        )
        assert status == 200 and json.loads(body)[0]["listing_mode"] == "sell"
        market_update = [entry for entry in MockSupabaseHandler.requests if entry[1] == "/rest/v1/rpc/update_marketplace_resource_atomic"][-1]
        assert market_update[2] == "Bearer owner-token" and market_update[3] == "sb_publishable_mock_only"
        assert not any(entry[0] == "PATCH" and entry[1].startswith("/rest/v1/resources") for entry in MockSupabaseHandler.requests)

        sale_payload = {
            "title": "Used calculator", "category_id": "20", "resource_type": "calculator",
            "availability_status": "available", "listing_mode": "sell", "borrow_price_kind": "free",
            "sale_original_price": 120, "sale_price": 80, "item_condition": "good", "purchase_year": 2022,
        }
        before_writes = len([entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1].startswith("/rest/v1/resources")])
        status, _, body = request_json(
            marketplace_base + "/api/resources", method="POST",
            body=json.dumps({**sale_payload, "sale_price": 121}).encode(), token="valid-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_price"
        status, _, body = request_json(
            marketplace_base + "/api/resources", method="POST",
            body=json.dumps({**sale_payload, "purchase_year": time.gmtime().tm_year + 1}).encode(), token="valid-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_purchase_year"
        status, _, body = request_json(
            marketplace_base + "/api/resources", method="POST",
            body=json.dumps({**sale_payload, "item_condition": "used"}).encode(), token="valid-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_condition"
        assert len([entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1].startswith("/rest/v1/resources")]) == before_writes
        status, _, body = request_json(
            marketplace_base + "/api/resources", method="POST",
            body=json.dumps(sale_payload).encode(), token="valid-token",
        )
        assert status == 201, (status, body)
        created_sale = [entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1].startswith("/rest/v1/resources")][-1]
        assert json.loads(created_sale[4])["owner_id"] == "user-123"

        status, _, body = request_json(marketplace_base + "/api/resources/123/images", token="valid-token")
        assert status == 200 and json.loads(body)[0]["storage_path"] == "user-123/123/photo.jpg"
        valid_images = b'{"images":[{"storage_path":"user-123/123/photo.jpg","alt_text":"Front","sort_order":0}]}'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/images", method="POST", body=valid_images, token="valid-token",
        )
        assert status == 201 and json.loads(body)[0]["id"] == 42, (status, body)
        image_insert = [entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1] == "/rest/v1/rpc/register_resource_images"][-1]
        assert image_insert[2] == "Bearer valid-token" and image_insert[3] == "sb_publishable_mock_only"
        assert json.loads(image_insert[4]) == {"p_resource_id": 123, "p_images": [{"storage_path": "user-123/123/photo.jpg", "alt_text": "Front", "sort_order": 0}]}
        image_posts_before = len([entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1] == "/rest/v1/rpc/register_resource_images"])
        for invalid_image in (
            b'{"images":[{"storage_path":"other-user/123/photo.jpg"}]}',
            b'{"images":[{"storage_path":"user-123/123/photo.exe"}]}',
            b'{"images":[{"storage_path":"user-123/123/photo.jpg","sort_order":10}]}',
        ):
            status, _, body = request_json(
                marketplace_base + "/api/resources/123/images", method="POST", body=invalid_image, token="valid-token",
            )
            assert status == 400 and json.loads(body)["error"]["code"] in ("invalid_image_path", "invalid_image")
        assert len([entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1] == "/rest/v1/rpc/register_resource_images"]) == image_posts_before
        MockSupabaseHandler.image_slots_body = b'[{"id":"existing","sort_order":0}]'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/images", method="POST",
            body=valid_images, token="valid-token",
        )
        assert status == 409 and json.loads(body)["error"]["code"] == "image_order_conflict"
        MockSupabaseHandler.image_slots_body = b'[{"id":"1","sort_order":0},{"id":"2","sort_order":1},{"id":"3","sort_order":2},{"id":"4","sort_order":3},{"id":"5","sort_order":4},{"id":"6","sort_order":5},{"id":"7","sort_order":6},{"id":"8","sort_order":7},{"id":"9","sort_order":8},{"id":"10","sort_order":9}]'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/images", method="POST",
            body=b'{"images":[{"storage_path":"user-123/123/extra.png","sort_order":0}]}', token="valid-token",
        )
        assert status == 409 and json.loads(body)["error"]["code"] == "image_limit"
        MockSupabaseHandler.image_slots_body = b'[]'

        MockSupabaseHandler.image_reorder_body = b'[{"id":10,"sort_order":0},{"id":11,"sort_order":1}]'
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/images/reorder", method="POST",
            body=b'{"image_ids":[10,11]}', token="owner-token",
        )
        assert status == 200 and len(json.loads(body)) == 2
        reorder_call = [entry for entry in MockSupabaseHandler.requests if entry[1] == "/rest/v1/rpc/reorder_resource_images"][-1]
        assert reorder_call[2] == "Bearer owner-token" and reorder_call[3] == "sb_publishable_mock_only"
        assert json.loads(reorder_call[4]) == {"p_resource_id": 123, "p_image_ids": [10, 11]}
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/images/reorder", method="POST",
            body=b'{"image_ids":[10,10]}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_image_order"
        MockSupabaseHandler.image_reorder_body = b'[]'

        metadata_deletes_before = len([entry for entry in MockSupabaseHandler.requests
                                       if entry[0] == "POST" and entry[1] == "/rest/v1/rpc/delete_resource_image_metadata"])
        status, _, body = request_json(
            marketplace_base + "/api/resource-images/42", method="DELETE", token="valid-token",
        )
        assert status == 403 and json.loads(body)["error"]["code"] == "forbidden", (status, body)
        assert len([entry for entry in MockSupabaseHandler.requests
                    if entry[0] == "POST" and entry[1] == "/rest/v1/rpc/delete_resource_image_metadata"]) == metadata_deletes_before

        status, _, body = request_json(marketplace_base + "/api/resource-images/42", method="DELETE", token="owner-token")
        assert status == 204
        image_delete_calls = [entry for entry in MockSupabaseHandler.requests
                              if entry[1] in ("/storage/v1/object/campusshare-resource-images", "/rest/v1/rpc/delete_resource_image_metadata")]
        assert [entry[1] for entry in image_delete_calls[-2:]] == [
            "/storage/v1/object/campusshare-resource-images", "/rest/v1/rpc/delete_resource_image_metadata"
        ]
        storage_delete = image_delete_calls[-2]
        assert storage_delete[2] == "Bearer owner-token" and storage_delete[3] == "sb_publishable_mock_only"
        assert json.loads(storage_delete[4]) == {"prefixes": ["owner-1/123/photo.jpg"]}
        delete_metadata = image_delete_calls[-1]
        assert delete_metadata[2] == "Bearer owner-token" and json.loads(delete_metadata[4]) == {"p_image_id": 42}
        assert not any(entry[0] == "DELETE" and entry[1].startswith("/rest/v1/resource_images") for entry in MockSupabaseHandler.requests)
        status, _, body = request_json(marketplace_base + "/api/resources/123/handover", token="valid-token")
        assert status == 200 and json.loads(body)[0]["pickup_location"] == "Main library"
        handover = b'{"pickup_location":"Main library","meeting_point":"Student center","preferred_pickup_time":"After class","instructions":"Meet by front desk"}'
        status, _, body = request_json(marketplace_base + "/api/resources/123/handover", method="PUT", body=handover, token="owner-token")
        assert status == 200 and json.loads(body)[0]["pickup_location"] == "Main library"
        assert json.loads(body)[0]["meeting_point"] == "Student center"
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/handover", method="PUT",
            body=b'{"pickup_location":"Library"}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_handover"
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/handover", method="PUT",
            body=b'{"pickup_location":"Library","owner_id":"attacker"}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(
            marketplace_base + "/api/resources/123/reports", method="POST",
            body=b'{"reason":"other","details":"Please review"}', token="valid-token",
        )
        assert status == 201 and json.loads(body)[0]["status"] == "pending"
        report_insert = [entry for entry in MockSupabaseHandler.requests if entry[0] == "POST" and entry[1].startswith("/rest/v1/resource_listing_reports")][-1]
        assert report_insert[2] == "Bearer valid-token" and report_insert[3] == "sb_publishable_mock_only"
        assert json.loads(report_insert[4])["reporter_id"] == "user-123"
        status, _, body = request_json(marketplace_base + "/api/marketplace/reports", token="valid-token")
        assert status == 200 and json.loads(body)[0]["reporter_id"] == "user-123"
        status, _, body = request_json(
            marketplace_base + "/api/marketplace/reports/7/review", method="POST",
            body=b'{"outcome":"resolved","notes":"Reviewed"}', token="owner-token",
        )
        assert status == 200 and isinstance(json.loads(body), list)
        review_rpc = [entry for entry in MockSupabaseHandler.requests if entry[1] == "/rest/v1/rpc/review_resource_listing_report"][-1]
        assert review_rpc[2] == "Bearer owner-token" and review_rpc[3] == "sb_publishable_mock_only"
        assert json.loads(review_rpc[4]) == {"p_report_id": 7, "p_outcome": "resolved", "p_notes": "Reviewed"}
        status, _, body = request_json(
            marketplace_base + "/api/marketplace/reports/7/review", method="POST",
            body=b'{"outcome":"banned"}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_report_review"
        assert not any("moderator" in entry[1].lower() for entry in MockSupabaseHandler.requests)

        # Image routes can be enabled on their own while sale/donation and
        # other marketplace endpoints remain disabled.
        image_only_port = available_port()
        image_only_base = f"http://127.0.0.1:{image_only_port}"
        image_only_env = dict(env)
        image_only_env.update({
            "SERVER_PORT": str(image_only_port),
            "SUPABASE_MARKETPLACE_ENABLED": "false",
            "SUPABASE_RESOURCE_IMAGES_ENABLED": "true",
        })
        image_only_process = subprocess.Popen(
            [str(executable)], cwd=workdir, env=image_only_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        wait_for_server(image_only_process, image_only_base)
        status, _, body = request_json(image_only_base + "/api/health")
        image_features = json.loads(body)["features"]
        assert status == 200 and image_features["resource_images_enabled"] is True
        assert image_features["marketplace_enabled"] is False
        status, _, body = request_json(image_only_base + "/api/resources/123/images", token="valid-token")
        assert status == 200 and isinstance(json.loads(body), list)
        status, _, body = request_json(image_only_base + "/api/resources/123/handover", token="valid-token")
        assert status == 503 and json.loads(body)["error"]["code"] == "marketplace_disabled"

        # Exercise feature-flagged RPC paths in a separate process. These checks
        # validate transport against a local mock, not deployed SQL or RLS.
        rpc_port = available_port()
        rpc_base_url = f"http://127.0.0.1:{rpc_port}"
        rpc_env = dict(env)
        rpc_env["SERVER_PORT"] = str(rpc_port)
        rpc_env["SUPABASE_RPC_CREATE_BORROW_REQUEST"] = "true"
        rpc_env["SUPABASE_RPC_ATOMIC_RESOURCE_UPDATE"] = "true"
        rpc_env["SUPABASE_RPC_BORROW_STATUS"] = "true"
        MockSupabaseHandler.requests.clear()
        MockSupabaseHandler.rpc_status = 200
        MockSupabaseHandler.rpc_body = (
            b'[{"id":123,"resource_id":123,"borrower_id":"user-123",'
            b'"requested_at":"2026-01-01T00:00:00Z","due_at":null,'
            b'"returned_at":null,"status":"pending"}]'
        )
        rpc_process = subprocess.Popen(
            [str(executable)], cwd=workdir, env=rpc_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        wait_for_server(rpc_process, rpc_base_url)

        status, _, body = request_json(rpc_base_url + "/api/health")
        health_body = json.loads(body)
        assert status == 200 and health_body["features"]["borrow_request_rpc_enabled"] is True
        assert health_body["features"]["atomic_resource_update_rpc_enabled"] is True

        rpc_payload = json.dumps({"resource_id": 123, "due_at": None}).encode()
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=rpc_payload, token="valid-token",
        )
        assert status == 201 and json.loads(body)[0]["status"] == "pending"
        rpc_calls = [entry for entry in MockSupabaseHandler.requests
                     if entry[1] == "/rest/v1/rpc/create_borrow_request"]
        assert len(rpc_calls) == 1
        assert rpc_calls[0][2] == "Bearer valid-token"
        assert rpc_calls[0][3] == "sb_publishable_mock_only"
        assert json.loads(rpc_calls[0][4]) == {"p_resource_id": 123, "p_due_at": None}
        assert not any(entry[0] == "POST" and entry[1].startswith("/rest/v1/borrow_requests")
                       for entry in MockSupabaseHandler.requests)
        assert not any(entry[0] == "GET" and entry[1].startswith(("/rest/v1/resources", "/rest/v1/borrow_requests"))
                       for entry in MockSupabaseHandler.requests)

        MockSupabaseHandler.rpc_body = (
            b'[{"id":123,"title":"Updated","description":"Notes",'
            b'"category_id":4,"owner_id":"owner-1","resource_type":"book",'
            b'"availability_status":"unavailable","created_at":"2026-01-01T00:00:00Z"}]'
        )
        valid_edits = [
            {"title": "Metadata only"},
            {"availability_status": "unavailable"},
            {"title": "Updated", "description": "Notes", "category_id": "4",
             "resource_type": "book", "availability_status": "unavailable"},
            {"description": None},
            {"category_id": None},
        ]
        for edit in valid_edits:
            status, _, body = request_json(
                rpc_base_url + "/api/resources/123", method="PATCH",
                body=json.dumps(edit).encode(), token="owner-token",
            )
            assert status == 200 and isinstance(json.loads(body), list) and len(json.loads(body)) == 1
            rpc_call = [entry for entry in MockSupabaseHandler.requests
                        if entry[1] == "/rest/v1/rpc/update_resource_atomic"][-1]
            assert rpc_call[2] == "Bearer owner-token"
            assert rpc_call[3] == "sb_publishable_mock_only"
            rpc_params = json.loads(rpc_call[4])
            assert rpc_params["p_resource_id"] == 123
            expected_edit = dict(edit)
            if isinstance(expected_edit.get("category_id"), str):
                expected_edit["category_id"] = int(expected_edit["category_id"])
            assert rpc_params["p_changes"] == expected_edit
        atomic_calls = [entry for entry in MockSupabaseHandler.requests
                        if entry[1] == "/rest/v1/rpc/update_resource_atomic"]
        assert len(atomic_calls) == len(valid_edits)
        assert not any(entry[0] == "PATCH" and entry[1].startswith("/rest/v1/resources")
                       for entry in MockSupabaseHandler.requests)

        # Missing and anonymous sessions stop before the RPC.
        rpc_update_count = len([entry for entry in MockSupabaseHandler.requests
                               if entry[1] == "/rest/v1/rpc/update_resource_atomic"])
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"title":"Missing token"}',
        )
        assert status == 401 and json.loads(body)["error"]["code"] == "unauthorized"
        assert len([entry for entry in MockSupabaseHandler.requests
                    if entry[1] == "/rest/v1/rpc/update_resource_atomic"]) == rpc_update_count
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"title":"Anonymous user"}', token="anonymous-token",
        )
        assert status == 401 and json.loads(body)["error"]["code"] == "auth_rejected"
        assert "private authentication detail" not in body.decode()
        assert len([entry for entry in MockSupabaseHandler.requests
                    if entry[1] == "/rest/v1/rpc/update_resource_atomic"]) == rpc_update_count
        assert not any(entry[0] == "PATCH" and entry[1].startswith("/rest/v1/resources")
                       for entry in MockSupabaseHandler.requests)

        invalid_edits = [
            ("/api/resources/not-an-id", b'{"title":"x"}', "invalid_request"),
            ("/api/resources/123", b'{"owner_id":"attacker"}', "invalid_request"),
            ("/api/resources/123", b'{}', "invalid_request"),
            ("/api/resources/123", b'{"title":"   "}', "invalid_request"),
            ("/api/resources/123", b'{"description":42}', "invalid_request"),
            ("/api/resources/123", b'{"availability_status":"borrowed"}', "invalid_availability_status"),
        ]
        calls_before_invalid = len([entry for entry in MockSupabaseHandler.requests
                                    if entry[1] == "/rest/v1/rpc/update_resource_atomic"])
        for path, edit_body, error_code in invalid_edits:
            status, _, body = request_json(
                rpc_base_url + path, method="PATCH", body=edit_body, token="owner-token",
            )
            assert status == 400 and json.loads(body)["error"]["code"] == error_code
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=json.dumps({"description": "x" * (16 * 1024)}).encode(), token="owner-token",
        )
        assert status == 413 and json.loads(body)["error"]["code"] == "payload_too_large"
        assert len([entry for entry in MockSupabaseHandler.requests
                    if entry[1] == "/rest/v1/rpc/update_resource_atomic"]) == calls_before_invalid

        MockSupabaseHandler.rpc_status = 404
        MockSupabaseHandler.rpc_body = b'{"code":"P0002","message":"Resource not found"}'
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"title":"Missing resource"}', token="owner-token",
        )
        assert status == 404 and json.loads(body)["error"]["code"] == "not_found"

        MockSupabaseHandler.rpc_status = 400
        MockSupabaseHandler.rpc_body = b'{"code":"23503","message":"private category detail"}'
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"category_id":"99999"}', token="owner-token",
        )
        assert status == 400 and "private category detail" not in body.decode()

        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"title":"Spoof attempt"}', token="valid-token",
        )
        assert status == 403 and "private authorization detail" not in body.decode()

        MockSupabaseHandler.rpc_status = 400
        MockSupabaseHandler.rpc_body = b'{"code":"P0001","message":"Approved loan remains active"}'
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"availability_status":"available"}', token="owner-token",
        )
        assert status == 409 and json.loads(body)["error"]["code"] == "conflict"
        assert "Approved loan remains active" not in body.decode()
        MockSupabaseHandler.rpc_status = 200

        MockSupabaseHandler.rpc_body = b"not-json"
        status, _, body = request_json(
            rpc_base_url + "/api/resources/123", method="PATCH",
            body=b'{"title":"Atomic response parse"}', token="owner-token",
        )
        assert status == 502 and json.loads(body)["error"]["code"] == "invalid_upstream_response"
        assert not any(entry[0] == "PATCH" and entry[1].startswith("/rest/v1/resources")
                       for entry in MockSupabaseHandler.requests)
        MockSupabaseHandler.rpc_body = b'[{"id":123,"resource_id":123,"borrower_id":"user-123",' \
            b'"requested_at":"2026-01-01T00:00:00Z","due_at":null,"returned_at":null,"status":"pending"}]'

        rpc_call_count = len(rpc_calls)
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=rpc_payload,
        )
        assert status == 401 and len([entry for entry in MockSupabaseHandler.requests
                                      if entry[1] == "/rest/v1/rpc/create_borrow_request"]) == rpc_call_count
        invalid_rpc_payload = json.dumps({"resource_id": "resource-1", "due_at": None}).encode()
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=invalid_rpc_payload, token="valid-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"

        rpc_calls_before_status_attempts = len([entry for entry in MockSupabaseHandler.requests
                                                if entry[1].startswith("/rest/v1/rpc/")])
        assert health_body["features"]["borrow_status_rpc_enabled"] is True
        for action, function_name, expected_status in (
            ("approve", "approve_borrow_request", "approved"),
            ("reject", "reject_borrow_request", "rejected"),
            ("return", "return_borrowed_resource", "returned"),
        ):
            MockSupabaseHandler.status_rpc_body = json.dumps([{
                "id": 123, "resource_id": 123, "borrower_id": "user-123",
                "requested_at": "2026-01-01T00:00:00Z", "due_at": None,
                "returned_at": "2026-01-02T00:00:00Z" if action == "return" else None,
                "status": expected_status,
            }]).encode()
            status, _, body = request_json(
                rpc_base_url + f"/api/borrow-requests/123/{action}", method="POST",
                body=b'{"due_at":null}' if action == "approve" else b'{}', token="owner-token",
            )
            assert status == 200 and json.loads(body)[0]["status"] == expected_status
            calls = [entry for entry in MockSupabaseHandler.requests
                     if entry[1] == f"/rest/v1/rpc/{function_name}"]
            assert calls and calls[-1][2] == "Bearer owner-token"
            assert calls[-1][3] == "sb_publishable_mock_only"
            params = json.loads(calls[-1][4])
            assert params["p_request_id"] == 123
            assert params.get("p_due_at") is None if action == "approve" else "p_due_at" not in params

        status_calls_before = len([entry for entry in MockSupabaseHandler.requests
                                   if entry[1].startswith("/rest/v1/rpc/")])
        for action in ("approve", "reject", "return"):
            status, _, body = request_json(
                rpc_base_url + f"/api/borrow-requests/123/{action}", method="POST",
                body=b"{}", token="valid-token",
            )
            assert status == 403 and json.loads(body)["error"]["code"] == "permission_denied", (status, body)
            assert b"private authorization detail" not in body
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/approve", method="POST",
            body=b"{}", token="anonymous-token",
        )
        assert status == 401 and json.loads(body)["error"]["code"] == "auth_rejected"
        assert b"private authentication detail" not in body
        assert len([entry for entry in MockSupabaseHandler.requests
                    if entry[1].startswith("/rest/v1/rpc/")]) == status_calls_before + 3

        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/invalid/approve", method="POST",
            body=b"{}", token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/approve", method="POST",
            body=b'{"status":"returned"}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/reject", method="POST",
            body=b'{"due_at":null}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_request"
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/approve", method="POST",
            body=b'{"due_at":"not-a-date"}', token="owner-token",
        )
        assert status == 400 and json.loads(body)["error"]["code"] == "invalid_date"

        MockSupabaseHandler.rpc_status = 400
        MockSupabaseHandler.rpc_body = b'{"code":"P0001","message":"private state detail"}'
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/approve", method="POST",
            body=b'{}', token="owner-token",
        )
        assert status == 409 and json.loads(body)["error"]["code"] == "conflict"
        assert b"private state detail" not in body
        MockSupabaseHandler.rpc_status = 200
        MockSupabaseHandler.status_rpc_body = b"not-json"
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/return", method="POST",
            body=b"{}", token="owner-token",
        )
        assert status == 502 and json.loads(body)["error"]["code"] == "invalid_upstream_response"
        MockSupabaseHandler.status_rpc_body = b'[{"id":123,"resource_id":123,"borrower_id":"user-123","status":"approved"}]'
        MockSupabaseHandler.rpc_delay_seconds = 16
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests/123/approve", method="POST",
            body=b"{}", token="owner-token", timeout=20,
        )
        assert status == 502 and json.loads(body)["error"]["code"] == "upstream_error"
        MockSupabaseHandler.rpc_delay_seconds = 0
        assert not any(entry[0] in ("PATCH", "PUT", "DELETE") and "borrow_requests" in entry[1]
                       for entry in MockSupabaseHandler.requests)

        MockSupabaseHandler.rpc_status = 400
        MockSupabaseHandler.rpc_body = b'{"code":"23505","message":"private constraint detail"}'
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=rpc_payload, token="valid-token",
        )
        assert status == 409 and "private constraint detail" not in body.decode()

        MockSupabaseHandler.rpc_status = 200
        MockSupabaseHandler.rpc_body = b"not-json"
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=rpc_payload, token="valid-token",
        )
        assert status == 502 and json.loads(body)["error"]["code"] == "invalid_upstream_response"

        MockSupabaseHandler.rpc_body = b'[{"id":123,"resource_id":123,"borrower_id":"user-123",' \
            b'"requested_at":"2026-01-01T00:00:00Z","due_at":null,"returned_at":null,"status":"pending"}]'
        MockSupabaseHandler.rpc_delay_seconds = 16
        status, _, body = request_json(
            rpc_base_url + "/api/borrow-requests", method="POST",
            body=rpc_payload, token="valid-token", timeout=20,
        )
        assert status == 502 and json.loads(body)["error"]["code"] == "upstream_error"
        MockSupabaseHandler.rpc_delay_seconds = 0
    finally:
        if image_only_process is not None and image_only_process.poll() is None:
            image_only_process.terminate()
            image_only_process.communicate(timeout=5)
        if marketplace_process is not None and marketplace_process.poll() is None:
            marketplace_process.terminate()
            marketplace_process.communicate(timeout=5)
        if rpc_process is not None and rpc_process.poll() is None:
            rpc_process.terminate()
        if rpc_process is not None:
            rpc_process.wait(timeout=5)
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
        backend_stdout, backend_stderr = process.communicate(timeout=5)
        backend_logs = backend_stdout + backend_stderr
        for sensitive_mock_value in (
            "valid-token", "invalid-token", "expired-token", "owner-token",
            "other-user-token", "sb_publishable_mock_only",
        ):
            assert sensitive_mock_value not in backend_logs
        assert "Supabase Auth rejected the token or API key (HTTP 401)" in backend_logs
        mock.shutdown()
        mock.server_close()
        mock_thread.join(timeout=2)

    print("PASS: config and flag validation; service-key rejection; API_KEY alias/conflict checks; mocked Auth; separate API-key/Bearer forwarding; RPC-only borrow and status flows; marketplace disabled-by-default; transfer RPC authorization/forwarding; atomic marketplace edits; image metadata path/type/order validation; private handover validation; listing report identity derivation; no moderator or direct-write fallback; malformed responses; timeout/no-fallback; CORS/OPTIONS")


if __name__ == "__main__":
    run()
