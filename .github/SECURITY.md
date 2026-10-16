# Security Policy

## Supported versions

Only the latest version of the Tamriel Trade Center, HarvestMap, ESO-Hub, ESOUI Auto-Updater is supported. Older scripts are not patched; download the current one.

## Reporting a vulnerability

Please report privately. Open this repository's Security tab and choose "Report a vulnerability". Don't post it as a public issue, an ESOUI comment or a Discord message until a fixed version is out. If you can't use GitHub, contact @APHONlC on ESOUI and don't put the details in a public post.

A useful report has the script version, your platform (Linux, macOS, SteamDeck or Windows), the steps to reproduce it and what an attacker could do with it.

## What counts

Anything in the script or its GitHub workflows that could harm a user or the repository: unsafe handling of downloaded data or file paths, editing Steam's `localconfig.vdf` or launch options in a way that runs something unintended, leaking your @Username or local data, leaking the repository's secrets, or pushing code nobody reviewed. Ordinary bugs and feature ideas go through Issues.

Out of scope: the websites and services the script talks to (Tamriel Trade Centre, HarvestMap, ESO-Hub, UESP) and their add-ons. Report those to their owners.

## What to expect

I maintain this alone, so replies take as long as they take. I'll confirm the report, fix it in a new version, and credit you if you want that.

## License

All rights reserved; see LICENSE.md. Testing the script on your own machine to find problems is fine. Copying, redistributing or selling it is not, and the license's opt-out for AI agents and bots applies to security research as well.
