import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from git_flow import GitHub, candidate, check_files, prepare, route, sync, unpublished, version

REPO = 'owner/repo'
SHA = 'a' * 40
MAIN = 'b' * 40


def files(v='1.1.0'):
    return {
        **{p: f'version: {v}\npublish_to: none\n' for p in
           ('pubspec.yaml', 'packages/marionette_agent_util/pubspec.yaml', 'example/pubspec.yaml')},
        'lib/src/protocol/protocol.dart': f"const version = '{v}';\n",
        'CHANGELOG.md': f'## {v}\n\n- Reviewed changes.\n\n## 1.0.0\nOld notes.\n',
    }


class FakeAPI(GitHub):
    def __init__(self):
        super().__init__(REPO)
        self.refs = {'heads/develop': SHA, 'heads/main': MAIN}
        self.prs = []
        self.writes = []
        self.status = 'ahead'

    def api(self, path, method='GET', data=None, missing=False):
        if method != 'GET':
            self.writes.append((path, data))
            if path == 'git/refs':
                self.refs[data['ref'][5:]] = data['sha']
            elif path == 'pulls':
                self.prs.append(dict(data, head={'ref': data['head']}, state='open', html_url='https://example.test/pr/1'))
                return self.prs[-1]
            return
        if path.startswith('git/ref/'):
            sha = self.refs.get(path[8:])
            return {'object': {'sha': sha}} if sha else None
        if path.startswith('pulls?'):
            return self.prs
        raise AssertionError(path)

    def read(self, sha, path):
        return files('1.0.0' if sha == MAIN else '1.1.0')[path]

    def compare(self, base, head):
        return {'status': self.status if head != 'main' else 'identical'}


class PolicyTests(unittest.TestCase):
    def pr(self, base, head, repo=REPO):
        return {'base': {'ref': base}, 'head': {'ref': head, 'repo': {'full_name': repo}}}

    def test_routes(self):
        for base, head, repo in [('develop', 'feature/normal', 'fork/repo'),
                                  ('main', 'release/1.1.0', REPO),
                                  ('release/1.1.0', 'fix/changelog', REPO),
                                  ('develop', 'sync/main-' + SHA, REPO)]:
            with self.subTest(head=head):
                route(self.pr(base, head, repo), REPO)

    def test_reject_routes(self):
        for base, head, repo in [('main', 'develop', REPO), ('main', 'feature/foo', REPO),
                                ('main', 'release/1.1.0', 'fork/repo'),
                                ('main', 'release/01.0.0', REPO),
                                ('develop', 'main', REPO), ('develop', 'release/1.1.0', REPO),
                                ('develop', 'sync/main-' + SHA, 'fork/repo'),
                                ('release/1.1.0', 'feature/foo', REPO),
                                ('other', 'feature/foo', REPO)]:
            with self.subTest(base=base, head=head, repo=repo), self.assertRaises(ValueError):
                route(self.pr(base, head, repo), REPO)

    def test_version_input_cannot_inject(self):
        for v in ['v1.0.0', '1.0.0-rc.1', '1.0.0+1', '01.0.0', '../main', '1.0.0\nsha=bad', '$(id)']:
            with self.subTest(v=v), self.assertRaises(ValueError):
                version(v)

    def test_release_metadata(self):
        self.assertEqual(check_files(files().__getitem__, '1.1.0'), '- Reviewed changes.')

    def test_pubspec_unpublished_scalar_forms(self):
        for scalar in ['none', "'none'", '"none"']:
            for comment in ['', ' # GitHub source releases only; keep pub.dev disabled.']:
                with self.subTest(scalar=scalar, comment=comment):
                    data = files()
                    data['example/pubspec.yaml'] = 'version: 1.1.0+1\npublish_to: ' + scalar + comment + '\n'
                    check_files(data.__getitem__, '1.1.0')

    def test_real_repository_pubspecs_remain_unpublished(self):
        for name in ['pubspec.yaml', 'example/pubspec.yaml',
                     'packages/marionette_agent_util/pubspec.yaml']:
            with self.subTest(name=name):
                self.assertTrue(unpublished(Path(name).read_text()))

    def test_unsafe_publish_targets_are_rejected(self):
        for text in ['publish_to: https://pub.dev\n',
                     'publish_to: none\npublish_to: https://pub.dev\n',
                     'publish_to: "none # not a comment"\n', 'publish_to: none-more\n']:
            with self.subTest(text=text):
                self.assertFalse(unpublished(text))

    def test_bad_metadata(self):
        for path, value in [('pubspec.yaml', 'version: 1.1.0\npublish_to: https://pub.dev\n'),
                            ('example/pubspec.yaml', 'version: 1.0.0\npublish_to: none\n'),
                            ('lib/src/protocol/protocol.dart', "const version = '1.0.0';\n"),
                            ('CHANGELOG.md', '## 1.1.0\nTODO\n'),
                            ('CHANGELOG.md', '## 1.1.0\n\n## 1.0.0\nold'),
                            ('CHANGELOG.md', '## 1.1.00\n- Not the requested version')]:
            with self.subTest(path=path):
                data = files()
                data[path] = value
                with self.assertRaises(ValueError):
                    check_files(data.__getitem__, '1.1.0')


