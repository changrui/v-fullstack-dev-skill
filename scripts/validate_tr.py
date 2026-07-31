#!/usr/bin/env python3
"""Validate .tr translation files for veb i18n format.

Each section (split on '-----\\n') must contain exactly one key\\nvalue pair.
Sections with zero keys, multiple keys, or empty values are flagged.

Usage:
    python3 scripts/validate_tr.py translations/
    python3 scripts/validate_tr.py translations/zh.tr translations/en.tr
"""
import sys
import os


def validate_tr(filepath: str) -> list[str]:
    """Return list of error strings for a .tr file."""
    errors = []
    with open(filepath, 'r', encoding='utf-8') as f:
        text = f.read()

    sections = text.split('-----\n')
    for i, section in enumerate(sections):
        section = section.strip()
        if not section:
            continue
        nl_pos = section.find('\n')
        if nl_pos < 0:
            errors.append(f"  Section {i+1}: no newline found — key and value on same line: {repr(section[:60])}")
            continue
        key = section[:nl_pos].strip()
        value = section[nl_pos + 1:].strip()
        if not key:
            errors.append(f"  Section {i+1}: empty key")
            continue
        if not value:
            errors.append(f"  Section {i+1}: key '{key}' has empty value")
            continue
        # Check for embedded newlines (multiple keys/values in one section)
        if '\n' in value:
            errors.append(f"  Section {i+1}: key '{key}' has value containing embedded newlines — "
                          f"likely missing '-----' separator. Value starts: {repr(value[:40])}")
    return errors


def main():
    paths = sys.argv[1:]
    if not paths:
        # Scan translations/ dir
        paths = [os.path.join('translations', f) for f in sorted(os.listdir('translations')) if f.endswith('.tr')]
        if not paths:
            print("No .tr files found. Usage: validate_tr.py <file.tr> [<file.tr> ...]")
            sys.exit(1)

    total_errors = 0
    for path in paths:
        if not os.path.exists(path):
            print(f"SKIP: {path} not found")
            continue
        errors = validate_tr(path)
        if errors:
            print(f"FAIL: {path}")
            for e in errors:
                print(e)
            total_errors += len(errors)
        else:
            print(f"OK: {path}")

    if total_errors:
        print(f"\n{total_errors} error(s) total")
        sys.exit(1)
    else:
        print("\nAll .tr files valid")
        sys.exit(0)


if __name__ == '__main__':
    main()
