#!/usr/bin/env python3
"""Exercise the product CLI against real, unmodified published bindings on iOS.

Creates a standalone temporary Flutter project so old bindings do not change the
repository's shared workspace resolution. Run on an exclusively assigned booted
Simulator. Raw runner logs/URI stay private; evidence contains sanitized CLI JSON
and screenshots. No input action is retried.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


VERSIONS = ['0.1.0', '0.2.0', '0.2.1', '0.2.2', '0.2.3', '0.2.4',
            '0.3.0', '0.4.0', '0.5.0', '0.6.0', '0.7.0']
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--dart', required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--versions', nargs='+', choices=VERSIONS, default=VERSIONS)
    args = parser.parse_args()
    os.umask(0o077)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = output / 'app'
    evidence = output / 'evidence'
    evidence.mkdir(exist_ok=True)
    env = {**os.environ, 'PATH': str(Path(args.flutter).parent) + ':' + os.environ['PATH']}

    def run(command, log, cwd=app):
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=240)
        if result.returncode:
            raise RuntimeError(f'Command failed; private diagnostic: {log}')

    if not app.exists():
        run([args.flutter, 'create', '--empty', '--no-pub', '--platforms=ios',
             '--org', 'dev.marionette', '--project-name', 'binding_compatibility',
             str(app)], output / 'create.log', output)
    shutil.copyfile(ROOT / 'integration_test/fixtures/binding_compatibility_app.dart',
                    app / 'lib/main.dart')
    summary_file = evidence / 'summary.json'
    previous = json.loads(summary_file.read_text()) if summary_file.exists() else []
    results = [result for result in previous if result['version'] not in args.versions]
    for version in args.versions:
        print(f'{version}: preparing app', flush=True)
        private = output / version
        private.mkdir(exist_ok=True)
        runtime = private / 'runtime'
        uri_file = private / 'vm-uri'
        uri_file.unlink(missing_ok=True)
        (app / 'pubspec.yaml').write_text(f'''name: binding_compatibility
publish_to: none
environment:
  sdk: ^3.13.7
dependencies:
  flutter:
    sdk: flutter
  marionette_flutter: {version}
flutter:
  uses-material-design: true
''')
        run([args.flutter, 'pub', 'get'], private / 'pub-get.log')
        records = []
        runner = None
        connected = False
        uri = None

        def cli(arguments, expected=0):
            command = [args.dart, str(ROOT / 'bin/marionette_agent.dart'),
                       '--session', 'compat', '--json', '--timeout', '20000', *arguments]
            result = subprocess.run(command, cwd=ROOT, env={**env,
                                    'MARIONETTE_AGENT_RUNTIME_DIR': str(runtime)},
                                    capture_output=True, text=True, timeout=60)
            if uri and (uri in result.stdout or uri in result.stderr):
                raise AssertionError('CLI exposed the private VM URI')
            response = json.loads(result.stdout)
            records.append({'arguments': ['connect', '<VM_URI>'] if arguments[0] == 'connect'
                            else arguments, 'exitCode': result.returncode,
                            'response': response, 'stderr': result.stderr})
            if result.returncode != expected:
                raise AssertionError(f'{version}: {arguments[0]} exit {result.returncode}, expected {expected}')
            return response

        def snapshot():
            return cli(['snapshot'])['data']['elements']

        def row(rows, key):
            return next(item for item in rows if item.get('key') == key)

        def state(key, expected):
            # Only reads may wait for a frame. UI operations above run once.
            deadline = time.monotonic() + 8
            while True:
                rows = snapshot()
                if row(rows, key).get('text') == expected:
                    return rows
                if time.monotonic() >= deadline:
                    raise AssertionError(f'{version}: expected {key} = {expected}')
                time.sleep(0.1)

        try:
            with (private / 'runner.log').open('w') as log:
                runner = subprocess.Popen([args.flutter, 'run', '--debug', '--no-pub',
                    '-d', args.device, '--vmservice-out-file=' + str(uri_file),
                    '--dart-define=BINDING_VERSION=' + version], cwd=app, env=env,
                    stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True)
                deadline = time.monotonic() + 240
                while not uri_file.exists() or not uri_file.read_text().strip():
                    if runner.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError(f'{version}: app launch failed; see private runner.log')
                    time.sleep(0.5)
                uri = uri_file.read_text().strip()
                # The service URI can precede first frame/extension registration.
                time.sleep(2)
                print(f'{version}: CLI acceptance', flush=True)
                connected = True
                cli(['connect', uri])
                before = state('tap_result', 'Tap count: 0')
                ref = row(before, 'tap_button')['ref']
                cli(['tap', ref])
                stale = cli(['tap', ref], expected=4)
                assert stale['error']['code'] == 'STALE_REF'
                state('tap_result', 'Tap count: 1')
                missing = cli(['tap', '--key', 'absent'], expected=4)
                assert missing['error']['code'] == 'TARGET_NOT_FOUND'
                state('tap_result', 'Tap count: 1')
                cli(['fill', '--key', 'text_input', 'compatibility'])
                state('fill_result', 'Input length: 13')
                cli(['fill', '--key', 'text_input', ''])
                state('fill_result', 'Input length: 0')
                # Native gestures were introduced in 0.5; earlier versions must
                # explicitly reject them, without breaking the connection.
                supports_swipe = tuple(map(int, version.split('.'))) >= (0, 5, 0)
                swipe = cli(['swipe', '--key', 'page_view', 'left'], expected=0 if supports_swipe else 6)
                if supports_swipe:
                    state('page_result', 'Page: 1')
                else:
                    assert swipe['error']['code'] == 'UNSUPPORTED_CAPABILITY'
                    state('page_result', 'Page: 0')
                if version == '0.7.0':
                    cli(['tap', '--identifier', 'compat.tap'])
                    state('tap_result', 'Tap count: 2')
                cli(['logs'])
                # Simulator pixels are independent evidence of the CLI actions.
                run(['xcrun', 'simctl', 'io', args.device, 'screenshot',
                     str(evidence / f'{version}.png')], private / 'screenshot.log')
                cli(['close'])
                cli(['connect', uri])
                state('tap_result', 'Tap count: 2' if version == '0.7.0' else 'Tap count: 1')
                cli(['close'])
                connected = False
                results.append({'version': version, 'status': 'passed',
                                'swipe': 'passed' if supports_swipe else 'unsupported'})
                print(f'{version}: PASS', flush=True)
        finally:
            try:
                if connected:
                    cli(['close'])
            finally:
                if runner is not None and runner.poll() is None:
                    runner.stdin.write('q\n')
                    runner.stdin.flush()
                    try:
                        runner.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        runner.terminate()
                        runner.wait(timeout=10)
                # The assigned simulator belongs exclusively to this verification.
                subprocess.run(['xcrun', 'simctl', 'terminate', args.device,
                                'dev.marionette.bindingCompatibility'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                uri_file.unlink(missing_ok=True)
                deadline = time.monotonic() + 10
                while (runtime / 'daemon.json').exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if (runtime / 'daemon.json').exists():
                    raise AssertionError('Owned daemon did not shut down')
                (evidence / f'{version}.json').write_text(json.dumps(records, indent=2))
                (evidence / 'summary.json').write_text(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
