# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

import os
import unittest

from oeqa.sdkmingw.case import OESDKMinGWTestCase

class GccCompileTest(OESDKMinGWTestCase):
    td_vars = ['MACHINE']

    def setUp(self):
        super().setUp()

        self.copyTestFile(os.path.join(self.tc.files_dir, 'test.c'))
        self.copyTestFile(os.path.join(self.tc.files_dir, 'test.cpp'))
        self.copyTestFile(os.path.join(self.tc.sdk_files_dir, 'testsdkmakefile'))

        machine = self.td.get("MACHINE")
        if not (self.tc.hasHostPackage("packagegroup-cross-canadian-%s" % machine) or
                self.tc.hasHostPackage("^gcc-", regex=True)):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain a cross-canadian toolchain")

    def test_gcc_compile(self):
        self._run('%CC% %CFLAGS% %LDFLAGS% test.c -o test -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_gcc_compile_and_link(self):
        self._run('%CC% %CFLAGS% -c test.c -o test.o')
        self._run('%CC% %LDFLAGS% -o test test.o -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test.o'))
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_gpp_compile(self):
        self._run('%CXX% %CXXFLAGS% %LDFLAGS% test.c -o test -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_gpp2_compile(self):
        self._run('%CXX% %CXXFLAGS% %LDFLAGS% test.cpp -o test -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_make(self):
        if not self.tc.hasHostPackage('nativesdk-make'):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain make")
        self._run('make -f testsdkmakefile')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

