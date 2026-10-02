"""Fail-closed git-flow policy and GitHub orchestration (standard library only)."""
import argparse
import base64
import json
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import quote

VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
SPECS = ('pubspec.yaml', 'packages/marionette_agent_util/pubspec.yaml',
         'example/pubspec.yaml')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def version(value):
    require(re.fullmatch(VERSION, value), 'Use stable MAJOR.MINOR.PATCH without v')
    return tuple(map(int, value.split('.')))


def route(pr, repo):
    base, head = pr['base']['ref'], pr['head']['ref']
    same = pr['head']['repo'] is not None and pr['head']['repo']['full_name'] == repo
    if base == 'main':
        require(same and re.fullmatch('release/' + VERSION, head),
                'main accepts same-repository release/MAJOR.MINOR.PATCH only')
    elif base == 'develop':
        require(head != 'main' and not head.startswith('release/'),
                'Development PRs target develop; use sync/main-* for release back-sync')
        if head.startswith('sync/'):
            require(same and re.fullmatch(r'sync/main-[0-9a-f]{40}', head),
                    'Reserved sync branch must belong to this repository')
    elif base.startswith('release/'):
        require(same and head.startswith('fix/'),
                'Release stabilization accepts same-repository fix/* only')
    else:
        raise ValueError('Unsupported PR base')


def check_files(read, expected):
    version(expected)
    for path in SPECS:
        text = read(path)
        matches = re.findall(r'^version:\s*([^\s]+)\s*$', text, re.M)
        require(len(matches) == 1 and matches[0].split('+')[0] == expected,
                f'{path}: version must match {expected}')
        require(re.search(r'^publish_to: none\s*$', text, re.M),
                f'{path}: pub.dev must remain disabled')
    require(re.search(r"^const version = '" + re.escape(expected) + r"';$",
                      read('lib/src/protocol/protocol.dart'), re.M), 'CLI version mismatch')
    changelog = read('CHANGELOG.md')
    sections = re.split(r'^## ', changelog, flags=re.M)[1:]
    require(sections and sections[0].splitlines()[0].strip() == expected,
            'Requested version must be the first changelog heading')
    notes = '\n'.join(sections[0].splitlines()[1:]).strip()
    require(notes and not re.search(r'\b(TODO|TBD|Unreleased)\b', notes, re.I),
            'Release changelog must contain reviewed notes, not placeholders')
    return notes


class GitHub:
    def __init__(self, repo):
        require(re.fullmatch(r'[\w.-]+/[\w.-]+', repo), 'Invalid repository')
        self.repo = repo

    def api(self, path, method='GET', data=None, missing=False):
        # Include HTTP status so only 404 is treated as absence; never swallow 403/5xx.
        args = ['gh', 'api', '--include', '--method', method,
                f'repos/{self.repo}/{path}']
        if data is not None:
            args += ['--input', '-']
        result = subprocess.run(args, input=json.dumps(data) if data is not None else None,
                                text=True, capture_output=True)
        status = re.search(r'^HTTP/\S+ (\d+)', result.stdout)
        if missing and status and status[1] == '404':
            return None
        require(result.returncode == 0, f'GitHub API failed: {method} {path}')
        body = re.split(r'\r?\n\r?\n', result.stdout, maxsplit=1)[-1]
        return json.loads(body) if body.strip() else None

    def ref(self, name):
        return self.api('git/ref/' + name, missing=True)

    def read(self, sha, path):
        obj = self.api(f'contents/{path}?ref={sha}')
        return base64.b64decode(obj['content']).decode()

    def compare(self, base, head):
        return self.api(f'compare/{base}...{head}')

    def ensure_branch(self, branch, sha):
        existing = self.ref('heads/' + branch)
        if existing:
            require(existing['object']['sha'] == sha,
                    'Existing branch moved; refusing overwrite. Review existing PR.')
        else:
            self.api('git/refs', 'POST', {'ref': 'refs/heads/' + branch, 'sha': sha})

    def ensure_pr(self, branch, base, title, body):
        owner = self.repo.split('/')[0]
        prs = self.api(f'pulls?state=all&head={quote(owner + ":" + branch, safe="")}&base={base}&per_page=100')
        if prs:
            require(len(prs) == 1 and prs[0]['state'] == 'open',
                    'A closed/merged or ambiguous PR exists; manual review required')
            return prs[0]
        return self.api('pulls', 'POST', dict(head=branch, base=base, title=title,
                                            body=body, draft=True))


