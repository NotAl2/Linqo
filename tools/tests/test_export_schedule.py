import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell is required')
class ExportScheduleTests(unittest.TestCase):
    def test_recent_exports_skip_but_a_late_weekly_completion_does_not(self):
        script = Path(__file__).resolve().parents[2] / 'scripts/Export-Contributions.ps1'
        command = ("function global:node { $global:LASTEXITCODE = 0; Write-Output 'MOCK_EXPORT' }; "
                   "& '" + str(script).replace("'", "''") + "' -Scheduled")
        with tempfile.TemporaryDirectory(prefix='linqo-export-schedule-') as directory:
            for age, expected in [(86400000, False), (7 * 86400000 - 30000, True)]:
                with self.subTest(age=age):
                    (Path(directory) / 'checkpoint.json').write_text(
                        json.dumps({'last_success': time.time() * 1000 - age}), encoding='utf-8')
                    result = subprocess.run(
                        ['powershell.exe', '-NoProfile', '-NonInteractive',
                         '-ExecutionPolicy', 'RemoteSigned', '-Command', command],
                        env=dict(os.environ, LINQO_DATA_DIRECTORY=directory),
                        capture_output=True, text=True, check=True,
                    )
                    self.assertEqual('MOCK_EXPORT' in result.stdout, expected)


if __name__ == '__main__':
    unittest.main()
