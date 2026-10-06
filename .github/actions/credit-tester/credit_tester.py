import sys

path, username = sys.argv[1], sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

changed = False


def already_credited(block_lines, username):
    return any(f"@{username}" in ln for ln in block_lines)


username = "".join(c if ord(c) < 128 else "&#%d;" % ord(c) for c in username)

if path.endswith("README_BBCODE.txt"):
    header_needle = "Testers & Suggestions:"
    header_idx = next((i for i, ln in enumerate(lines) if header_needle in ln), None)
    new_entry = f'[*] [color="#FF69B4"]@{username}[/color]\n'
    if header_idx is not None:
        list_start = header_idx + 1
        if lines[list_start].strip() != "[LIST]":
            raise SystemExit(f"expected [LIST] right after '{header_needle}' in {path}")
        list_end = next(i for i in range(list_start, len(lines)) if lines[i].strip() == "[/LIST]")
        if already_credited(lines[list_start:list_end], username):
            print(f"@{username} already credited, nothing to do")
            sys.exit(0)
        lines.insert(list_end, new_entry)
        changed = True
    else:
        anchor_idx = next(i for i, ln in enumerate(lines) if "Check out my other addons/projects:" in ln)
        section = [
            '[b][COLOR="Orange"]Testers & Suggestions:[/COLOR][/b]\n',
            "[LIST]\n",
            new_entry,
            "[/LIST]\n",
            "\n",
        ]
        lines[anchor_idx:anchor_idx] = section
        changed = True

elif path.endswith("README_COMMONMARK.txt"):
    header_needle = "Testers & Suggestions:"
    header_idx = next((i for i, ln in enumerate(lines) if ln.strip() == header_needle), None)
    new_entry = f"- @{username}\n"
    if header_idx is not None:
        block_end = header_idx + 1
        while block_end < len(lines) and lines[block_end].startswith("- "):
            block_end += 1
        if already_credited(lines[header_idx + 1:block_end], username):
            print(f"@{username} already credited, nothing to do")
            sys.exit(0)
        lines.insert(block_end, new_entry)
        changed = True
    else:
        anchor_idx = next(i for i, ln in enumerate(lines) if ln.strip() == "Check out my other addons/projects:")
        section = [f"{header_needle}\n", new_entry, "\n"]
        lines[anchor_idx:anchor_idx] = section
        changed = True

else:
    # README.md -- HTML-comment markers are safe here, GitHub renders them invisibly
    START, END = "<!-- TESTERS:START -->\n", "<!-- TESTERS:END -->\n"
    content = "".join(lines)
    entry = f"- @{username}\n"
    if "<!-- TESTERS:START -->" in content and "<!-- TESTERS:END -->" in content:
        pre, rest = content.split("<!-- TESTERS:START -->", 1)
        block, post = rest.split("<!-- TESTERS:END -->", 1)
        if f"@{username}" in block:
            print(f"@{username} already credited, nothing to do")
            sys.exit(0)
        if block and not block.endswith("\n"):
            block += "\n"
        block += entry
        content = pre + "<!-- TESTERS:START -->" + block + "<!-- TESTERS:END -->" + post
        changed = True
    else:
        anchor = "**Check out my other addons/projects:**"
        section = f"\n**Testers & Suggestions:**\n\n{START}{entry}{END}\n\n"
        if anchor in content:
            content = content.replace(anchor, section + anchor, 1)
        else:
            content = content.rstrip("\n") + "\n" + section
        changed = True
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"credited @{username}" if changed else "no change")
    sys.exit(0)

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"credited @{username}")
