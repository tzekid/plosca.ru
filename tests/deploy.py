#!/usr/bin/env python3
"""Exercise the real publisher in a disposable Git repository and release root."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / 'scripts/deploy.sh'
with tempfile.TemporaryDirectory(prefix='plosca-deploy-') as temporary:
    base = Path(temporary)
    repo, root = base / 'repo with spaces', base / 'releases with spaces'
    repo.mkdir()
    (repo / 'scripts').mkdir()
    (repo / 'site').mkdir()
    shutil.copy2(script, repo / 'scripts/deploy.sh')
    env = {**os.environ, 'PLOSCA_RELEASE_ROOT': str(root)}

    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()

    def commit(text):
        (repo / 'site/index.html').write_text(text)
        git('add', '.')
        git('commit', '-qm', 'Update fixture')
        return git('rev-parse', 'HEAD')

    def deploy(extra_env=None, success=True):
        result = subprocess.run([str(repo / 'scripts/deploy.sh')], env=extra_env or env,
                                capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result

    def current():
        return os.readlink(root / 'current')

    def verify(revision, text):
        assert current() == f'releases/{revision}'
        assert (root / 'current/index.html').read_text() == text
        assert {p.name for p in (root / 'current').iterdir()} == {'index.html', 'download.bin'}
        assert (root / 'current/download.bin').read_bytes() == bytes(range(256))
        assert not list(root.glob('.deploy-*'))

    git('init', '-q', '-b', 'master')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    (repo / '.gitignore').write_text('site/ignored.txt\n')
    (repo / 'site/download.bin').write_bytes(bytes(range(256)))
    first = commit('first')
    (repo / 'site/untracked.txt').write_text('must not publish')
    (repo / 'site/ignored.txt').write_text('must not publish')
    deploy()
    verify(first, 'first')
    assert not (root / 'previous').exists()
    deploy()
    verify(first, 'first')
    assert not (root / 'previous').exists()
    (repo / 'site/untracked.txt').unlink()
    second = commit('second')
    deploy()
    verify(second, 'second')
    assert os.readlink(root / 'previous') == f'releases/{first}'
    deploy()
    assert os.readlink(root / 'previous') == f'releases/{first}'

    # Refuse dirty tracked input and a conflicting immutable directory.
    (repo / 'site/index.html').write_text('dirty')
    deploy(success=False)
    verify(second, 'second')
    (repo / 'site/index.html').write_text('second')
    third = commit('third')
    conflict = root / 'releases' / third
    conflict.mkdir()
    (conflict / 'index.html').write_text('wrong bytes')
    deploy(success=False)
    verify(second, 'second')
    assert (conflict / 'index.html').read_text() == 'wrong bytes'
    shutil.rmtree(conflict)
    conflict.symlink_to(root / 'current', target_is_directory=True)
    deploy(success=False)
    verify(second, 'second')
    conflict.unlink()

    # Fail the actual current-link rename, after previous was recorded.
    commands = base / 'commands'
    commands.mkdir()
    real_mv = shutil.which('mv')
    (commands / 'mv').write_text('#!/usr/bin/env bash\n'
        'if [[ "${@: -1}" == "$PLOSCA_RELEASE_ROOT/current" ]]; then exit 71; fi\n'
        'exec "$REAL_MV" "$@"\n')
    (commands / 'mv').chmod(0o755)
    fail_env = {**env, 'PATH': str(commands) + os.pathsep + os.environ['PATH'], 'REAL_MV': real_mv}
    deploy(fail_env, success=False)
    verify(second, 'second')
    assert os.readlink(root / 'previous') == f'releases/{first}'

    # Concurrent identical publishers must never nest/overwrite releases or lose rollback.
    processes = [subprocess.Popen([str(repo / 'scripts/deploy.sh')], env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
    for process in processes:
        out, err = process.communicate(timeout=15)
        assert process.returncode == 0, (out, err)
    verify(third, 'third')
    assert os.readlink(root / 'previous') == f'releases/{second}'
    assert not (root / 'releases' / third / 'site').exists()

    # Moving HEAD during archive must not change the revision captured at startup.
    fourth = commit('fourth')
    git('reset', '--hard', third)
    real_git = shutil.which('git')
    (commands / 'git').write_text('#!/usr/bin/env bash\n'
        'if [[ "$3" == archive ]]; then "$REAL_GIT" -C "$2" reset --hard "$NEXT_REVISION" >/dev/null; fi\n'
        'exec "$REAL_GIT" "$@"\n')
    (commands / 'git').chmod(0o755)
    (commands / 'mv').unlink()
    deploy({**env, 'PATH': str(commands) + os.pathsep + os.environ['PATH'],
            'REAL_GIT': real_git, 'NEXT_REVISION': fourth})
    assert git('rev-parse', 'HEAD') == fourth
    verify(third, 'third')
    # Exercise the documented rollback sequence with the same root lock.
    subprocess.run(['bash', '-euc', '''
root="$PLOSCA_RELEASE_ROOT"
(
  flock 9
  test -d "$root/previous" || exit 1
  next=$(mktemp -d "$root/.rollback-XXXXXXXX")
  trap 'rm -rf -- "$next"' EXIT
  ln -s "$(readlink "$root/previous")" "$next/current"
  mv -Tf "$next/current" "$root/current"
) 9>"$root/.deploy.lock"
'''], env=env, check=True)
    verify(second, 'second')
    assert (root / 'releases' / third / 'index.html').read_text() == 'third'
    print('publication journeys passed: committed bytes, excluded working files, idempotency, rollback, collision, failed promotion, concurrency, captured revision')

    # Immutable fixture directories need owner write permission for temporary cleanup.
    for path in root.rglob('*'):
        if path.is_dir() and not path.is_symlink():
            path.chmod(0o755)
