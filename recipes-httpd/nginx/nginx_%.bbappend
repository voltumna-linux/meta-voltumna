FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://default.conf \
	file://events.conf \
	file://http.conf \
	file://nginx.conf \
	file://auth.conf \
	file://status.conf \
	file://openssl.conf \
	"

DEPENDS += "openssl"

PACKAGECONFIG = "stub-status ssl http2 nchan http-auth-request auth-pam upload encrypt-session"

PACKAGECONFIG[stub-status] = "--with-http_stub_status_module,,"

DESCRIPTION_nchan = "Nchan is a scalable, flexible pub/sub server for the modern web, built as a module for the Nginx web server"
HOMEPAGE_nchan = "http://nchan.io/"
LICENSE_nchan = "MIT"
LIC_FILES_CHKSUM_nchan = "file://LICENCE;md5=c3ab23ddd6df351c3410c3aa31f6675f"
SRCREV_nchan = "82abfccf9ca5545b2e90af2ac8156ac7da0ce203"
SRC_URI_append += "git://github.com/abogani/nchan.git;protocol=https;branch=master;name=nchan;destsuffix=nchan-1.2.7"
PACKAGECONFIG[nchan] = "--add-module=${WORKDIR}/nchan-1.2.7,,"

DESCRIPTION_auth-pam = "Nginx module to use PAM for simple http authentication"
HOMEPAGE_auth-pam = "https://github.com/sto/ngx_http_auth_pam_module"
LICENSE_auth-pam = "BSD"
LIC_FILES_CHKSUM_auth-pam = "file://LICENCE;md5=c3ab23ddd6df351c3410c3aa31f6675f"
DEPENDS += "libpam"
SRCREV_auth-pam = "0e5545b3b19095f0388dd63e964361659a99fb3b"
SRC_URI_append += "git://github.com/abogani/ngx_http_auth_pam_module.git;protocol=https;branch=master;name=auth-pam;destsuffix=auth-pam-1.5.1"
PACKAGECONFIG[auth-pam] = "--add-module=${WORKDIR}/auth-pam-1.5.1,,"

DESCRIPTION_upload = "A module for nginx web server for handling file uploads using multipart/form-data encoding (RFC 1867)"
HOMEPAGE_upload = "http://www.grid.net.ru/nginx/upload.en.html"
LICENSE_upload = "BSD"
LIC_FILES_CHKSUM_upload = "file://LICENCE;md5=40edeb6e8250952d817fead4d6651fb4"
SRCREV_upload = "2f67cde5a0aaf7cffd43a71f5c4b443698909f4a"
SRC_URI_append += "git://github.com/vkholodkov/nginx-upload-module.git;protocol=https;branch=master;name=upload;destsuffix=upload-2.3.0"
PACKAGECONFIG[upload] = "--add-module=${WORKDIR}/upload-2.3.0,,"

DESCRIPTION_ndk = "The NDK is an Nginx module that is designed to extend the core functionality of the excellent Nginx webserver in a way that can be used as a basis of other Nginx modules"
HOMEPAGE_ndk = "https://github.com/vision5/ngx_devel_kit"
LICENSE_ndk = "BSD-3-Clause"
LIC_FILES_CHKSUM_ndk = "file://LICENSE;md5=005a7db35de6d299127dcce5e2a25cdb"
SRCREV_ndk = "a22dade76c838e5f377d58d007f65d35b5ce1df3"
SRC_URI_append += "git://github.com/vision5/ngx_devel_kit.git;protocol=https;branch=master;name=ndk;destsuffix=ndk-0.3.1"
PACKAGECONFIG[ndk] = "--add-module=${WORKDIR}/ndk-0.3.1,,"

