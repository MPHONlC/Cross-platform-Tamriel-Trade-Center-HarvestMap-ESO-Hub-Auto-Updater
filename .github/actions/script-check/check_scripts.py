import os
import glob
import shutil
import argparse
import subprocess
import sys


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def check_shell(path):
    problems = []
    result = subprocess.run(['bash', '-n', path], capture_output=True, text=True)
    if result.returncode != 0:
        problems.append(f"{path}: syntax error: {result.stderr.strip().splitlines()[0] if result.stderr.strip() else 'bash -n failed'}")
    return problems


def shellcheck_counts(path):
    result = subprocess.run(['shellcheck', '-f', 'gcc', path], capture_output=True, text=True)
    errors, warnings = [], 0
    for line in result.stdout.splitlines():
        if ': error:' in line:
            errors.append(line)
        elif ': warning:' in line:
            warnings += 1
    return errors, warnings


def check_batch(path):
    data = read_bytes(path)
    lines = data.split(b'\n')
    bare = [i + 1 for i, line in enumerate(lines[:-1]) if not line.endswith(b'\r')]
    if bare:
        return [f"{path}: {len(bare)} line(s) end without CRLF, first at line {bare[0]}; cmd.exe needs CRLF"]
    return []


def emit(report_lines, annotations):
    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    text = '\n'.join(report_lines) + '\n'
    if summary_path:
        with open(summary_path, 'a') as f:
            f.write(text)
    else:
        print(text)
    for a in annotations:
        print(a)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--shell-glob', default='**/*.sh')
    parser.add_argument('--batch-glob', default='**/*.bat')
    parser.add_argument('--fail', default='true')
    args = parser.parse_args()

    shell_files = sorted(glob.glob(args.shell_glob, recursive=True))
    batch_files = sorted(glob.glob(args.batch_glob, recursive=True))
    have_shellcheck = shutil.which('shellcheck') is not None
    out = ["## Script check", ""]
    annotations = []
    problems = []

    out.append("| File | Kind | Result |")
    out.append("|---|---|---|")
    for path in shell_files:
        found = check_shell(path)
        note = "syntax ok" if not found else "syntax error"
        if have_shellcheck:
            errors, warnings = shellcheck_counts(path)
            found += errors
            note += f", shellcheck {len(errors)} error(s), {warnings} warning(s)"
        out.append(f"| `{path}` | shell | {'FAIL' if found else 'pass'} ({note}) |")
        problems += found
    for path in batch_files:
        found = check_batch(path)
        out.append(f"| `{path}` | batch | {'FAIL' if found else 'pass'} (CRLF line endings) |")
        problems += found

    if not shell_files and not batch_files:
        out.append("| - | - | no scripts found |")
    if not have_shellcheck:
        out.append("")
        out.append("shellcheck is not installed on this runner, so only syntax and line endings were checked.")
    if problems:
        out.append("")
        for p in problems:
            out.append(f"- {p}")
            annotations.append(f"::error title=Script Check::{p}")
    emit(out, annotations)
    if problems and args.fail == 'true':
        sys.exit(1)


if __name__ == '__main__':
    main()
