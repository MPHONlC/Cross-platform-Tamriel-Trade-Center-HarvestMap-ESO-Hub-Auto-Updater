import argparse
import os
import re
import sys

DROP = {0xFEFF, 0x200B, 0x2060, 0x00AD, 0x200E, 0x200F}
LIMITS = {"esoui": None, "bethesda": 10000}
ENTITY = re.compile(r"&#(\d+);|&#x([0-9a-fA-F]+);|&(copy|reg|mdash|ndash|trade);")
NAMED = {"copy": "©", "reg": "®", "mdash": "—", "ndash": "–", "trade": "™"}


def decode_entities(text):
    def rep(m):
        if m.group(1):
            return chr(int(m.group(1)))
        if m.group(2):
            return chr(int(m.group(2), 16))
        return NAMED[m.group(3)]
    return ENTITY.sub(rep, text)


def convert(text, target):
    text = decode_entities(text)
    if target == "bethesda":
        return "".join(ch for ch in text if ord(ch) not in DROP)
    out = []
    for ch in text:
        code = ord(ch)
        if code in DROP:
            continue
        if code == 0xA0:
            out.append(" ")
        elif code < 128 or 0xA0 < code <= 0xFF:
            out.append(ch)
        else:
            out.append("&#%d;" % code)
    return "".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="esoui-upload-text")
    parser.add_argument("--target", choices=sorted(LIMITS), default="esoui")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    encoding = "latin-1" if args.target == "esoui" else "utf-8"
    failed = False
    for path in args.files:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
        safe = convert(text, args.target)
        target = os.path.join(args.out_dir, os.path.basename(path))
        with open(target, "w", encoding=encoding, newline="") as f:
            f.write(safe)
        print("%s -> %s (%s, %d characters)" % (path, target, encoding, len(safe)))
        limit = LIMITS[args.target]
        if limit and len(safe) > limit:
            print("::error file=%s::%s is %d characters after conversion; %s takes at most %d" % (path, path, len(safe), args.target, limit))
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
