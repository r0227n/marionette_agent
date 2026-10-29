"""Exercise the real Lefthook/Git boundary with deterministic SDK stand-ins."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
LEFTHOOK = shutil.which(os.environ.get('LEFTHOOK_BIN', 'lefthook'))

STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'flutter' and any(key in os.environ for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_PREFIX')):
    sys.exit(98)
with open(os.environ['QUALITY_LOG'], 'a') as log:
    log.write(json.dumps([name, args, str(Path.cwd())]) + '\n')
if os.environ.get('QUALITY_FAIL') == name + ' ' + ' '.join(args):
    sys.exit(1)
if name == 'dart' and args and args[0] == 'format':
    for arg in args[1:]:
        file = Path(arg)
        if file.is_file() and 'UNFORMATTED' in file.read_text():
            sys.exit(1)
'''


class QualityHooks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='quality-hooks-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / 'fake-bin'
        self.bin.mkdir()
        for name in ('dart', 'flutter', 'ffmpeg', 'ffprobe'):
            path = self.bin / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.log = self.root / 'commands.jsonl'
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        QUALITY_LOG=str(self.log), LEFTHOOK_VERBOSE='0',
                        MISE_TRUSTED_CONFIG_PATHS=str(self.root))
        # Do not inherit the caller's Git hook context into the fixture repository.
        for key in list(self.env):
            if key.startswith('GIT_') or key in ('LEFTHOOK', 'LEFTHOOK_EXCLUDE'):
                self.env.pop(key)
        self.git('init', '-q', '--template=')
        self.git('config', 'user.name', 'Hook test')
        self.git('config', 'user.email', 'hook@example.test')
        self.git('config', 'commit.gpgsign', 'false')
        for name in ('lefthook.yml', '.mise.toml', 'tool/quality.sh'):
            self.write(name, (SOURCE / name).read_text())
        for directory in ('lib', 'example',
                          'packages/marionette_agent_platform_interface/test',
                          'packages/marionette_agent_ios/test',
                          'packages/marionette_agent_android',
                          'packages/marionette_agent_macos',
                          'packages/marionette_agent_web',
                          'packages/marionette_agent_flutter/test',
                          'packages/marionette_agent_video/test'):
            self.write(f'{directory}/fixture.dart', 'void main() {}\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.run_process([LEFTHOOK, 'install'])

    def run_process(self, args, check=True):
        result = subprocess.run(args, cwd=self.root, env=self.env,
                                capture_output=True, text=True)
        if check and result.returncode:
            self.fail(result.stdout + result.stderr)
        return result

    def git(self, *args, check=True):
        return self.run_process(['git', *args], check=check)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def stage(self, name, text='fixture\n'):
        self.write(name, text)
        self.git('add', '--', name)

    def calls(self):
        return [json.loads(line)[:2] for line in self.log.read_text().splitlines()] \
            if self.log.exists() else []

    def test_extension_and_distribution_inputs_run_complete_gate(self):
        for name in ('.mise.toml', 'lib/new.dart', 'pubspec.yaml', 'pubspec.lock',
                     'analysis_options.yaml', 'samples/workflows/new.yml',
                     'samples/workflows/new.json', 'test/fixtures/new.json',
                     'CHANGELOG.md', 'THIRD_PARTY_NOTICES.txt', 'LICENSE',
                     'NOTICE', 'skill-data/core/SKILL.md', 'tool/check.sh'):
            with self.subTest(name=name):
                text = (SOURCE / name).read_text() + '\n# changed\n' \
                    if name == '.mise.toml' else 'void main() {}\n'
                self.stage(name, text)
                self.run_process([LEFTHOOK, 'run', 'pre-commit'])
                calls = self.calls()
                self.assertIn(['flutter', ['pub', 'get', '--enforce-lockfile']], calls)
                self.assertIn(['dart', ['analyze']], calls)
                self.assertIn(['dart', ['run', 'tool/check_release.dart']], calls)
                self.assertIn(['dart', ['run', 'tool/license_notices.dart', '--check']], calls)
                self.assertIn(['dart', ['test', '--concurrency=1', '--timeout=2m']], calls)
                self.assertIn(['dart', ['test', '--concurrency=1']], calls)
                self.assertTrue(any(
                    name == 'dart' and args == ['test', '--concurrency=1']
                    and Path(cwd).name == 'marionette_agent_video'
                    for name, args, cwd in map(json.loads, self.log.read_text().splitlines())
                ))
                self.assertIn(['flutter', ['test', 'flutter_test']], calls)
                self.assertIn(['flutter', ['test']], calls)
                self.assertEqual(calls[-1], ['dart', ['run', 'integration_test/release_smoke.dart']])
                # Reset only this fixture index; keep each input independent.
                self.git('reset', '-q')
                self.log.unlink()

    def test_documentation_and_website_inputs_skip_workspace(self):
        self.stage('docs/note.md')
        self.stage('website/src/page.astro')
        self.stage('website/package.json')
        self.stage('website/bun.lock')
        self.git('commit', '-qm', 'documentation only')
        self.assertEqual(self.calls(), [])

    def test_deleted_dart_still_runs_workspace_checks(self):
        self.git('rm', 'lib/fixture.dart')
        self.run_process([LEFTHOOK, 'run', 'pre-commit'])
        self.assertIn(['dart', ['analyze']], self.calls())

    def test_renamed_dart_with_spaces_is_one_formatter_argument(self):
        self.git('mv', 'lib/fixture.dart', 'lib/renamed file.dart')
        self.run_process([LEFTHOOK, 'run', 'pre-commit'])
        self.assertIn(['dart', ['format', '--output=none', '--set-exit-if-changed',
                                'lib/renamed file.dart']], self.calls())

    def test_unformatted_staged_content_blocks_commit_even_if_worktree_fixed(self):
        self.stage('lib/fixture.dart', '// UNFORMATTED\n')
        self.write('lib/fixture.dart', 'void main() {}\n')
        staged = self.git('diff', '--cached').stdout
        before = self.git('rev-parse', 'HEAD').stdout
        result = self.git('commit', '-qm', 'must fail', check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)
        self.assertEqual(self.git('diff', '--cached').stdout, staged)
        self.assertEqual((self.root / 'lib/fixture.dart').read_text(), 'void main() {}\n')

    def test_failed_quality_step_blocks_commit_and_stops_later_steps(self):
        for failure in ('flutter pub get --enforce-lockfile', 'dart analyze',
                        'dart run tool/check_release.dart',
                        'dart run tool/license_notices.dart --check',
                        'dart test --concurrency=1 --timeout=2m',
                        'dart test --concurrency=1', 'flutter test flutter_test',
                        'flutter test', 'dart run integration_test/release_smoke.dart'):
            with self.subTest(failure=failure):
                self.stage('lib/fixture.dart', '// changed\n')
                self.env['QUALITY_FAIL'] = failure
                before = self.git('rev-parse', 'HEAD').stdout
                result = self.git('commit', '-qm', 'must fail', check=False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.git('rev-parse', 'HEAD').stdout, before)
                name, *args = failure.split()
                self.assertEqual(self.calls()[-1], [name, args])
                self.log.unlink()

    def test_all_files_runs_complete_gate_with_clean_index(self):
        self.run_process([LEFTHOOK, 'run', 'pre-commit', '--all-files'])
        self.assertEqual(self.calls()[-1],
                         ['dart', ['run', 'integration_test/release_smoke.dart']])

    def test_platform_tests_run_only_in_packages_with_tests(self):
        self.stage('lib/fixture.dart', '// changed\n')
        self.run_process([LEFTHOOK, 'run', 'pre-commit'])
        rows = [json.loads(line) for line in self.log.read_text().splitlines()]
        tested = [Path(cwd).resolve().relative_to(self.root.resolve()).as_posix()
                  for name, args, cwd in rows
                  if name == 'dart' and args == ['test', '--concurrency=1']]
        self.assertEqual(tested, [
            'packages/marionette_agent_platform_interface',
            'packages/marionette_agent_ios',
            'packages/marionette_agent_flutter',
            'packages/marionette_agent_video',
        ])
        provider = [Path(cwd).resolve().relative_to(self.root.resolve()).as_posix()
                    for name, args, cwd in rows
                    if name == 'flutter' and args == ['test', 'flutter_test']]
        self.assertEqual(provider, ['packages/marionette_agent_flutter'])

    def test_missing_encoder_blocks_commit_instead_of_skipping_tests(self):
        self.env['PATH'] = f'{self.bin}:/usr/bin:/bin'
        for name in ('ffmpeg', 'ffprobe'):
            with self.subTest(name=name):
                tool = self.bin / name
                tool.rename(self.bin / f'{name}.saved')
                self.stage('lib/fixture.dart', '// changed\n')
                result = self.run_process([LEFTHOOK, 'run', 'pre-commit'], check=False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f'Missing {name}', result.stdout + result.stderr)
                self.assertNotIn(['dart', ['analyze']], self.calls())
                (self.bin / f'{name}.saved').rename(tool)
                self.log.unlink(missing_ok=True)


if __name__ == '__main__':
    unittest.main()
