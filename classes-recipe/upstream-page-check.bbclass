# Check the upstream version of recipes whose download page cannot be read
# with the standard UPSTREAM_CHECK_URI/UPSTREAM_CHECK_REGEX mechanism.
#
# That mechanism (bb.fetch2) extracts versions only from the <a href> links of
# the page in UPSTREAM_CHECK_URI. Upstreams which publish their downloads
# through JavaScript widgets, JSON feeds or plain <span>/<button> markup are
# invisible to it and the check always comes back empty.
#
# Inheriting this class fills in RECIPE_UPSTREAM_VERSION by applying
# UPSTREAM_CHECK_REGEX to the whole body of UPSTREAM_CHECK_URI instead of just
# its hyperlinks, so 'devtool latest-version', 'devtool check-upgrade-status'
# and 'devtool upgrade' report the real upstream version for such recipes too.
# The regex is applied with DOTALL semantics and, as the standard check does,
# when more than one version matches the highest one wins.
#
# The page is only downloaded when a devtool command queries the upstream
# version: a normal build never expands RECIPE_UPSTREAM_VERSION and never
# touches the network. If the fetch or the match fails the variable expands to
# nothing and devtool falls back to the standard link based check.
#
# Usage:
#     inherit upstream-page-check
#     UPSTREAM_CHECK_URI = "https://example.com/downloads"
#     UPSTREAM_CHECK_REGEX = "foo-(?P<pver>\d+\.\d+\.\d+)\.tar\.gz"
#
# The regex must capture the version in a named group called pver, like
# UPSTREAM_CHECK_REGEX does; underscores in the match are turned into dots.

UPSTREAM_CHECK_URI ?= "${HOMEPAGE}"
UPSTREAM_CHECK_REGEX ?= ""

RECIPE_UPSTREAM_VERSION = "${@upstream_page_check_version(d)}"

def upstream_page_check_version(d):
    import bb
    import re
    import urllib.request

    uri = (d.getVar('UPSTREAM_CHECK_URI') or '').strip()
    regex = d.getVar('UPSTREAM_CHECK_REGEX') or ''
    if not uri or not regex:
        return ''
    if '(?P<pver>' not in regex:
        bb.warn('upstream-page-check: UPSTREAM_CHECK_REGEX must capture the version as a (?P<pver>...) group')
        return ''
    try:
        pattern = re.compile(regex, re.S)
        # Note: no User-Agent header is sent on purpose, several download
        # sites (intel.com, supermicro.com) answer only the default urllib one.
        page = urllib.request.urlopen(uri, timeout=30).read().decode('utf-8', 'replace')
    except Exception as e:
        bb.note('upstream-page-check: cannot check %s: %s' % (uri, e))
        return ''

    latest = ''
    for m in pattern.finditer(page):
        version = (m.groupdict().get('pver') or '').replace('_', '.')
        if version and (not latest or bb.utils.vercmp_string(latest, version) < 0):
            latest = version
    return latest