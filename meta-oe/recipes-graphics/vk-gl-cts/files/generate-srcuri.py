#! /usr/bin/env python3

import json
import re
import os
import subprocess
import sys
import types
import urllib.parse


def resolve_commit(repo, ref):
    # If it looks like a SHA, just return that
    if re.match(r"[a-z0-9]{40}", ref):
        return ref

    # Otherwise it's probably a tag name so resolve it
    cmd = ("git", "ls-remote", "--tags", "--exit-code", repo, ref)
    ret = subprocess.run(cmd, check=True, text=True, capture_output=True)
    sha = ret.stdout.split(maxsplit=1)[0]
    assert len(sha) == 40
    return sha


def transform_git(repo_url, repo_ref, destination):
    parts = urllib.parse.urlparse(repo_url)
    protocol = parts.scheme
    parts = parts._replace(scheme="git")
    url = urllib.parse.urlunparse(parts)
    # Resolve the commit reference to a SHA
    sha = resolve_commit(repo_url, repo_ref)

    return url + f";protocol={protocol};nobranch=1;destsuffix={destination};rev={sha}"


def load_module(filename):
    import importlib.util

    spec = importlib.util.spec_from_file_location("fetchmodule", filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def convert_fetch(basedir):
    """
    Convert the external/fetch_sources.py data
    """
    fetch = load_module(os.path.join(basedir, "fetch_sources.py"))
    lines = []
    for p in fetch.PACKAGES:
        if isinstance(p, fetch.SourcePackage):
            # Ignore these as so far we can use the system copies
            pass
        elif isinstance(p, fetch.SourceFile):
            dest = "/".join(["git/external", p.baseDir, p.extractDir])
            url = f"{p.url};subdir={dest};sha256sum={p.checksum}"
            lines.append(f"    {url} \\")
        elif isinstance(p, fetch.GitRepo):
            dest = "/".join(["git/external", p.baseDir, p.extractDir])
            url = transform_git(p.httpsUrl, p.revision, dest)
            lines.append(f"    {url} \\")
        else:
            assert f"Unexpected {p=}"
    return lines


def convert_knowngood(basedir, destination):
    """
    Convert the """
    filename = os.path.join(basedir, "vulkan-validationlayers/src/scripts/known_good.json")
    try:
        with open(filename) as fp:
            data = json.load(fp, object_hook=lambda x: types.SimpleNamespace(**x))
    except FileNotFoundError:
        return []

    lines = []
    for repo in data.repos:
        # Skip repositories that are not needed on Linux (TODO: assumes linux target)
        if hasattr(repo, "build_platforms") and repo.build_platforms != "linux":
            continue

        # Switch the URL to use git: and save the original protocol
        parts = urllib.parse.urlparse(repo.url)
        protocol = parts.scheme
        parts = parts._replace(scheme="git")
        url = urllib.parse.urlunparse(parts)
        # Resolve the commit reference to a SHA
        sha = resolve_commit(repo.url, repo.commit)

        destsuffix = destination + "/" + repo.sub_dir

        url += f";protocol={protocol};nobranch=1;destsuffix={destsuffix};rev={sha}"
        lines.append(f"    {url} \\")
    return lines


def main():
    pv = sys.argv[1]
    basedir = sys.argv[2]

    print("""
#
# Generated by generate-srcuri.py, don't update manually")
#

RECIPE_UPGRADE_EXTRA_TASKS += "do_refresh_srcuri"

python __anonymous() {
    if d.getVar("PV") != "%s":
        bb.warn("-sources.inc out of date, run refresh_srcuri task")
}
""" % (pv))

    print('SRC_URI += " \\')
    lines = convert_fetch(basedir)
    print("\n".join(lines))
    print('"')

    #lines = convert_knowngood(sys.argv[1], "git/external/validation")
    #if lines:
    #    print('SRC_URI += " \\')
    #    print("\n".join(lines))
    #    print('"')
    #else:
    #    print("# Re-run")


if __name__ == "__main__":
    main()
