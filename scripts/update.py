#!/usr/bin/env python3
"""Update reviewed source manifests, never package code or deployment configuration."""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OPENAI_REPO = "https://persistent.oaistatic.com/codex-app-prod/linux/deb"
CLAUDE_REPO = "https://downloads.claude.ai/claude-desktop/apt/stable"
OPENAI_KEY = "3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"
ARCHES = {"x86_64-linux": "amd64", "aarch64-linux": "arm64"}
PACKAGES = ("claude-desktop", "chatgpt-desktop", "coroslink")


def fetch(url):
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("only HTTPS sources are allowed")
    request = urllib.request.Request(url, headers={"User-Agent": "likarum-nix-packages"})
    with urllib.request.urlopen(request, timeout=120) as response:
        if urllib.parse.urlsplit(response.url).scheme != "https":
            raise ValueError("refusing non-HTTPS redirect")
        return response.read()


def version_key(version):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", version):
        raise ValueError(f"unexpected release version: {version!r}")
    return tuple(map(int, version.split(".")))


def stanzas(text):
    result = []
    for block in re.split(r"\n\s*\n", text.strip()):
        fields = {}
        for line in block.splitlines():
            if line and not line[0].isspace() and ": " in line:
                key, value = line.split(": ", 1)
                if key in fields:
                    raise ValueError(f"duplicate package field: {key}")
                fields[key] = value
        result.append(fields)
    return result


def select_package(text, name, arch, version=None):
    candidates = [p for p in stanzas(text) if p.get("Package") == name
                  and p.get("Architecture") == arch
                  and (version is None or p.get("Version") == version)]
    if not candidates:
        raise ValueError(f"missing {name} {arch} {version or 'release'}")
    return max(candidates, key=lambda p: version_key(p["Version"]))


def sri(hex_digest):
    if not re.fullmatch(r"[a-fA-F0-9]{64}", hex_digest):
        raise ValueError("invalid SHA256")
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode()


def deb_source(repo, name, stanza, arch):
    version = stanza["Version"]
    version_key(version)
    filename = stanza["Filename"]
    expected = f"{name}_{version}_{arch}.deb"
    if (not filename.startswith("pool/") or ".." in PurePosixPath(filename).parts
            or PurePosixPath(filename).name != expected or "?" in filename or "#" in filename):
        raise ValueError(f"unexpected package path: {filename!r}")
    return {"url": f"{repo}/{filename}", "hash": sri(stanza["SHA256"])}


