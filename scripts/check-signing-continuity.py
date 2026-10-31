#!/usr/bin/env python3
"""Verify stable code identity, optionally across two different Parrot builds.

This checks the signing prerequisite for privacy permission continuity. It does
not grant permissions or assert that macOS has retained an existing grant.
"""
import pathlib
import subprocess
import sys


def requirement(app):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    result = subprocess.run(['codesign', '-d', '-r-', str(app)], capture_output=True, text=True, check=True)
    lines = (result.stdout + result.stderr).splitlines()
    value = next(line for line in lines if line.startswith('designated =>') or line.startswith('# designated =>'))
    if 'cdhash' in value:
        raise ValueError(f'{app}: binary-hash identity changes on rebuild; use a stable signing certificate')
    return value.removeprefix('# ')


def main():
    if len(sys.argv) not in (2, 3):
        raise ValueError('Usage: check-signing-continuity.py APP [PREVIOUS_APP]')
    apps = [pathlib.Path(arg) for arg in sys.argv[1:]]
    requirements = [requirement(app) for app in apps]
    if len(requirements) == 2 and requirements[0] != requirements[1]:
        raise ValueError('Signing requirements differ; macOS may treat these as different apps')
    print('PASS: valid certificate signature; stable designated requirement' + (' matches both builds' if len(apps) == 2 else ''))
    print(requirements[0])


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, StopIteration) as error:
        sys.exit(f'FAIL: {error}')
