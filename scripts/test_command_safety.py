#!/usr/bin/env python3
"""Exercise real AppleScript command generation without opening Terminal."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def instrument(source: str) -> str:
    replacements = {
        "on openFolders(folderTokens)\n": "on openFolders(folderTokens)\n    set collectedCommands to {}\n",
        '        tell application id "com.apple.Terminal"\n'
        '            -- With no "in" target, Terminal creates a new window.\n'
        '            do script terminalCommand\n'
        '        end tell': '        set end of collectedCommands to terminalCommand',
        '    tell application id "com.apple.Terminal" to activate': '    return collectedCommands',
    }
    for original, replacement in replacements.items():
        if source.count(original) != 1:
            raise AssertionError("Packaged source changed; update the inert instrumentation.")
        source = source.replace(original, replacement)
    return source


def main() -> None:
    source = (ROOT / "native/App/Resources/OpenNewTerminalWindow.applescript").read_text()
    with tempfile.TemporaryDirectory(prefix="oit-command-safety-") as directory:
        work = Path(directory).resolve()
        harness = work / "commands"
        subprocess.run([
            "xcrun", "clang", "-fobjc-arc", "-framework", "Foundation",
            str(ROOT / "native/Tests/CommandSafetyTests.m"), "-o", str(harness),
        ], check=True)
        inert_script = work / "inert.applescript"
        inert_script.write_text(instrument(source))
        names = [
            "ordinary folder",
            "quotes ' \\\" $() `echo nope` ; &",
            "caf\u00e9 \u2603 \u65e5\u672c\u8a9e",
            "prefix\x15touch INJECTED; #",
            "prefix\x03touch INJECTED; #",
            "first\ntouch INJECTED\n#",
            "trailing newline\n\n",
            "carriage\rtouch INJECTED;#",
            "tab\tand escape\x1b[A",
        ]
        folders = [work / name for name in names]
        for folder in folders:
            folder.mkdir()
        input_file = work / "paths.json"
        input_file.write_text(json.dumps([str(folder) for folder in folders]))
        result = subprocess.run([str(harness), str(inert_script), str(input_file)],
                                capture_output=True)
        if result.returncode:
            raise AssertionError(result.stderr.decode(errors="replace"))
        commands = json.loads(result.stdout)
        assert len(commands) == len(folders), "The AppleScript dropped folders."

        # A login-shell fixture records its actual cwd and exits. The wrapper's
        # inherited SHELL is changed only for these child processes.
        recorder = work / "record-shell"
        recorder.write_text('#!/bin/bash\n[ "$1" = "-l" ] || exit 90\nprintf \'%s\' "$PWD" > "$OIT_TEST_RECORD"\n')
        recorder.chmod(0o700)
        for index, (folder, command) in enumerate(zip(folders, commands)):
            assert command and all(32 <= ord(char) <= 126 for char in command), \
                "A raw control or non-ASCII character reached the PTY command."
            record = work / f"cwd-{index}"
            environment = os.environ.copy()
            environment.update(SHELL=str(recorder), OIT_TEST_RECORD=str(record))
            subprocess.run(["/bin/bash", "--noprofile", "--norc", "-c", command],
                           cwd=work, env=environment, check=True, timeout=10)
            actual = os.fsdecode(record.read_bytes())
            assert os.path.samefile(actual, folder), f"Wrong directory for case {index}."
            assert actual.endswith(folder.name), f"Path bytes changed for case {index}."
            assert not (work / "INJECTED").exists(), "A filename became a shell command."
            assert not (folder / "INJECTED").exists(), "A filename became a shell command."
        print(f"PASS: {len(folders)} control-character, Unicode, quoting, and trailing-newline cases.")


if __name__ == "__main__":
    main()