DESCRIPTION_misc = "Various set_xxx directives added to nginx's rewrite module (md5/sha1, sql/json quoting, and many more)"
HOMEPAGE_misc = "https://github.com/openresty/set-misc-nginx-module"
LICENSE_misc = "BSD-2-Clause"
LIC_FILES_CHKSUM_misc = "file://${COREBASE}/meta/files/common-licenses/BSD-2-Clause;md5=cb641bc04cda31daea161b1bc15da69f"
SRCREV_misc = "f6639dc06c92ff301a845558f7b8a1ccef069997"
SRC_URI_append += "git://github.com/openresty/set-misc-nginx-module.git;protocol=https;branch=master;name=misc;destsuffix=misc-0.32"
PACKAGECONFIG[misc] = "--add-module=${WORKDIR}/ndk-0.3.1 --add-module=${WORKDIR}/misc-0.32,,"

DESCRIPTION_encrypt-session = "Encrypt and decrypt nginx variable values"
HOMEPAGE_encrypt-session = "https://github.com/openresty/encrypted-session-nginx-module"
LICENSE_encrypt-session = "BSD-2-Clause"
LIC_FILES_CHKSUM_encrypt-session = "file://${COREBASE}/meta/files/common-licenses/BSD-2-Clause;md5=cb641bc04cda31daea161b1bc15da69f"
SRCREV_encrypt-session = "58161ba15b1e4c77d1c5ffad37b95074b1084560"
SRC_URI_append += "git://github.com/openresty/encrypted-session-nginx-module.git;protocol=https;branch=master;name=encrypt-session;destsuffix=encrypt-session-0.0.8"
PACKAGECONFIG[encrypt-session] = "--add-module=${WORKDIR}/ndk-0.3.1 --add-module=${WORKDIR}/misc-0.32 --add-module=${WORKDIR}/encrypt-session-0.0.8,,"

NGINX_WWWDIR = "${WWWDIR}"

FILES_${PN} += "${nonarch_libdir}/tmpfiles.d ${NGINX_WWWDIR}"

do_install_append() {
	# Remove html stuff
	rm -fr ${D}${NGINX_WWWDIR}

	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_nginx
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles

	# Move nginx's tmpfile to system directory
	install -d ${D}${nonarch_libdir}/tmpfiles.d
	mv ${D}${sysconfdir}/tmpfiles.d/nginx.conf ${D}${nonarch_libdir}/tmpfiles.d
	rmdir ${D}${sysconfdir}/tmpfiles.d

	# Disable logging to disk removing directory
	rm -fr ${D}${localstatedir}/log/
	sed -i '/log/d' ${D}${nonarch_libdir}/tmpfiles.d/nginx.conf

	# Remove old configuration files and directories
	rm -fr ${D}${sysconfdir}/${BPN}/${BPN}.conf ${D}${sysconfdir}/${BPN}/sites-* \
		${D}${sysconfdir}/${BPN}/modules-*

	# Install new configuration directories and files
	install -d ${D}${sysconfdir}/${BPN}/location-conf.d
	install -m 0644 ${WORKDIR}/status.conf ${D}${sysconfdir}/${BPN}/location-conf.d/
	sed -i 's,/var/www/localhost/html,${NGINX_WWWDIR}/html,g' ${WORKDIR}/auth.conf ${WORKDIR}/default.conf
	install -m 0644 ${WORKDIR}/default.conf ${WORKDIR}/auth.conf ${D}${sysconfdir}/${BPN}/server-conf.d/
	install -m 0644 ${WORKDIR}/http.conf ${WORKDIR}/events.conf ${D}${sysconfdir}/${BPN}/conf.d/
	install -m 0644 ${WORKDIR}/nginx.conf ${D}${sysconfdir}/${BPN}/

	# Make /auth and /authcookie work
	install -d ${D}${NGINX_WWWDIR}/html/
	touch ${D}${NGINX_WWWDIR}/html/auth
	touch ${D}${NGINX_WWWDIR}/html/authcookie
}

pkg_postinst_${PN}() {
	if test -z "$D"
	then
		if test ! -s ${sysconfdir}/ssl/public.pem
		then
			openssl req -x509 -new -newkey rsa:2048 -sha256 -nodes -days 358000 \
			-keyout ${sysconfdir}/ssl/private.key \
			-out ${sysconfdir}/ssl/public.pem \
			-config ${WORKDIR}/openssl.conf >/dev/null 2>&1
			chmod 400 ${sysconfdir}/ssl/private.key
		fi			
        fi
}
