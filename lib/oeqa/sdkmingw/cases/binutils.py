# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

import os
import unittest

from oeqa.sdkmingw.case import OESDKMinGWTestCase

class BinutilsTest(OESDKMinGWTestCase):
    td_vars = ['MACHINE']

    def setUp(self):
        super().setUp()

        self.copyTestFile(os.path.join(self.tc.files_dir, 'test.c'))

        machine = self.td.get("MACHINE")
        if not (self.tc.hasHostPackage("packagegroup-cross-canadian-%s" % machine) or
                self.tc.hasHostPackage("^gcc-", regex=True)):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain a cross-canadian toolchain")
        if not (self.tc.hasHostPackage("packagegroup-cross-canadian-%s" % machine) or
                self.tc.hasHostPackage('binutils-cross-canadian-%s' % machine)):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain a binutils")

        self._run('%CC% -c -g test.c -o test.o')
        self._run('%CC% -o test test.o -lm')

    def test_strip(self):
        self._run('%STRIP% -s test')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_ar(self):
        self._run('%AR% -rcs lib.a test.o')
        self._run('%CC% -o test lib.a -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_ranlib(self):
        self._run('%AR% -rc lib.a test.o')
        self._run('%RANLIB% lib.a')
        self._run('%CC% -o test lib.a -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_objcopy(self):
        self._run('%OBJCOPY% -g test.o test_no_debug.o')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test_no_debug.o'))
        self._run('%CC% -o test test_no_debug.o -lm')
        self.assertIsTargetElf(os.path.join(self.test_dir, 'test'))

    def test_objdump(self):
        self._run('%OBJDUMP% -S test.o')

    def test_nm(self):
        self._run('%NM% test.o')


