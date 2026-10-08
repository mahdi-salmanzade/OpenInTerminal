"""Exercise the service action without launching Terminal or any other GUI app."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ACTION_PATH = PROJECT_ROOT / "src" / "open-in-terminal.sh"


class FolderActionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="open-in-terminal-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.call_log = self.root / "open-calls.jsonl"
        self.failure_marker = self.root / "fail-open"

        # Instrument a temporary copy, keeping the shipped action free of
        # environment-controlled command substitutions or test-only branches.
        recorder = self.root / "record_open.py"
        recorder.write_text(
            "import json, pathlib, sys\n"
            f"log = pathlib.Path({str(self.call_log)!r})\n"
            "with log.open('a', encoding='utf-8') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            f"sys.exit(7 if pathlib.Path({str(self.failure_marker)!r}).exists() else 0)\n",
            encoding="utf-8",
        )
        stub = self.root / "mock-open"
        stub.write_text(
            "#!/bin/bash\n"
            f"exec {shlex.quote(sys.executable)} {shlex.quote(str(recorder))} \"$@\"\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)
        source = ACTION_PATH.read_text(encoding="utf-8")
        self.assertEqual(source.count("/usr/bin/open"), 1)
        self.action = self.root / "action.sh"
        self.action.write_text(
            source.replace("/usr/bin/open", shlex.quote(str(stub))),
            encoding="utf-8",
        )

    def run_action(self, *arguments):
        return subprocess.run(
            ["/bin/bash", str(self.action), *map(str, arguments)],
            cwd=str(self.root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
            check=False,
        )

    def calls(self):
        if not self.call_log.exists():
            return []
        return [
            json.loads(line)
            for line in self.call_log.read_text(encoding="utf-8").splitlines()
        ]

    def folder(self, name):
        path = self.root / name
        path.mkdir()
        return path

    def test_opens_a_folder_in_terminal(self):
        folder = self.folder("Documents")
        result = self.run_action(folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.calls(), [["-b", "com.apple.Terminal", str(folder)]])

    def test_preserves_special_characters_and_multiple_folder_arguments(self):
        names = [
            "with spaces",
            "both 'single' and \"double\" quotes",
            "日本語 café 📁",
            "line one\nline two",
            "$(touch INJECTED); `touch ALSO_INJECTED` & * ? [abc] \\ $HOME",
            "-n",
        ]
        folders = [self.folder(name) for name in names]
        result = self.run_action(*folders)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls(),
            [["-b", "com.apple.Terminal", str(folder)] for folder in folders],
        )
        self.assertFalse((self.root / "INJECTED").exists())
        self.assertFalse((self.root / "ALSO_INJECTED").exists())

    def test_relative_folder_starting_with_dash_is_not_an_option(self):
        self.folder("-a")
        result = self.run_action("-a")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:2], ["-b", "com.apple.Terminal"])
        self.assertTrue(os.path.isabs(calls[0][2]))
        self.assertEqual(Path(calls[0][2]).resolve(), (self.root / "-a").resolve())

    def test_empty_selection_is_an_error(self):
        result = self.run_action()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("select at least one folder", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_empty_path_is_an_error(self):
        result = self.run_action("")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a folder", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_rejects_regular_files_scripts_and_missing_paths(self):
        plain_file = self.root / "notes.txt"
        plain_file.write_text("notes", encoding="utf-8")
        shell_script = self.root / "danger.command"
        shell_script.write_text("#!/bin/bash\ntouch EXECUTED\n", encoding="utf-8")
        shell_script.chmod(0o755)
        missing = self.root / "missing"
        result = self.run_action(plain_file, shell_script, missing)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count("not a folder"), 3)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.root / "EXECUTED").exists())

    def test_processes_valid_folders_when_other_inputs_are_invalid(self):
        first = self.folder("first")
        last = self.folder("last")
        missing = self.root / "missing"
        result = self.run_action(first, missing, last)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a folder", result.stderr)
        self.assertEqual(
            self.calls(),
            [
                ["-b", "com.apple.Terminal", str(first)],
                ["-b", "com.apple.Terminal", str(last)],
            ],
        )

    def test_accepts_symlinks_to_folders_but_rejects_symlinks_to_files(self):
        folder = self.folder("target folder")
        folder_link = self.root / "folder link"
        folder_link.symlink_to(folder, target_is_directory=True)
        file = self.root / "file.command"
        file.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        file_link = self.root / "file link"
        file_link.symlink_to(file)
        result = self.run_action(folder_link, file_link)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [["-b", "com.apple.Terminal", str(folder_link)]])

    def test_reports_launch_failures_and_keeps_processing(self):
        folders = [self.folder("first"), self.folder("second")]
        self.failure_marker.touch()
        result = self.run_action(*folders)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count("could not open folder"), 2)
        self.assertEqual(
            self.calls(),
            [["-b", "com.apple.Terminal", str(folder)] for folder in folders],
        )


if __name__ == "__main__":
    unittest.main()
