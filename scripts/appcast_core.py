"""Credential-free validation and staging for Daddy Sparkle appcasts."""

import base64
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET


SIGNATURE_ATTRIBUTE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def one_release_dmg(directory: Path) -> Path:
    sources = list(directory.glob("*.dmg"))
    if len(sources) != 1:
        raise ValueError("Expected exactly one release DMG")
    return sources[0]


def verify_apple_qualified(source: Path) -> None:
    subprocess.run(["codesign", "--verify", "--verbose=2", str(source)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(source)], check=True)


def checksum_from_sums(source: Path, sums: Path) -> str:
    if not sums.is_file():
        raise ValueError("Missing SHA256SUMS; expected the post-staple release checksum record")
    entries = []
    for line in sums.read_text().splitlines():
        fields = line.split()
        if len(fields) == 2 and re.fullmatch(r"[0-9a-fA-F]{64}", fields[0]) and fields[1] == source.name:
            entries.append(fields[0].lower())
    if len(entries) != 1:
        raise ValueError("Release checksum record must contain exactly one matching DMG")
    if sha256_file(source) != entries[0]:
        raise ValueError("Release checksum mismatch")
    return entries[0]


def stage_dmg(source: Path, output: Path, filename: str, expected_sha256: str) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.dmg", filename):
        raise ValueError("Unsafe update DMG filename")
    if not isinstance(expected_sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha256):
        raise ValueError("Invalid release checksum")
    if sha256_file(source) != expected_sha256.lower():
        raise ValueError("Release checksum mismatch")
    output.mkdir(parents=True, exist_ok=False)
    copied = output / filename
    shutil.copy2(source, copied)
    if sha256_file(copied) != expected_sha256.lower():
        raise ValueError("Copied update checksum mismatch")
    return copied


def validate_signed_feed(feed: Path, expected_url: str, expected_length: int) -> None:
    root = ET.parse(feed).getroot()
    enclosures = root.findall("./channel/item/enclosure")
    if len(enclosures) != 1:
        raise ValueError("Expected exactly one update enclosure")
    enclosure = enclosures[0]
    if enclosure.get("url") != expected_url or enclosure.get("length") != str(expected_length):
        raise ValueError("Update enclosure does not match the staged DMG")
    signature = enclosure.get(SIGNATURE_ATTRIBUTE)
    try:
        decoded = base64.b64decode(signature or "", validate=True)
    except ValueError as error:
        raise ValueError("Unsigned or invalid update enclosure") from error
    if len(decoded) != 64:
        raise ValueError("Unsigned or invalid update enclosure")