def candidate(api, requested):
    version(requested)
    develop, main = api.ref('heads/develop'), api.ref('heads/main')
    require(develop and main, 'Both main and develop must exist; no history creation')
    sha, main_sha = develop['object']['sha'], main['object']['sha']
    comparison = api.compare(main_sha, sha)
    require(comparison['status'] == 'ahead',
            'develop must be ahead of and contain main; back-sync first')
    require(not api.ref('tags/v' + requested), 'Version tag already exists')
    active = api.api('pulls?state=open&base=main&per_page=100')
    require(len(active) < 100, 'Too many open main PRs to inspect safely')
    require(not any(pr['head']['ref'].startswith('release/') and
                    pr['head']['ref'] != 'release/' + requested for pr in active),
            'Another release PR is open; finish it before preparing a new version')
    check_files(lambda path: api.read(sha, path), requested)
    old = re.search(r'^version:\s*(\S+)', api.read(main_sha, 'pubspec.yaml'), re.M)[1]
    require(version(requested) > version(old.split('+')[0]), 'Version must increase from main')
    return sha


def prepare(api, requested, sha):
    # Recheck after the long quality gate; never release a different develop snapshot.
    require(candidate(api, requested) == sha, 'develop changed during verification; rerun')
    branch = 'release/' + requested
    api.ensure_branch(branch, sha)
    pr = api.ensure_pr(branch, 'main', 'Release ' + requested,
        '## 概要\nPrepare ' + requested + ' from verified develop commit `' + sha + '`.\n\n'
        '## 動作確認方法\nQuality passed before branch creation. Approve pending bot PR workflows '
        '(or close/reopen as a maintainer if checks are absent). Require Quality, Documentation '
        'and Git flow checks on the final candidate. Review native acceptance and release notes.\n\n'
        '- [ ] 人間が最終候補を確認し、Ready化とmainへのmergeを判断した\n\n'
        '## エビデンス\nCI logs and checks record mechanical verification. '
        'No tag, GitHub Release or pub.dev publication is performed.\n')
    print(pr['html_url'])


def sync(api, sha):
    require(re.fullmatch(r'[0-9a-f]{40}', sha), 'Expected exact merge SHA')
    comparison = api.compare(sha, 'develop')
    if comparison['status'] in ('ahead', 'identical'):
        print('develop already contains release commit')
        return
    require(api.compare(sha, 'main')['status'] in ('ahead', 'identical'),
            'Release commit must remain on main')
    branch = 'sync/main-' + sha
    api.ensure_branch(branch, sha)
    pr = api.ensure_pr(branch, 'develop', 'Sync released main into develop',
        '## 概要\nBack-sync reviewed main commit `' + sha + '`.\n\n'
        '## 動作確認方法\nApprove pending bot PR workflows (or close/reopen if absent). '
        'Resolve conflicts on this branch without force-pushing main/develop. '
        'Use a merge commit to preserve main ancestry.\n\n'
        '- [ ] 人間が差分・CI・競合解消を確認した\n\n'
        '## エビデンス\nSee main quality run and this PR checks. No automatic merge.\n')
    print(pr['html_url'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['policy', 'resolve', 'prepare', 'metadata', 'sync'])
    parser.add_argument('--version')
    parser.add_argument('--sha')
    args = parser.parse_args()
    repo = os.environ['GITHUB_REPOSITORY']
    if args.mode == 'policy':
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        pr = event.get('pull_request')
        if pr:
            route(pr, repo)
            if pr['base']['ref'] == 'main':
                requested = pr['head']['ref'][8:]
                check_files(lambda path: Path(path).read_text(), requested)
                base, head = pr['base']['sha'], pr['head']['sha']
                require(all(re.fullmatch(r'[0-9a-f]{40}', sha) for sha in (base, head)),
                        'Expected exact PR commits')
                subprocess.run(['git', 'merge-base', '--is-ancestor', base, head], check=True)
                old = subprocess.check_output(['git', 'show', base + ':pubspec.yaml'], text=True)
                old_version = re.search(r'^version:\s*(\S+)', old, re.M)[1].split('+')[0]
                require(version(requested) > version(old_version), 'Version must increase from main')
                tags = subprocess.check_output(['git', 'tag', '--list', 'v' + requested], text=True)
                require(not tags.strip(), 'Version tag already exists')
        return
    if args.mode == 'metadata':
        require(re.fullmatch(r'[0-9a-f]{40}', args.sha or ''), 'Expected exact merge SHA')
        notes = check_files(lambda path: Path(path).read_text(), args.version)
        target = Path('release-preparation')
        target.mkdir(exist_ok=True)
        (target / 'manifest.json').write_text(json.dumps(dict(version=args.version,
            proposed_tag='v' + args.version, commit=args.sha, published=False), indent=2) + '\n')
        (target / 'release-notes.md').write_text(notes + '\n')
        subprocess.run(['git', 'archive', '--format=tar.gz',
                        '--output=' + str(target / ('marionette_agent-' + args.version + '.tar.gz')),
                        args.sha], check=True)
        return
    api = GitHub(repo)
    if args.mode == 'resolve':
        sha = candidate(api, args.version)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            out.write('sha=' + sha + '\n')
        print('Validated develop snapshot: ' + sha)
    elif args.mode == 'prepare':
        prepare(api, args.version, args.sha)
    else:
        sync(api, args.sha)


if __name__ == '__main__':
    main()
