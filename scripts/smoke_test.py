#!/usr/bin/env python3
"""Run the packaged workflow once; this deliberately opens a Terminal window."""

import argparse
import subprocess
import zipfile

from build import NAME, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launch-terminal", action="store_true", required=True,
                        help="Confirm that the test should open Terminal")
    parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    archive = ROOT / "dist" / ("OpenInTerminal-%s-workflow.zip" % version)
    destination = ROOT / "build/smoke"
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as workflow:
        workflow.extractall(destination)
    folder = destination / "Folder with spaces and 'quotes' 日本語"
    folder.mkdir(exist_ok=True)
    print("Expected working directory: " + str(folder), flush=True)
    subprocess.run(["/usr/bin/automator", "-v", "-i", str(folder),
                    str(destination / (NAME + ".workflow"))], check=True)
    print("Workflow completed. Run pwd in the opened Terminal to verify its working directory.")
    print("The service was not installed or registered in Finder.")


if __name__ == "__main__":
    main()
