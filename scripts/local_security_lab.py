#!/usr/bin/env python3
"""Loopback-only intentionally vulnerable HTTP target for authorized tool tests."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import argparse
import sqlite3


DB = sqlite3.connect(":memory:", check_same_thread=False)
DB.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
DB.executemany(
    "INSERT INTO items (id, name) VALUES (?, ?)",
    [(1, "field notebook"), (2, "usb analyzer"), (3, "test radio")],
)
DB.commit()


class LabHandler(BaseHTTPRequestHandler):
    server_version = "X1SLocalLab/1.0"
    sys_version = ""

    def send_body(self, status: int, body: str, content_type: str = "text/html; charset=utf-8") -> None:
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/":
            self.send_body(
                200,
                "<h1>X1S local security lab</h1>"
                "<p>Intentionally vulnerable and bound to loopback only.</p>"
                "<a href='/admin/'>Admin</a> <a href='/item?id=1'>Item</a>",
            )
            return

        if parsed.path == "/robots.txt":
            self.send_body(200, "User-agent: *\nDisallow: /admin/\n", "text/plain; charset=utf-8")
            return

        if parsed.path == "/admin/":
            self.send_body(200, "<h1>Local lab admin placeholder</h1>")
            return

        if parsed.path == "/item":
            item_id = parse_qs(parsed.query).get("id", ["1"])[0]
            # Deliberately unsafe for this loopback-only SQLmap validation target.
            query = f"SELECT name FROM items WHERE id = {item_id}"
            try:
                rows = DB.execute(query).fetchall()
                body = " | ".join(row[0] for row in rows) if rows else "No item found"
                self.send_body(200, f"<p>Item result: {body}</p>")
            except sqlite3.Error as exc:
                self.send_body(500, f"Database error: {exc}", "text/plain; charset=utf-8")
            return

        self.send_body(404, "Not found", "text/plain; charset=utf-8")

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8008)
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost"}:
        raise SystemExit("This lab must remain bound to loopback.")
    server = ThreadingHTTPServer((args.host, args.port), LabHandler)
    print(f"Listening on http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
