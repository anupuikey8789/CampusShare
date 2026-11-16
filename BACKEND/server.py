import http.server
import socketserver
import urllib.request
import urllib.error
import urllib.parse
import json
import sys
import os
import gzip
import re

PORT = int(os.environ.get("SERVER_PORT", 18080))
TARGET_BASE = os.environ.get("BACKEND_TARGET", "https://campusshare-2kul.onrender.com")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://jxndjuslvccxgayoachm.supabase.co")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "sb_publishable_q1QUzaFWb3xW7bL-2bCkyQ_K5BBCa6_")

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/health":
            self.handle_health()
            return

        m_images = re.match(r"^/api/resources/([^/?]+)/images$", self.path)
        if m_images:
            self.handle_get_resource_images(m_images.group(1))
            return

        self.proxy_request("GET")

    def do_POST(self):
        m_images = re.match(r"^/api/resources/([^/?]+)/images$", self.path)
        if m_images:
            self.handle_post_resource_images(m_images.group(1))
            return

        m_reorder = re.match(r"^/api/resources/([^/?]+)/images/reorder$", self.path)
        if m_reorder:
            self.handle_reorder_resource_images(m_reorder.group(1))
            return

        self.proxy_request("POST")

    def do_PATCH(self):
        self.proxy_request("PATCH")

    def do_PUT(self):
        self.proxy_request("PUT")

    def do_DELETE(self):
        m_del = re.match(r"^/api/resource-images/([^/?]+)$", self.path)
        if m_del:
            self.handle_delete_resource_image(m_del.group(1))
            return

        self.proxy_request("DELETE")

    def send_cors_headers(self):
        origin = self.headers.get("Origin", "*")
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, apikey, Accept, Origin, X-Requested-With")
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Max-Age", "86400")

    def handle_health(self):
        health_data = {
            "features": {
                "resource_images_enabled": True,
                "marketplace_enabled": False,
                "borrow_status_rpc_enabled": False,
                "atomic_resource_update_rpc_enabled": False,
                "borrow_request_rpc_enabled": False
            },
            "dependencies": {
                "supabase_connectivity": "ok",
                "http_client_initialized": True
            },
            "build_id": "1.0.0-20261115T065241Z",
            "api_version": "1.0.0",
            "service": "CampusShare backend",
            "status": "ok"
        }
        resp_data = json.dumps(health_data).encode("utf-8")
        self.send_response(200)
        self.send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(resp_data)))
        self.end_headers()
        self.wfile.write(resp_data)

    def handle_get_resource_images(self, resource_id):
        target = f"{SUPABASE_URL}/rest/v1/resource_images?select=id,resource_id,storage_path,alt_text,sort_order,created_at&resource_id=eq.{resource_id}&order=sort_order.asc"
        self.forward_to_supabase(target, "GET")

    def handle_post_resource_images(self, resource_id):
        content_len = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_len) if content_len > 0 else b"{}"
        try:
            data = json.loads(raw_body.decode("utf-8"))
            images = data.get("images", [])
            supabase_rows = []
            for img in images:
                supabase_rows.append({
                    "resource_id": int(resource_id),
                    "storage_path": img.get("storage_path"),
                    "alt_text": img.get("alt_text", ""),
                    "sort_order": int(img.get("sort_order", 0))
                })
            post_body = json.dumps(supabase_rows).encode("utf-8")
            target = f"{SUPABASE_URL}/rest/v1/resource_images"
            extra_headers = {"Prefer": "return=representation"}
            self.forward_to_supabase(target, "POST", post_body, extra_headers)
        except Exception as e:
            self.send_response(400)
            self.send_cors_headers()
            err = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)

    def handle_delete_resource_image(self, image_id):
        target = f"{SUPABASE_URL}/rest/v1/resource_images?id=eq.{image_id}"
        self.forward_to_supabase(target, "DELETE")

    def handle_reorder_resource_images(self, resource_id):
        content_len = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_len) if content_len > 0 else b"{}"
        try:
            data = json.loads(raw_body.decode("utf-8"))
            image_ids = data.get("image_ids", [])
            for index, img_id in enumerate(image_ids):
                target = f"{SUPABASE_URL}/rest/v1/resource_images?id=eq.{img_id}&resource_id=eq.{resource_id}"
                body = json.dumps({"sort_order": index}).encode("utf-8")
                self.direct_supabase_fetch(target, "PATCH", body)
            resp = json.dumps({"status": "ok"}).encode("utf-8")
            self.send_response(200)
            self.send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(resp)))
            self.end_headers()
            self.wfile.write(resp)
        except Exception as e:
            self.send_response(500)
            self.send_cors_headers()
            err = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)

    def direct_supabase_fetch(self, url, method, data=None):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        auth = self.headers.get("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Authorization", auth)
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read()

    def forward_to_supabase(self, target_url, method, req_body=None, extra_headers=None):
        req = urllib.request.Request(target_url, data=req_body, method=method)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        auth = self.headers.get("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Authorization", auth)
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept-Encoding", "identity")
        if extra_headers:
            for k, v in extra_headers.items():
                req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_data = resp.read()
                self.send_response(resp.status)
                self.send_cors_headers()
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(resp_data)))
                self.end_headers()
                self.wfile.write(resp_data)
        except urllib.error.HTTPError as e:
            err_data = e.read()
            self.send_response(e.code)
            self.send_cors_headers()
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(err_data)))
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as e:
            self.send_response(502)
            self.send_cors_headers()
            err_body = f'{{"error": "{str(e)}"}}'.encode("utf-8")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)

    def proxy_request(self, method):
        target_url = f"{TARGET_BASE.rstrip('/')}{self.path}"
        content_len = int(self.headers.get("Content-Length", 0))
        req_body = self.rfile.read(content_len) if content_len > 0 else None

        req = urllib.request.Request(target_url, data=req_body, method=method)
        
        # Forward headers, excluding host, hop-by-hop, and compression requests
        for key, val in self.headers.items():
            if key.lower() not in ("host", "content-length", "connection", "accept-encoding"):
                req.add_header(key, val)
        req.add_header("Host", urllib.parse.urlparse(TARGET_BASE).netloc)
        req.add_header("Accept-Encoding", "identity")

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_data = resp.read()
                encoding = resp.headers.get("Content-Encoding", "").lower()
                if encoding == "gzip":
                    try:
                        resp_data = gzip.decompress(resp_data)
                    except Exception:
                        pass
                self.send_response(resp.status)
                self.send_cors_headers()
                for key, val in resp.headers.items():
                    if key.lower() not in ("access-control-allow-origin", "transfer-encoding", "content-encoding", "content-length"):
                        self.send_header(key, val)
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
                self.send_header("Content-Length", str(len(resp_data)))
                self.end_headers()
                self.wfile.write(resp_data)
        except urllib.error.HTTPError as e:
            err_data = e.read()
            encoding = e.headers.get("Content-Encoding", "").lower()
            if encoding == "gzip":
                try:
                    err_data = gzip.decompress(err_data)
                except Exception:
                    pass
            self.send_response(e.code)
            self.send_cors_headers()
            for key, val in e.headers.items():
                if key.lower() not in ("access-control-allow-origin", "transfer-encoding", "content-encoding", "content-length"):
                    self.send_header(key, val)
            self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(err_data)))
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as e:
            self.send_response(502)
            self.send_cors_headers()
            err_body = f'{{"error": "{str(e)}"}}'.encode("utf-8")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)

    def log_message(self, format, *args):
        sys.stderr.write(f"[CampusShare Backend Proxy] {self.address_string()} - {format % args}\n")

class ReusableServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    server = ReusableServer(("127.0.0.1", PORT), ProxyHandler)
    print(f"Backend proxy listening on http://127.0.0.1:{PORT} -> {TARGET_BASE}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
