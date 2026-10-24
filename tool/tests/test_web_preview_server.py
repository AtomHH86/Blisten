"""Real loopback HTTP checks for the static Web preview server."""
import http.client
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'serve-web.py'
spec = importlib.util.spec_from_file_location('web_preview', SOURCE)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class WebPreviewServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        parent = Path(cls.temporary.name)
        cls.root = parent / 'web'
        cls.root.mkdir()
        cls.payload = bytes(range(256)) * 1024
        (cls.root / 'audio.wav').write_bytes(cls.payload)
        (cls.root / 'index.html').write_text('<title>Blisten</title>')
        (cls.root / 'empty.wav').touch()
        (cls.root / 'nested').mkdir()
        (cls.root / 'nested' / 'index.html').write_text('nested')
        (cls.root / 'unlisted').mkdir()
        (parent / 'secret.txt').write_text('PRIVATE PREVIEW FIXTURE')
        (cls.root / 'outside.txt').symlink_to(parent / 'secret.txt')
        (cls.root / 'outside-dir').symlink_to(parent, target_is_directory=True)
        cls.server = preview.create_server(cls.root, 0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temporary.cleanup()

    def request(self, path='/audio.wav', method='GET', headers=None):
        connection = http.client.HTTPConnection(
            *self.server.server_address, timeout=3)
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_bind_is_loopback_and_full_file_is_intact(self):
        self.assertEqual('127.0.0.1', self.server.server_address[0])
        status, headers, body = self.request()
        self.assertEqual(200, status)
        self.assertEqual(self.payload, body)
        self.assertEqual(str(len(body)), headers['Content-Length'])
        self.assertEqual('bytes', headers.get('Accept-Ranges'))

    def test_closed_range_returns_only_requested_bytes(self):
        status, headers, body = self.request(headers={'Range': 'bytes=44-103'})
        self.assertEqual(206, status)
        self.assertEqual(self.payload[44:104], body)
        self.assertEqual('60', headers['Content-Length'])
        self.assertEqual(f'bytes 44-103/{len(self.payload)}', headers['Content-Range'])

    def test_open_and_suffix_ranges(self):
        cases = [('bytes=262140-', 262140), ('bytes=-4', 262140),
                 ('bytes=262140-999999', 262140), ('bytes=-999999', 0)]
        for value, start in cases:
            with self.subTest(value=value):
                status, headers, body = self.request(headers={'Range': value})
                self.assertEqual(206, status)
                self.assertEqual(self.payload[start:], body)
                self.assertEqual(str(len(body)), headers['Content-Length'])

    def test_unsatisfied_and_invalid_ranges_do_not_send_audio(self):
        for value in ['bytes=262144-', 'bytes=50-40', 'bytes=-0',
                      'bytes=', 'bytes=0-1,3-4', 'bytes=nope']:
            with self.subTest(value=value):
                status, headers, body = self.request(headers={'Range': value})
                self.assertEqual(416, status)
                self.assertEqual(f'bytes */{len(self.payload)}', headers['Content-Range'])
                self.assertEqual(b'', body)

    def test_empty_file_range_is_unsatisfied(self):
        status, headers, body = self.request('/empty.wav', headers={'Range': 'bytes=0-'})
        self.assertEqual(416, status)
        self.assertEqual('bytes */0', headers['Content-Range'])
        self.assertEqual(b'', body)

    def test_head_has_full_length_without_body(self):
        status, headers, body = self.request(method='HEAD', headers={'Range': 'bytes=44-103'})
        self.assertEqual(200, status)
        self.assertEqual(str(len(self.payload)), headers['Content-Length'])
        self.assertEqual(b'', body)

    def test_index_query_and_missing_file(self):
        self.assertEqual(b'<title>Blisten</title>', self.request('/?v=1')[2])
        self.assertEqual(b'nested', self.request('/nested/')[2])
        self.assertEqual(404, self.request('/missing')[0])
        self.assertEqual(404, self.request('/unlisted/')[0])

    def test_traversal_and_symlinks_cannot_read_outside(self):
        for path in ['/../secret.txt', '/%2e%2e/secret.txt',
                     '/nested/%2e%2e/%2e%2e/secret.txt', '/outside.txt',
                     '/outside-dir/secret.txt', '/%00', '/nested%5c..%5csecret.txt']:
            with self.subTest(path=path):
                status, _, body = self.request(path)
                self.assertEqual(404, status)
                self.assertNotIn(b'PRIVATE PREVIEW FIXTURE', body)


if __name__ == '__main__':
    unittest.main()
