"""Behavioral regressions for the authenticated compiled-server load gate."""

import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import server_sync_load_runtime as load


class ModelClient:
    def __init__(self, fault=None):
        self.fault = fault
        self.lock = threading.Lock()
        self.saved = None

    def request(self, method, route, token=None, body=None):
        with self.lock:
            if self.saved is not None and self.fault != 'two-winners':
                conflict = {'error': 'sync_conflict', 'currentRevision': 1,
                            'checksum': self.saved['checksum']}
                if self.fault == 'wrong-conflict':
                    conflict['currentRevision'] = 0
                return 409, conflict, {}
            self.saved = {'snapshot': body['snapshot'], 'revision': 1,
                          'checksum': load.digest(body['snapshot']),
                          'updatedByDevice': body['deviceId']}
            return 200, self.saved, {}

    def expect(self, method, route, **unused):
        value = copy.deepcopy(self.saved)
        if self.fault == 'wrong-account':
            value['snapshot']['name'] = 'another-account'
        if self.fault == 'lost-write':
            value['revision'] = 0
        if self.fault == 'wrong-checksum':
            value['checksum'] = 'wrong'
        if route.endswith('/metadata') and self.fault != 'leaked-payload':
            value.pop('snapshot')
        return value


class SyncBehaviorTest(unittest.TestCase):
    def test_two_devices_read_back_the_exact_single_winner(self):
        result = load.account_cycle(ModelClient(), 'account-a', ['one', 'two'], 0, 0, 3)
        self.assertEqual(result['revision'], 1)
        self.assertEqual(len(result['snapshot']['tracks']), 3)
        self.assertTrue(result['snapshot']['name'].startswith('account-a-'))

    def test_semantic_failures_do_not_become_successful_load_evidence(self):
        for fault in ('two-winners', 'wrong-conflict', 'wrong-account', 'lost-write',
                      'wrong-checksum', 'leaked-payload'):
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                load.account_cycle(ModelClient(fault), 'account-a', ['one', 'two'], 0, 0, 3)

    def test_snapshot_checksum_uses_utf8_compact_json(self):
        self.assertEqual(load.encode({'title': '\u0130stanbul'}), b'{"title":"\xc4\xb0stanbul"}')
        self.assertNotEqual(load.digest(load.snapshot('a', 0, 0, 2)),
                            load.digest(load.snapshot('b', 0, 0, 2)))

    def test_rate_limit_must_reject_and_leave_other_account_available(self):
        calls = []

        class RateClient:
            def request(self, *args, **kwargs):
                return 429, {'error': 'rate_limited'}, {'Retry-After': '60'}

            def expect(self, *args, **kwargs):
                calls.append((args, kwargs))

        load.verify_rate_limit(RateClient(), 'limited', 'same-account', 'other')
        self.assertEqual(calls[0][1], {'status': 429, 'token': 'same-account'})
        self.assertEqual(calls[1][1]['token'], 'other')
        self.assertEqual(calls[2][0][1], '/health')
        for status, headers in ((200, {}), (503, {}), (429, {}), (429, {'Retry-After': '0'})):
            with self.subTest(status=status, headers=headers), patch.object(
                    RateClient, 'request', return_value=(status, {'error': 'rate_limited'}, headers)):
                with self.assertRaises(AssertionError):
                    load.verify_rate_limit(RateClient(), 'limited', 'same-account', 'other')


class HttpClientTest(unittest.TestCase):
    def setUp(self):
        self.status, self.body = 200, b'{"revision":1}'
        self.delay, self.extra_length = 0, 0
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(outer.status)
                self.send_header('Content-Length', str(len(outer.body) + outer.extra_length))
                self.send_header('Location', 'http://invalid.example/credential-target')
                self.end_headers()
                try:
                    if outer.delay:
                        for byte in outer.body:
                            self.wfile.write(bytes([byte]))
                            self.wfile.flush()
                            time.sleep(outer.delay)
                    else:
                        self.wfile.write(outer.body)
                except OSError:
                    pass

            def log_message(self, *unused):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.client = load.Client(SimpleNamespace(port=self.server.server_port))

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_reads_content_and_retains_only_credential_free_metrics(self):
        self.assertEqual(self.client.expect('GET', load.ROUTE, token='private-token'), {'revision': 1})
        stats = load.summarize(self.client.measurements)
        self.assertEqual(stats['status_counts'], {'200': 1})
        self.assertEqual(stats['received_bytes'], len(self.body))
        self.assertNotIn('private-token', json.dumps(self.client.measurements))

    def test_redirect_is_not_followed_with_bearer_credentials(self):
        self.status = 302
        with self.assertRaisesRegex(AssertionError, 'received 302'):
            self.client.expect('GET', load.ROUTE, token='private-token')
        self.assertEqual(len(self.client.measurements), 1)

    def test_oversized_and_malformed_responses_fail_without_retaining_body(self):
        for body in (b'{"secret":"private-token"}', b'not-json-private-token'):
            self.body = body
            limit = 16 if body.startswith(b'{') else 100
            with self.subTest(body=body), patch.object(load, 'MAX_RESPONSE_BYTES', limit):
                with self.assertRaises(AssertionError) as result:
                    self.client.expect('GET', load.ROUTE, token='private-token')
                self.assertNotIn('private-token', str(result.exception))
        self.assertEqual(load.summarize(self.client.measurements)['transport_failures'], 2)

    def test_truncated_content_length_is_rejected_even_for_valid_json(self):
        self.extra_length = 10
        with self.assertRaises(AssertionError):
            self.client.expect('GET', load.ROUTE)
        self.assertEqual(load.summarize(self.client.measurements)['transport_failures'], 1)

    def test_trickling_response_cannot_reset_the_total_deadline(self):
        self.delay = 0.03
        with patch.object(load, 'REQUEST_TIMEOUT', 0.1), self.assertRaises(AssertionError):
            self.client.expect('GET', load.ROUTE)
        self.assertEqual(load.summarize(self.client.measurements)['transport_failures'], 1)