def signed_openai_release():
    """Verify the index with a locally reviewed key; never execute Debian scripts."""
    key = ROOT / "pkgs/chatgpt-desktop/openai-archive-keyring.asc"
    with tempfile.TemporaryDirectory(prefix="nix-packages-gpg-") as tmp:
        env = dict(os.environ, GNUPGHOME=tmp)
        listing = subprocess.check_output(
            ["gpg", "--batch", "--with-colons", "--show-keys", str(key)], env=env, text=True)
        fingerprints = [line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:")]
        if not fingerprints or fingerprints[0] != OPENAI_KEY:
            raise ValueError("OpenAI signing key fingerprint changed; manual review required")
        keyring = Path(tmp) / "keyring.gpg"
        subprocess.run(["gpg", "--batch", "--dearmor", "--output", str(keyring), str(key)],
                       env=env, check=True)
        inrelease = Path(tmp) / "InRelease"
        inrelease.write_bytes(fetch(f"{OPENAI_REPO}/dists/stable/InRelease"))
        release = Path(tmp) / "Release"
        subprocess.run(["gpgv", "--keyring", str(keyring), "--output", str(release), str(inrelease)],
                       env=env, check=True)
        body = release.read_text()
    for line in body.splitlines():
        if line.startswith("Valid-Until: "):
            from email.utils import parsedate_to_datetime
            if parsedate_to_datetime(line[13:]) < dt.datetime.now(dt.timezone.utc):
                raise ValueError("expired signed index; refusing automatic update")
    hashes = {}
    in_sha256 = False
    for line in body.splitlines():
        if line == "SHA256:":
            in_sha256 = True
        elif line and not line[0].isspace():
            in_sha256 = False
        elif in_sha256:
            digest, size, path = line.split()
            hashes[path] = (digest, int(size))
    return hashes


def checked_index(data, digest, size):
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError("Packages index differs from the signed InRelease")
    return data.decode()


def deb_manifest(name, version=None):
    is_openai = name == "chatgpt-desktop"
    repo = OPENAI_REPO if is_openai else CLAUDE_REPO
    deb_name = "chatgpt" if is_openai else name
    hashes = signed_openai_release() if is_openai else None
    versions, sources = set(), {}
    for system, arch in ARCHES.items():
        path = f"main/binary-{arch}/Packages"
        data = fetch(f"{repo}/dists/stable/{path}")
        text = checked_index(data, *hashes[path]) if hashes is not None else data.decode()
        stanza = select_package(text, deb_name, arch, version)
        versions.add(stanza["Version"])
        sources[system] = deb_source(repo, deb_name, stanza, arch)
    if len(versions) != 1:
        raise ValueError("architectures have different releases; retry after publication completes")
    return {"version": versions.pop(), "sources": sources}


def coros_manifest(version=None):
    base = "https://api.github.com/repos/JunAkerBuilds/CorosLink/releases"
    suffix = f"tags/v{version}" if version else "latest"
    release = json.loads(fetch(f"{base}/{suffix}"))
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("refusing prerelease or draft")
    version = release["tag_name"].removeprefix("v")
    version_key(version)
    filename = f"CorosLink-{version}.AppImage"
    expected_url = f"https://github.com/JunAkerBuilds/CorosLink/releases/download/v{version}/{filename}"
    assets = [a for a in release["assets"] if a["name"] == filename]
    if len(assets) != 1 or assets[0]["browser_download_url"] != expected_url:
        raise ValueError("missing or unexpected CorosLink asset")
    # Hash the actual release binary. No signature is claimed for this upstream.
    digest = hashlib.sha256(fetch(expected_url)).hexdigest()
    advertised = assets[0].get("digest")
    if advertised and advertised != "sha256:" + digest:
        raise ValueError("CorosLink asset digest mismatch")
    return {"version": version, "sources": {"x86_64-linux": {
        "url": expected_url, "hash": sri(digest)}}}


def normalized(manifest):
    # Ignore legacy informational fields, compare the actual pin only.
    return {"version": manifest["version"], "sources": {
        system: {key: source[key] for key in ("url", "hash")}
        for system, source in manifest["sources"].items()}}


def validate_transition(old, new):
    if version_key(new["version"]) < version_key(old["version"]):
        raise ValueError("refusing automatic downgrade")
    if old["version"] == new["version"] and normalized(old) != normalized(new):
        raise ValueError("existing release URL/hash changed; manual investigation required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=PACKAGES)
    parser.add_argument("--check", action="store_true", help="exit 1 if an update exists; do not write")
    parser.add_argument("--verify", action="store_true", help="verify the current pin against upstream")
    args = parser.parse_args()
    file = ROOT / "pkgs" / args.package / "sources.json"
    old = json.loads(file.read_text())
    version = old["version"] if args.verify else None
    new = coros_manifest(version) if args.package == "coroslink" else deb_manifest(args.package, version)
    validate_transition(old, new)
    if args.verify or normalized(old) == normalized(new):
        print(f"{args.package}: verified {old['version']}")
        return
    print(f"{args.package}: {old['version']} -> {new['version']}")
    if args.check:
        raise SystemExit(1)
    # Atomic replacement; a failed fetch or verification never edits the old pin.
    with tempfile.NamedTemporaryFile(mode="w", dir=file.parent, delete=False) as tmp:
        json.dump(new, tmp, indent=2)
        tmp.write("\n")
    os.replace(tmp.name, file)


if __name__ == "__main__":
    main()
