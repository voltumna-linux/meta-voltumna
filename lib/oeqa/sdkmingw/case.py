# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

import subprocess
import os
import tempfile
import shutil
import bb

from oeqa.core.utils.path import remove_safe
from oeqa.sdk.case import OESDKTestCase

from oeqa.utils.subprocesstweak import errors_have_output
errors_have_output()

class OESDKMinGWTestCase(OESDKTestCase):
    def setUp(self):
        super().setUp()

        self.test_dir = tempfile.mkdtemp(prefix=self.__class__.__name__ + '-', dir=self.tc.sdk_dir)
        self.addCleanup(lambda: bb.utils.prunedir(self.test_dir))

        self.wine_test_dir = self.tc.wine_path(self.test_dir)

    def copyTestFile(self, src, dest=None):
        dest_path = dest or os.path.join(self.test_dir, os.path.basename(src))
        shutil.copyfile(src, dest_path)
        self.addCleanup(lambda: remove_safe(dest_path))

    def fetch(self, url, destdir=None, dl_dir=None, archive=None):
        if not destdir:
            destdir = self.test_dir

        if not dl_dir:
            dl_dir = self.td.get('DL_DIR', None)

        if not archive:
            from urllib.parse import urlparse
            archive = os.path.basename(urlparse(url).path)

        if dl_dir:
            tarball = os.path.join(dl_dir, archive)
            if os.path.exists(tarball):
                return tarball

        tarball = os.path.join(destdir, archive)
        subprocess.check_output(["wget", "-O", tarball, url])
        return tarball


    def _run(self, cmd):
        import shlex

        def strip_quotes(s):
            if s[0] == '"' and s[-1] == '"':
                return s[1:-1]
            return s

        command = ['wine', 'cmd', '/c', self.tc.wine_sdk_env, '>', 'NUL', '&&', 'cd', self.wine_test_dir, '&&']

        # Perform some massaging so that commands can be written naturally in
        # test cases. shlex.split() in Non-posix mode gets us most of the way
        # there, but it leaves the quotes around a quoted argument, so we
        # remove them manually.
        command.extend(strip_quotes(s) for s in shlex.split(cmd, posix=False))

        return subprocess.check_output(command, env=self.tc.get_wine_env(),
                stderr=subprocess.STDOUT, universal_newlines=True)

    def assertIsTargetElf(self, path):
        import oe.qa
        import oe.elf

        elf = oe.qa.ELFFile(path)
        elf.open()

        if not getattr(self, 'target_os', None):
            output = self._run("echo %OECORE_TARGET_OS%:%OECORE_TARGET_ARCH%")
            self.target_os, self.target_arch = output.strip().split(":")

        machine_data = oe.elf.machine_dict(None)[self.target_os][self.target_arch]
        (machine, osabi, abiversion, endian, bits) = machine_data

        self.assertEqual(machine, elf.machine())
        self.assertEqual(bits, elf.abiSize())
        self.assertEqual(endian, elf.isLittleEndian())

