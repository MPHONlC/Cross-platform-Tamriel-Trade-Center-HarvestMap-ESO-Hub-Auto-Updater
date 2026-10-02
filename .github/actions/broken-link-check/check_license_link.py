import os
import re
import sys
import argparse

PLAIN = re.compile(r'See\s+LICENSE\.md')
LINKED = re.compile(r'See\s+(\[LICENSE\.md\]\([^)]*\)|\[url=[^\]]*\]\s*LICENSE\.md\s*\[/url\])', re.I)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--files', nargs='+', required=True)
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY', ''))
    parser.add_argument('--plain-ok', default='', help='Kept for older workflow calls; every format is plain now')
    args = parser.parse_args()

    problems = []
    out = ["## License line check", ""]
    for path in args.files:
        try:
            with open(path, encoding='utf-8') as f:
                text = f.read()
        except FileNotFoundError:
            continue
        if LINKED.search(text):
            problems.append(f"{path}: the license line links LICENSE.md, expected the plain \"See LICENSE.md\"")
        elif PLAIN.search(text):
            out.append(f"`{path}`: plain \"See LICENSE.md\".")

    for p in problems:
        out.append(f"- {p}")
        print(f"::error title=License Line Check::{p}")
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    text = '\n'.join(out) + '\n'
    if summary:
        with open(summary, 'a') as f:
            f.write(text)
    else:
        print(text)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
