#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MiniMax-H3 分镜批量脚本的 mock 服务端（仅用于冒烟测试，不做真实生成）。

同时兼容两套后端协议，方便复用同一份测试驱动去验证 scripts/ 下的客户端脚本：

  sglang（异步 JSON body）
    GET  /health                      -> 200
    POST /v1/videos                   -> 200 {"id": "jobN"}，并把收到的完整 body
                                          以 JSON Lines 追加写入 --log 指定的文件
    GET  /v1/videos/{id}              -> 200 {"status": "completed"}
    GET  /v1/videos/{id}/content      -> 200 假字节（供脚本落盘校验）

  vLLM（同步 multipart）
    POST /v1/videos/sync              -> 200 假字节

用法：
  python3 mock_video_server.py --port 30010 --log /tmp/posts.jsonl
"""
import argparse
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

FAKE_VIDEO = b"FAKE-MP4-BYTES-FOR-TEST-ONLY"
JOB_ID = re.compile(r"^/v1/videos/([^/]+)$")
JOB_CONTENT = re.compile(r"^/v1/videos/([^/]+)/content$")

_counter_lock = threading.Lock()
_counter = 0


def next_job_id():
    global _counter
    with _counter_lock:
        _counter += 1
        return "mockjob_%d" % _counter


class Handler(BaseHTTPRequestHandler):
    log_path = "/tmp/posts.jsonl"

    def _reply(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._reply(200, b"ok", "text/plain")
        elif JOB_CONTENT.match(self.path):
            self._reply(200, FAKE_VIDEO, "video/mp4")
        elif JOB_ID.match(self.path):
            self._reply(200, json.dumps({"status": "completed"}).encode())
        else:
            self._reply(404, b'{"error":"not found"}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""

        # vLLM 同步：multipart 表单，直接返回假视频字节
        if self.path == "/v1/videos/sync":
            self._reply(200, FAKE_VIDEO, "video/mp4")
            return

        # sglang 异步：JSON body，完整记录一份供测试断言
        try:
            body = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as exc:
            self._reply(400, json.dumps({"error": "bad json: %s" % exc}).encode())
            return

        with open(self.log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(body, ensure_ascii=False) + "\n")

        self._reply(200, json.dumps({"id": next_job_id()}).encode())

    def log_message(self, *args):  # 静默访问日志，避免干扰测试输出
        pass


def main():
    ap = argparse.ArgumentParser(description="MiniMax-H3 batch-script mock server")
    ap.add_argument("--port", type=int, default=30010)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--log", default="/tmp/posts.jsonl", help="JSONL 请求记录文件")
    args = ap.parse_args()

    Handler.log_path = args.log
    open(args.log, "w", encoding="utf-8").close()

    httpd = HTTPServer((args.host, args.port), Handler)
    print("mock server listening on http://%s:%d  log=%s" % (args.host, args.port, args.log), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
