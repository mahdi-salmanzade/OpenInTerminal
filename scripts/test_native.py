#!/usr/bin/env python3
"""Compile and run native request-boundary checks without launching GUI apps."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
output = ROOT / "build/tests"
output.mkdir(parents=True, exist_ok=True)
subprocess.run([
    "xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
    "-I", str(ROOT / "native/Shared"), "-framework", "Foundation",
    str(ROOT / "native/Shared/OITRequest.m"), str(ROOT / "native/Tests/RequestTests.m"),
    "-o", str(output / "RequestTests"),
], check=True)
subprocess.run([str(output / "RequestTests")], check=True)
