#!/usr/bin/env python3
"""Flatten a llama-server models.ini preset ([*] + [<section>]) into CLI args.

Lets single-model mode (engine/bin/llama-up.sh single <section>) reuse exactly
the same tuning as router mode (--models-preset), so the flags are never
duplicated between a shell script and the INI.

Usage:
    ini2args.py models.ini qwen36-coder            # one arg per line (for mapfile)
    ini2args.py models.ini qwen36-coder --shell    # shell-quoted single line
    ini2args.py models.ini --list                  # list preset sections
    ini2args.py models.ini qwen36-coder --get model

Rules:
    key = true        ->  --key
    key = false       ->  --no-key
    key = <value>     ->  --key <value>   (surrounding double quotes stripped)
    version = N       ->  ignored (preset-file metadata, not a flag)
"""
import configparser
import shlex
import sys

GLOBAL = "*"
META_KEYS = {"version"}


def load(path: str) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(
        interpolation=None,
        comment_prefixes=(";", "#"),
        inline_comment_prefixes=None,
        default_section="__configparser_default__",  # keep [*] an ordinary section
        strict=True,
    )
    cp.optionxform = str  # preserve key case
    with open(path, encoding="utf-8") as fh:
        # Top-level keys (e.g. "version = 1") precede the first section header.
        cp.read_string("[__top__]\n" + fh.read(), source=path)
    return cp


def unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] == '"':
        return v[1:-1]
    return v


def merged(cp: configparser.ConfigParser, section: str) -> dict:
    if section not in cp:
        raise SystemExit(f"error: preset [{section}] not found. Available: {', '.join(presets(cp))}")
    out: dict = {}
    if GLOBAL in cp:
        out.update(cp[GLOBAL])
    out.update(cp[section])
    return {k: unquote(v) for k, v in out.items() if k not in META_KEYS}


def presets(cp: configparser.ConfigParser) -> list:
    return [s for s in cp.sections() if s not in ("__top__", GLOBAL)]


def to_args(opts: dict) -> list:
    args: list = []
    for k, v in opts.items():
        low = v.lower()
        if low == "true":
            args.append(f"--{k}")
        elif low == "false":
            args.append(f"--no-{k}")
        else:
            args += [f"--{k}", v]
    return args


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cp = load(argv[1])
    if "--list" in argv:
        print("\n".join(presets(cp)))
        return 0
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    opts = merged(cp, argv[2])
    if "--get" in argv:
        key = argv[argv.index("--get") + 1]
        if key not in opts:
            return 1
        print(opts[key])
        return 0
    args = to_args(opts)
    if "--shell" in argv:
        print(" ".join(shlex.quote(a) for a in args))
    else:
        print("\n".join(args))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
