#!/usr/bin/env python3
"""Resolve a Flipper app-catalog appid to its source location + category.

Usage:
  catalog.py resolve <catalog_dir> <appid>   -> prints KEY=VALUE lines
  catalog.py list <catalog_dir> [category]   -> prints "<category>/<appid>" lines
"""
import os
import re
import shlex
import sys


def _base(catalog):
    # catalog repo holds categories under applications/
    apps = os.path.join(catalog, "applications")
    return apps if os.path.isdir(apps) else catalog


def find_manifest(catalog, appid):
    catalog = _base(catalog)
    for cat in sorted(os.listdir(catalog)):
        d = os.path.join(catalog, cat, appid)
        m = os.path.join(d, "manifest.yml")
        if os.path.isfile(m):
            return cat, m
    return None, None


def field(text, key):
    m = re.search(rf"^\s*{key}:\s*(.+?)\s*$", text, re.M)
    return m.group(1).strip().strip('"').strip("'") if m else ""


def resolve(catalog, appid):
    cat, manifest = find_manifest(catalog, appid)
    if not manifest:
        sys.exit(f"app '{appid}' not found in catalog")
    blk = open(manifest, encoding="utf-8", errors="replace").read().split("description:")[0]
    origin = field(blk, "origin")
    commit = field(blk, "commit_sha")
    subdir = field(blk, "subdir")
    if not origin or not commit:
        sys.exit(f"'{appid}' manifest missing origin/commit_sha (non-git source?)")
    print(f"CATEGORY={shlex.quote(cat)}")
    print(f"ORIGIN={shlex.quote(origin)}")
    print(f"COMMIT={shlex.quote(commit)}")
    print(f"SUBDIR={shlex.quote(subdir)}")


def list_apps(catalog, category=None):
    catalog = _base(catalog)
    for cat in sorted(os.listdir(catalog)):
        if category and cat.lower() != category.lower():
            continue
        cdir = os.path.join(catalog, cat)
        if not os.path.isdir(cdir):
            continue
        for app in sorted(os.listdir(cdir)):
            if os.path.isfile(os.path.join(cdir, app, "manifest.yml")):
                print(f"{cat}/{app}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "resolve":
        resolve(sys.argv[2], sys.argv[3])
    elif cmd == "list":
        list_apps(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        sys.exit(__doc__)