class AutomationTests(unittest.TestCase):
    def test_dry_run_has_no_writes(self):
        api = FakeAPI()
        self.assertEqual(candidate(api, '1.1.0'), SHA)
        self.assertEqual(api.writes, [])

    def test_prepare_is_idempotent(self):
        api = FakeAPI()
        prepare(api, '1.1.0', SHA)
        prepare(api, '1.1.0', SHA)
        self.assertEqual(len(api.writes), 2)
        self.assertTrue(api.prs[0]['draft'])
        self.assertEqual(api.prs[0]['base'], 'main')
        self.assertEqual(api.refs['heads/main'], MAIN)

    def test_never_reset_existing_branch(self):
        api = FakeAPI()
        api.refs['heads/release/1.1.0'] = MAIN
        with self.assertRaises(ValueError):
            prepare(api, '1.1.0', SHA)
        self.assertFalse(api.writes)

    def test_closed_pr_never_recreated(self):
        api = FakeAPI()
        prepare(api, '1.1.0', SHA)
        api.prs[0]['state'] = 'closed'
        with self.assertRaises(ValueError):
            prepare(api, '1.1.0', SHA)
        self.assertEqual(len(api.writes), 2)

    def test_changed_candidate_never_written(self):
        api = FakeAPI()
        with self.assertRaises(ValueError):
            prepare(api, '1.1.0', 'c' * 40)
        self.assertFalse(api.writes)

    def test_existing_tag_rejected(self):
        api = FakeAPI()
        api.refs['tags/v1.1.0'] = SHA
        with self.assertRaises(ValueError):
            candidate(api, '1.1.0')

    def test_other_open_release_rejected(self):
        api = FakeAPI()
        api.prs = [{'head': {'ref': 'release/1.2.0'}, 'state': 'open'}]
        with self.assertRaisesRegex(ValueError, 'Another release'):
            candidate(api, '1.1.0')
        self.assertFalse(api.writes)

    def test_missing_main_rejected(self):
        api = FakeAPI()
        del api.refs['heads/main']
        with self.assertRaises(ValueError):
            candidate(api, '1.1.0')
        self.assertFalse(api.writes)

    def test_diverged_or_empty_release_rejected(self):
        for status in ['diverged', 'behind', 'identical']:
            api = FakeAPI()
            api.status = status
            with self.assertRaises(ValueError):
                candidate(api, '1.1.0')
            self.assertFalse(api.writes)

    def test_same_or_older_version_rejected(self):
        api = FakeAPI()
        for requested in ['1.0.0', '0.9.0']:
            api.read = lambda sha, path: files('1.0.0' if sha == MAIN else requested)[path]
            with self.assertRaises(ValueError):
                candidate(api, requested)

    def test_sync_noop_when_already_integrated(self):
        api = FakeAPI()
        sync(api, SHA)
        self.assertFalse(api.writes)

    def test_sync_diverged_creates_draft_without_merging(self):
        api = FakeAPI()
        api.status = 'diverged'
        sync(api, SHA)
        sync(api, SHA)
        self.assertEqual(len(api.writes), 2)
        self.assertTrue(api.prs[0]['draft'])
        self.assertEqual(api.prs[0]['base'], 'develop')
        self.assertEqual(api.refs['heads/develop'], SHA)

    def test_api_404_only_is_absence(self):
        api = GitHub(REPO)
        for code in [403, 404, 500]:
            result = subprocess.CompletedProcess([], 1, f'HTTP/2.0 {code}\n\n{{}}', '')
            with patch('subprocess.run', return_value=result):
                if code == 404:
                    self.assertIsNone(api.ref('heads/main'))
                else:
                    with self.assertRaises(ValueError):
                        api.ref('heads/main')

    def test_policy_real_history_and_existing_tag(self):
        import os
        from git_flow import main
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
            git('init', '-q')
            for v in ['1.0.0', '1.1.0']:
                for path, value in files(v).items():
                    dest = root / path
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_text(value)
                git('add', '.')
                git('-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', v)
                if v == '1.0.0':
                    base = git('rev-parse', 'HEAD')
            head = git('rev-parse', 'HEAD')
            event = root / 'event.json'
            event.write_text(json.dumps({'pull_request': {
                'base': {'ref': 'main', 'sha': base},
                'head': {'ref': 'release/1.1.0', 'sha': head, 'repo': {'full_name': REPO}},
            }}))
            cwd = os.getcwd()
            try:
                os.chdir(directory)
                with patch.dict(os.environ, GITHUB_REPOSITORY=REPO, GITHUB_EVENT_PATH=str(event)), \
                        patch('sys.argv', ['git_flow.py', 'policy']):
                    main()
                    git('tag', 'v1.1.0')
                    with self.assertRaisesRegex(ValueError, 'tag already exists'):
                        main()
            finally:
                os.chdir(cwd)

    def test_metadata_archive_exact_commit_without_tag(self):
        import os
        from git_flow import main
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path, value in files().items():
                dest = root / path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(value)
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
            git('init', '-q')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'fixture')
            sha = git('rev-parse', 'HEAD')
            cwd = os.getcwd()
            try:
                os.chdir(directory)
                with patch.dict(os.environ, GITHUB_REPOSITORY=REPO), patch('sys.argv',
                        ['git_flow.py', 'metadata', '--version', '1.1.0', '--sha', sha]):
                    main()
            finally:
                os.chdir(cwd)
            manifest = json.loads((root / 'release-preparation/manifest.json').read_text())
            self.assertEqual(manifest['commit'], sha)
            self.assertFalse(manifest['published'])
            self.assertEqual(git('tag'), '')
            self.assertTrue((root / 'release-preparation/marionette_agent-1.1.0.tar.gz').is_file())


if __name__ == '__main__':
    unittest.main()
