#!/usr/bin/env python3
"""Regression tests for Taskfile validate fail-fast behavior."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


TASKFILE_PATH = Path(__file__).resolve().parents[2] / "Taskfile.yml"


class TaskfileValidateFailFastTests(unittest.TestCase):
    """Ensure validate subtasks fail loudly when checks fail."""

    def test_validate_subtasks_do_not_ignore_errors(self) -> None:
        """validate:* tasks must not contain ignore_error suppression."""
        text = TASKFILE_PATH.read_text(encoding="utf-8")

        for task_name in (
            "validate:images",
            "validate:oci",
            "validate:proxmox",
            "validate:talos",
            "validate:cost",
        ):
            block_pattern = (
                rf"(?ms)^  {re.escape(task_name)}:\n(.*?)(?=^  [^ \n][^:]*:|\Z)"
            )
            match = re.search(block_pattern, text)
            self.assertIsNotNone(match, f"Task block not found: {task_name}")
            block = match.group(1)
            self.assertNotIn(
                "ignore_error: true",
                block,
                f"{task_name} should fail fast instead of ignoring errors",
            )


if __name__ == "__main__":
    unittest.main()
