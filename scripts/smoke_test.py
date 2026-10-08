#!/usr/bin/env python3
"""Open the native setup app or submit a test-folder action through Launch Services."""
import argparse
import subprocess
from pathlib import Path
from urllib.parse import urlencode

from build import NAME, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launch-app", action="store_true", required=True,
                        help="Acknowledge that this test opens the app and possibly Terminal")
    parser.add_argument("--app", type=Path, default=ROOT / "build" / (NAME + ".app"))
    parser.add_argument("--mode", choices=("setup", "default", "new-window"), default="setup")
    args = parser.parse_args()
    command = ["/usr/bin/open", "-a", str(args.app.resolve())]
    if args.mode != "setup":
        folder = ROOT / "build/smoke" / "Folder with spaces and 'quotes' 日本語"
        folder.mkdir(parents=True, exist_ok=True)
        request = "openinterminal-app://open?" + urlencode([
            ("version", "1"), ("mode", args.mode), ("folder", folder.as_uri() + "/")])
        command.append(request)
        print("Expected Terminal working directory: " + str(folder), flush=True)
    subprocess.run(command, check=True)
    print("Launch Services accepted the request. Check the app/Finder and Terminal for the result.")


if __name__ == "__main__":
    main()
