# Copyright (C) 2018 by Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT)
import os
import subprocess

from oeqa.sdk.context import OESDKTestContext, OESDKTestContextExecutor

from oeqa.utils.subprocesstweak import errors_have_output
errors_have_output()

class OESDKMinGWTestContext(OESDKTestContext):
    sdk_files_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "files")

    def __init__(self, td=None, logger=None, sdk_dir=None, sdk_env=None, wine_prefix=None,
            wine_arch=None, target_pkg_manifest=None, host_pkg_manifest=None):
        super(OESDKMinGWTestContext, self).__init__(td, logger, sdk_dir, sdk_env, target_pkg_manifest, host_pkg_manifest)
        self.wine_prefix = wine_prefix
        self.wine_arch = wine_arch
        self.wine_sdk_dir = self.wine_path(sdk_dir)
        self.wine_sdk_env = self.wine_path(sdk_env)

    def get_wine_env(self):
        env = os.environ.copy()

        # Turn off all Wine debug logging so it doesn't interfere with command output
        env['WINEDEBUG'] = '-all'

        env['WINEPREFIX'] = self.wine_prefix
        env['WINEARCH'] = self.wine_arch

        # Convenience variables to make test cases easier to write
        env['SDK_DIR'] = getattr(self, 'wine_sdk_dir', '')

        # Set the language. If this is not set to a valid language, then
        # program that use glib will attempt to determine the language from
        # stdin, which results in an error, fallback to "UTF-8" which is
        # invalid and crash
        env["LANG"] = "C.UTF-8"

        return env

    def wine_path(self, p):
        """
        Converts a host POSIX path to a path in Wine
        """
        o = subprocess.check_output(['wine', 'winepath', '-w', p], env=self.get_wine_env())
        return o.decode('utf-8').rstrip()


class OESDKMinGWTestContextExecutor(OESDKTestContextExecutor):
    _context_class = OESDKMinGWTestContext

    name = 'sdk-mingw'
    help = 'MinGW sdk test component'
    description = 'executes MinGW sdk tests'

    default_cases = [os.path.join(os.path.abspath(os.path.dirname(__file__)),
            'cases')]

    def register_commands(self, logger, subparsers):
        super(OESDKMinGWTestContextExecutor, self).register_commands(logger, subparsers)

        wine_group  = self.parser.add_argument_group('wine options')
        wine_group.add_argument('--wine-prefix', action='store',
            help='Wine prefix (bottle). Default is $SDK_DIR/.wine')
        wine_group.add_argument('--wine-arch', action='store', choices=('win32', 'win64'),
            default='win64', help='Wine architecture. Defaults to %(default)s')

    def _process_args(self, logger, args):
        super(OESDKMinGWTestContextExecutor, self)._process_args(logger, args)
        self.tc_kwargs['init']['wine_prefix'] = args.wine_prefix or os.path.join(args.sdk_dir, '.wine')
        self.tc_kwargs['init']['wine_arch'] = args.wine_arch

_executor_class = OESDKMinGWTestContextExecutor

