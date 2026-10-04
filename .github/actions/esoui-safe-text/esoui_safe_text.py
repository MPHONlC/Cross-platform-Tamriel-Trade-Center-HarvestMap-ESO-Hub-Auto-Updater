import argparse
import os
import sys

DROP = {0xFEFF, 0x200B, 0x2060, 0x00AD, 0x200E, 0x200F}


def convert(text):
    out = []
    for ch in text:
        code = ord(ch)
        if code in DROP:
            continue
        out.append(ch if code < 128 else "&#%d;" % code)
    return "".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="esoui-upload-text")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    for path in args.files:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
        safe = convert(text)
        target = os.path.join(args.out_dir, os.path.basename(path))
        with open(target, "w", encoding="ascii", newline="") as f:
            f.write(safe)
        changed = sum(1 for ch in text if ord(ch) >= 128)
        print("%s -> %s (%d characters turned into entities or dropped)" % (path, target, changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
