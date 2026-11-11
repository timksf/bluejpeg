import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest


class VivadoExitTests(unittest.TestCase):
    def test_native_target_propagates_tcl_errors_and_exit_codes(self):
        script = Path(__file__).resolve().parents[4] / 'dep' / 'BSVTools' / 'scripts' / 'bsvTools.py'
        spec = importlib.util.spec_from_file_location('bsv_tools_exit_test', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        original_directory = Path.cwd()
        original_path = os.environ['PATH']
        tclsh = shutil.which('tclsh')
        self.assertIsNotNone(tclsh)
        try:
            with tempfile.TemporaryDirectory() as directory:
                os.chdir(directory)
                root = Path(directory)
                (root / 'rtl').mkdir()
                (root / 'rtl' / 'top.v').write_text('module top()\nendmodule\n')
                (root / 'fail.tcl').write_text('error expected_test_failure\n')
                (root / 'stub.tcl').write_text('proc create_project args {}\nproc read_verilog args {}\nproc close_project args {}\nsource temp.tcl\n')
                fake = root / 'vivado'
                fake.write_text(f'#!/bin/sh\nexec "{tclsh}" "{root / "stub.tcl"}"\n')
                fake.chmod(0o755)
                os.environ['PATH'] = str(root) + os.pathsep + original_path
                cli = SimpleNamespace(projectname='test', topModule='top', script=str(root / 'fail.tcl'), part='xc7a200tfbg484-2', verilog_dir=[str(root / 'rtl')], exclude='', includes='', bluespec_dir=str(root))
                with self.assertRaises(SystemExit) as error:
                    module.mkVivadoTCL(cli)
                self.assertEqual(error.exception.code, 1)
                fake.write_text('#!/bin/sh\nexit 7\n')
                with self.assertRaises(SystemExit) as error:
                    module.mkVivadoTCL(cli)
                self.assertEqual(error.exception.code, 7)
        finally:
            os.chdir(original_directory)
            os.environ['PATH'] = original_path


if __name__ == '__main__':
    unittest.main()
