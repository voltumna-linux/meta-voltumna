# Copyright 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)

from oeqa.sdk.testsdk import TestSDK
from oeqa.sdkmingw.context import OESDKMinGWTestContext, OESDKMinGWTestContextExecutor

class TestSDKMinGW(TestSDK):
    context_executor_class = OESDKMinGWTestContextExecutor
    context_class = OESDKMinGWTestContext

    def get_tcname(self, d):
        """
        Get the name of the SDK file
        """
        return d.expand("${SDK_DEPLOY}/${TOOLCHAIN_OUTPUTNAME}.${SDK_ARCHIVE_TYPE}")

    def extract_sdk(self, tcname, sdk_dir, d):
        """
        Extract the SDK to the specified location
        """
        import subprocess

        try:
            # TODO: It would be nice to try and extract the SDK in Wine to make
            # sure it is well formed
            
            # TODO: Extract SDK according to SDK_ARCHIVE_TYPE, need to change if
            # oe-core support other types.
            if d.getVar("SDK_ARCHIVE_TYPE") == "zip":
                subprocess.check_output(['unzip', '-d', sdk_dir, tcname])
            else:
                subprocess.check_output(['tar', '-xf', tcname, '-C', sdk_dir])

        except subprocess.CalledProcessError as e:
            bb.fatal("Couldn't install the SDK:\n%s" % e.output.decode("utf-8"))

    def setup_context(self, d):
        """
        Return a dictionary of additional arguments that should be passed to
        the context_class on construction
        """
        wine_prefix = d.getVar('TESTSDK_WINEPREFIX') or d.expand('${WORKDIR}/testimage-wine/')
        bb.utils.remove(wine_prefix, True)

        return {
            'wine_prefix': wine_prefix,
            'wine_arch': d.getVar('TESTSDK_WINEARCH') or 'win64',
            'wine_devices': {
                'w:': d.getVar("WORKDIR"),
            }
        }

