import os
import re
import json
import sys
import argparse
from urllib.parse import urlsplit


def host(url):
    return (urlsplit(url).hostname or '').lower()


def same_site(old, new):
    return host(old) == host(new) or host(old).removeprefix('www.') == host(new).removeprefix('www.')


def redirects(stats):
    pairs = {}
    for _, entries in (stats.get('redirect_map') or {}).items():
        for e in entries:
            old = e.get('origin')
            new = e.get('url')
            if old and new and old != new and same_site(old, new):
                pairs[old] = new
    return pairs


def emit(report_lines):
    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    text = '\n'.join(report_lines) + '\n'
    if summary_path:
        with open(summary_path, 'a') as f:
            f.write(text)
    else:
        print(text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', required=True)
    parser.add_argument('--files', nargs='+', required=True)
    parser.add_argument('--github-output', default='')
    args = parser.parse_args()

    try:
        with open(args.report) as f:
            stats = json.load(f)
    except (FileNotFoundError, ValueError):
        emit(["## Broken Link Fix", "", "No link report to work from - nothing to fix."])
        return 0

    pairs = redirects(stats)
    out = ["## Broken Link Fix", ""]
    changed_files = []
    for path in args.files:
        try:
            with open(path, encoding='utf-8') as f:
                text = f.read()
        except FileNotFoundError:
            continue
        new_text = text
        for old, new in sorted(pairs.items(), key=lambda kv: -len(kv[0])):
            new_text = re.sub(re.escape(old) + r'(?![A-Za-z0-9_\-/.?=&%#~])', new.replace('\\', '\\\\'), new_text)
        if new_text != text:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_text)
            changed_files.append(path)
    if pairs:
        out.append(f"{len(pairs)} redirected link(s) pointed at their final address:")
        for old, new in sorted(pairs.items()):
            out.append(f"- `{old}` -> `{new}`")
    else:
        out.append("No same-site redirects to update.")
    out.append("")
    out.append("Links that return an error (404, gone, timeout) have no safe replacement and stay as warnings in the Broken Link Check report.")
    emit(out)
    if args.github_output:
        with open(args.github_output, 'a') as f:
            f.write(f"changed={'true' if changed_files else 'false'}\n")
    return 0


if __name__ == '__main__':
    sys.exit(main())
