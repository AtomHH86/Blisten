#!/usr/bin/env python3
"""Serve a local Web preview with byte ranges for browser audio seeking."""
import argparse
import functools
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import mimetypes
import os
from pathlib import Path
import re
import stat
from urllib.parse import unquote, urlsplit


class PreviewHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, directory, **kwargs):
        self.directory = directory
        super().__init__(*args, **kwargs)

    def _open_file(self):
        path = unquote(urlsplit(self.path).path, errors='strict')
        parts = [part for part in path.split('/') if part not in ('', '.')]
        if not path.startswith('/') or '..' in parts or '\\' in path or '\0' in path:
            raise FileNotFoundError()
        if not parts or path.endswith('/'):
            parts.append('index.html')
        # Walk beneath the root using descriptors; never follow symlinks, even
        # if a path component changes between checking and opening the file.
        directory = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            for part in parts[:-1]:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                dir_fd=directory)
                os.close(directory)
                directory = child
            descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                 dir_fd=directory)
        finally:
            os.close(directory)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            os.close(descriptor)
            raise FileNotFoundError()
        return os.fdopen(descriptor, 'rb'), metadata, parts[-1]

    def do_GET(self):
        self._serve(body=True)

    def do_HEAD(self):
        self._serve(body=False)

    def _serve(self, *, body):
        try:
            stream, metadata, name = self._open_file()
        except (OSError, ValueError, UnicodeError):
            self.send_error(404)
            return
        with stream:
            size = metadata.st_size
            start, end = 0, size - 1
            # Range is only defined for GET. If-Range falls back to the full
            # representation; this preview does not issue entity validators.
            requested = self.headers.get('Range') if body and not self.headers.get('If-Range') else None
            if requested is not None:
                try:
                    match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested.strip())
                    if not match or not any(match.groups()) or not size:
                        raise ValueError()
                    first, last = match.groups()
                    if first:
                        start = int(first)
                        end = min(int(last), size - 1) if last else size - 1
                    else:
                        suffix = int(last)
                        if suffix <= 0:
                            raise ValueError()
                        start = max(0, size - suffix)
                    if start > end or start >= size:
                        raise ValueError()
                except ValueError:
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{size}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
            self.send_response(206 if requested is not None else 200)
            self.send_header('Content-Type', mimetypes.guess_type(name)[0] or 'application/octet-stream')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            self.send_header('Cache-Control', 'no-store')
            if requested is not None:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            if body:
                stream.seek(start)
                remaining = end - start + 1
                try:
                    while remaining:
                        chunk = stream.read(min(65536, remaining))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                except ConnectionError:
                    pass  # Browsers cancel an earlier request when seeking.


def create_server(directory, port):
    directory = Path(directory).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError('Preview directory must be a directory')
    handler = functools.partial(PreviewHandler, directory=directory)
    return ThreadingHTTPServer(('127.0.0.1', port), handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('build/web'))
    parser.add_argument('--port', type=int, default=8768)
    args = parser.parse_args()
    with create_server(args.directory, args.port) as server:
        print(f'Preview: http://127.0.0.1:{server.server_port}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
