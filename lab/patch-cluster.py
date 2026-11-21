#!/usr/bin/env python3
"""Merge an exercise overlay into a rendered manifest, preserving named lists.

Usage: python3 lab/patch-cluster.py lab/generated/pg-eu.yaml exercise/cluster.yaml
This changes the local manifest; apply it with kubectl after reviewing it.
"""
import os
import re
import pathlib
import sys
import yaml


def merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        for key, value in overlay.items():
            base[key] = merge(base[key], value) if key in base else value
        return base
    if isinstance(base, list) and isinstance(overlay, list):
        if all(isinstance(item, dict) and 'name' in item for item in base + overlay):
            by_name = {item['name']: item for item in base}
            for item in overlay:
                name = item['name']
                by_name[name] = merge(by_name[name], item) if name in by_name else item
            return list(by_name.values())
        return overlay
    return overlay


def main():
    target, overlay = map(pathlib.Path, sys.argv[1:])
    data = yaml.safe_load(target.read_text())
    text = os.path.expandvars(overlay.read_text())
    if re.search(r'\$\{[A-Z_]+\}', text):
        raise SystemExit('Export all required environment variables before applying this overlay')
    patch = yaml.safe_load(text)
    target.write_text(yaml.safe_dump(merge(data, patch), sort_keys=False))


if __name__ == '__main__':
    main()
