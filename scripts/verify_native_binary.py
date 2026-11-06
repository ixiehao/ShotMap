#!/usr/bin/env python3
"""Verify the exact shipped CPU slices, deployment target and matching dSYM."""
import argparse
import re
import subprocess


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def verify(binary, architecture, symbols=None):
    expected = {"arm64", "x86_64"} if architecture == "universal" else {architecture}
    actual = set(output("xcrun", "lipo", "-archs", str(binary)).split())
    if actual != expected:
        raise ValueError(f"Expected {sorted(expected)}, found {sorted(actual)}: {binary}")
    for cpu in sorted(expected):
        commands = output("xcrun", "otool", "-arch", cpu, "-l", str(binary))
        minimum = re.search(r"cmd LC_BUILD_VERSION\b.*?\bminos (\S+)", commands, re.S)
        if minimum is None:
            minimum = re.search(r"cmd LC_VERSION_MIN_MACOSX\b.*?\bversion (\S+)", commands, re.S)
        if minimum is None or minimum[1] not in {"13.0", "13.0.0"}:
            raise ValueError(f"Expected macOS 13.0 for {cpu}: {binary}")
    if symbols is not None:
        def uuids(path):
            return set(re.findall(r"UUID: ([\w-]+) \(([^)]+)\)", output("xcrun", "dwarfdump", "--uuid", str(path))))
        binary_uuids, symbol_uuids = uuids(binary), uuids(symbols)
        if not binary_uuids or binary_uuids != symbol_uuids or {cpu for _, cpu in binary_uuids} != expected:
            raise ValueError(f"Missing or mismatched dSYM: {symbols}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["arm64", "x86_64", "universal"], required=True)
    parser.add_argument("--symbols")
    parser.add_argument("binary")
    args = parser.parse_args()
    verify(args.binary, args.arch, args.symbols)
    print(f"Verified {args.arch}, macOS 13.0" + (", matching dSYM" if args.symbols else ""))
