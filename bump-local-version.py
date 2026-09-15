#!/usr/bin/env python3
"""Set package.json version above the newest upstream tag AND the installed app,
so the local build is never seen as a downgrade. Safe to re-run."""
import json, re, subprocess, sys, os, plistlib

PKG = 'package.json'

def newest_upstream_tag():
    subprocess.run(['git','fetch','--tags','upstream'], capture_output=True)
    out = subprocess.run(['git','tag','--list','v1.*','--sort=-v:refname'],
                         capture_output=True, text=True).stdout.split()
    for t in out:
        m = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', t)
        if m:
            return tuple(int(x) for x in m.groups())
    return (0,0,0)

def installed_versions():
    found = []
    for app in ('/Applications/Orca.app','/Applications/Orca-Bob.app'):
        p = os.path.join(app,'Contents','Info.plist')
        if os.path.exists(p):
            with open(p,'rb') as f:
                v = plistlib.load(f).get('CFBundleShortVersionString','')
            m = re.match(r'(\d+)\.(\d+)\.(\d+)', v or '')
            if m:
                found.append(tuple(int(x) for x in m.groups()))
    return found

def main():
    tag = newest_upstream_tag()
    highest = max([tag] + installed_versions())
    # Why: build:mac appends a -local.* PRERELEASE suffix, which semver ranks BELOW
    # its own base version. So the base must be strictly greater than anything present.
    target = (highest[0], highest[1], highest[2] + 1)
    new = '%d.%d.%d' % target

    d = json.load(open(PKG))
    old = d['version']
    if old == new:
        print('already at', new); return 0
    src = open(PKG).read()
    assert src.count('"version": "%s"' % old) == 1
    open(PKG,'w').write(src.replace('"version": "%s"' % old, '"version": "%s"' % new, 1))
    print('newest upstream tag : v%d.%d.%d' % tag)
    print('installed apps      :', ['%d.%d.%d' % v for v in installed_versions()])
    print('version %s -> %s' % (old, new))
    return 0

if __name__ == '__main__':
    sys.exit(main())
