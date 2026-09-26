#!/usr/bin/env python3
"""Prepare a signed appcast from an already notarized DMG. Does not deploy."""
import argparse
import os
import json
from pathlib import Path
import subprocess
import appcast_core
import sparkle_support

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("release_directory", type=Path)
parser.add_argument("output", type=Path, help="New directory; must not already exist")
parser.add_argument("--ed-key-stdin", action="store_true", help="Read protected Sparkle key from the environment")
args = parser.parse_args()
sparkle_support.configuration()
receipt = json.loads((args.release_directory / "release-receipt.json").read_text())
if not all(receipt.get(key) for key in ["notarized", "stapled", "signed"]):
    raise SystemExit("Only signed, notarized and stapled releases can enter the appcast")
source = appcast_core.one_release_dmg(args.release_directory)
filename = f"storagedaddy-{receipt['version']}-build{receipt['build']}-arm64.dmg"
copied = appcast_core.stage_dmg(source, args.output, filename, receipt["dmgSha256"])
tool = sparkle_support.ROOT / ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
key = os.environ.get("SPARKLE_ED25519_PRIVATE_KEY") if args.ed_key_stdin else None
if args.ed_key_stdin and not key:
    raise SystemExit("Protected Sparkle signing key is missing")
signing = ["--ed-key-file", "-"] if args.ed_key_stdin else ["--account", "storagedaddy-updates"]
subprocess.run([str(tool), *signing, "--download-url-prefix",
                "https://storage.daddyrad.com/updates/", str(args.output)],
               check=True, input=key, text=True)
feed = args.output / "appcast.xml"
appcast_core.validate_signed_feed(
    feed, f"https://storage.daddyrad.com/updates/{filename}", copied.stat().st_size
)
print(feed)
