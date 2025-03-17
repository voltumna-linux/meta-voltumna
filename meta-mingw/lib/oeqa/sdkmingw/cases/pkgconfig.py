# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

import os
import unittest

from oeqa.sdkmingw.case import OESDKMinGWTestCase

class PkgConfigTest(OESDKMinGWTestCase):
    def setUp(self):
        super().setUp()

        if not self.tc.hasHostPackage("nativesdk-pkgconfig"):
            raise unittest.SkipTest(self.__class__.__name__ + " class: SDK doesn't contain nativesdk-pkgconfig")

    def test_pkg_config(self):
        self._run('pkg-config --list-all')

