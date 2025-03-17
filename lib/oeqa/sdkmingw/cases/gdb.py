# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

import unittest

from oeqa.sdkmingw.case import OESDKMinGWTestCase

class GdbTest(OESDKMinGWTestCase):
    td_vars = ['MACHINE']

    def setUp(self):
        super().setUp()

        machine = self.td.get("MACHINE")
        if not (self.tc.hasHostPackage("packagegroup-cross-canadian-%s" % machine) or
                self.tc.hasHostPackage("^gdb-", regex=True)):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain a cross-canadian toolchain")

    def test_gdb(self):
        self._run('%GDB% -ex quit')
