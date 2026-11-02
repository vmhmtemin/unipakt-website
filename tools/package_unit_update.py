#!/usr/bin/env python3
"""Package a committed update and verify its patch against the exact base tree."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile


def git(*args, cwd=None):
    return subprocess.check_output(['git', *args], cwd=cwd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', default='669cde2')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(git('rev-parse', '--show-toplevel').decode().strip())
    base = git('rev-parse', args.base, cwd=root).decode().strip()
    head = git('rev-parse', 'HEAD', cwd=root).decode().strip()
    if git('status', '--porcelain', cwd=root).strip():
        raise SystemExit('Commit the source changes before packaging.')
    names = git('diff', '--name-only', '--diff-filter=ACMR', '-z', base, head, cwd=root).decode().split('\0')
    names = [name for name in names if name]
    deleted = [name for name in git('diff', '--name-only', '--diff-filter=D', '-z', base, head, cwd=root).decode().split('\0') if name]
    patch = git('diff', '--binary', '--full-index', base, head, cwd=root)
    files = {name: (root / name).read_bytes() for name in names}
    manifest = {
        'base_commit': base, 'source_commit': head,
        'deleted_paths': deleted,
        'files': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()} for name, data in files.items()},
    }
    with tempfile.TemporaryDirectory(prefix='unipakt-apply-check-') as directory:
        destination = Path(directory)
        archive = git('archive', '--format=tar', base, cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(destination, filter='data')
        patch_file = destination / 'delivery.patch'
        patch_file.write_bytes(patch)
        subprocess.run(['git', 'apply', '--check', str(patch_file)], cwd=destination, check=True)
        subprocess.run(['git', 'apply', str(patch_file)], cwd=destination, check=True)
        for name, data in files.items():
            if (destination / name).read_bytes() != data:
                raise SystemExit(f'Applied file differs: {name}')
        for name in deleted:
            if (destination / name).exists():
                raise SystemExit(f'Deleted file still exists: {name}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    instructions = (
        '# UniPakt kod teslimi\n\n'
        f'Temel commit: `{base}`\nTeslim commit: `{head}`\n\n'
        '`files/` dizini yalnız değişen kaynak dosyalarını içerir. '
        '`changes.patch` aynı değişikliklerin Git yamasıdır. İki yöntemden birini kullanın.\n\n'
        'Önce `git apply --check /paket/changes.patch` çalıştırın. Başarılıysa '
        '`git apply /paket/changes.patch` ile uygulayın. Kontrol başarısızsa güncel '
        'dalınız farklıdır; dosyaları körlemesine üzerine yazmayın.\n\n'
        'Migration sırası, testler, kapsam ve ortam sınırları: '
        '`files/docs/unit-workspace-renewal.md`.\n\n'
        'Bu teslim canlı veritabanına uygulanmadı ve GitHub’a gönderilmedi. '
        'Kod push etmek migration’ları kendiliğinden uygulamaz.\n'
    )
    with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.writestr('KURULUM.md', instructions)
        archive.writestr('manifest.json', json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
        archive.writestr('changes.patch', patch)
        for name, data in files.items():
            archive.writestr('files/' + name, data)
    with zipfile.ZipFile(args.output) as archive:
        if archive.testzip() is not None:
            raise SystemExit('ZIP verification failed.')
        for name, data in files.items():
            assert archive.read('files/' + name) == data
    print(json.dumps({'output': str(args.output), 'files': len(files), 'bytes': args.output.stat().st_size,
                      'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(), 'patch_verified': True}, indent=2))


if __name__ == '__main__':
    main()