class RunnerTest(unittest.TestCase):
    def test_rejects_unbounded_inputs_before_launching_a_service(self):
        for options in ({'seconds': 0}, {'seconds': 601}, {'accounts': 1}, {'accounts': 9},
                        {'tracks': 0}, {'tracks': 10001}):
            with self.subTest(options=options), self.assertRaises(AssertionError):
                load.run(Path('missing'), Path('missing-evidence'), **options)

    def test_refuses_to_overwrite_existing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(FileExistsError):
                load.run(Path(__file__), directory)
            self.assertEqual(list(directory.iterdir()), [])

    def test_startup_failure_writes_failure_not_a_pass_and_hides_exception_details(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary) / 'run'
            with patch.object(load.Server, '__enter__', side_effect=OSError('private-token')):
                self.assertEqual(load.run(Path(__file__), evidence, seconds=5), 1)
            raw = (evidence / 'authenticated-sync-load.json').read_text()
            report = json.loads(raw)
            self.assertEqual(report['result'], 'failed')
            self.assertEqual(report['checks'], [])
            self.assertEqual(report['all_requests']['requests'], 0)
            self.assertNotIn('private-token', raw)
            self.assertTrue(report['executable_sha256'])
            self.assertIn('services/server/bin/server.dart', report['input_sha256'])

    def test_ci_and_release_execute_the_gate_and_keep_evidence(self):
        ci = (load.ROOT / '.github/workflows/aethertune-ci.yml').read_text()
        release = (load.ROOT / '.github/workflows/aethertune-release.yml').read_text()
        for workflow in (ci, release):
            self.assertIn('scripts/ci/server_sync_load_runtime.py', workflow)
            step = workflow.split('- name: Run authenticated sync load and restart acceptance', 1)[1].split('- name:', 1)[0]
            self.assertNotIn('continue-on-error', step)
            self.assertIn('SOURCE_COMMIT_SHA', step)
        self.assertIn('scripts/ci/test_server_sync_load_runtime.py', ci)
        self.assertIn('--evidence build/server-load/authenticated', ci)
        self.assertIn('build/server-sync-load-${{ matrix.label }}/', release)

    def test_pr_ci_executes_the_compiled_gate_on_windows_and_macos(self):
        ci = (load.ROOT / '.github/workflows/aethertune-ci.yml').read_text()
        desktop = ci.split('\n  desktop:', 1)[1].split('\n  server:', 1)[0]
        build = desktop.split('- name: Compile native server for sync acceptance', 1)[1].split('- name:', 1)[0]
        run = desktop.split('- name: Verify native server sync load and restart', 1)[1].split('- name:', 1)[0]
        upload = desktop.split('- name: Upload native server sync evidence', 1)[1].split('- name:', 1)[0]
        for step in (build, run):
            self.assertIn("if: matrix.target != 'linux'", step)
            self.assertNotIn('continue-on-error', step)
        self.assertIn('working-directory: services/server', build)
        self.assertIn('dart pub get --enforce-lockfile', build)
        self.assertIn('dart compile exe bin/server.dart', build)
        self.assertIn('server_sync_load_runtime.py', run)
        self.assertIn('SOURCE_COMMIT_SHA', run)
        self.assertIn('test_server_sync_load_runtime.py', run)
        self.assertIn('--evidence build/native-server-sync', run)
        self.assertIn("always() && matrix.target != 'linux'", upload)
        self.assertIn('if-no-files-found: error', upload)
        self.assertIn('path: build/native-server-sync/', upload)


if __name__ == '__main__':
    unittest.main()
