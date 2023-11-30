FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

#	file://sslgenkeys.service \
#	file://redirect.conf \
#
SRC_URI:append = " \
	file://default.conf \
	file://auth.conf \
	file://events.conf \
	file://http.conf \
	file://nginx.conf \
	file://status.conf \
	file://sshd-root \
	"

#SYSTEMD_SERVICE:${PN} += "sslgenkeys.service"

CFLAGS += " -DNDEBUG"

PACKAGECONFIG = "stub-status ssl http2 nchan http-auth-request auth-pam upload encrypt-session"
PACKAGECONFIG[stub-status] = "--with-http_stub_status_module,,"

DESCRIPTION:nchan = "Nchan is a scalable, flexible pub/sub server for the modern web, built as a module for the Nginx web server"
HOMEPAGE:nchan = "http://nchan.io/"
LICENSE:nchan = "MIT"
LIC_FILES_CHKSUM:nchan = "file://LICENCE;md5=c3ab23ddd6df351c3410c3aa31f6675f"
SRCREV:nchan = "8bbff16dc0abeaebb9a0c0c865504f87f0f93430"
SRC_URI:append = "git://github.com/abogani/nchan.git;protocol=https;branch=master;name=nchan;destsuffix=nchan-1.2.8"
PACKAGECONFIG[nchan] = "--add-module=../nchan-1.2.8,,"

DESCRIPTION:auth-pam = "Nginx module to use PAM for simple http authentication"
HOMEPAGE:auth-pam = "https://github.com/sto/ngx_http_auth_pam_module"
LICENSE:auth-pam = "BSD"
LIC_FILES_CHKSUM:auth-pam = "file://LICENCE;md5=c3ab23ddd6df351c3410c3aa31f6675f"
DEPENDS:append = " libpam"
SRCREV:auth-pam = "0e5545b3b19095f0388dd63e964361659a99fb3b"
SRC_URI:append = "git://github.com/abogani/ngx_http_auth_pam_module.git;protocol=https;branch=master;name=auth-pam;destsuffix=auth-pam-1.5.1"
PACKAGECONFIG[auth-pam] = "--add-module=../auth-pam-1.5.1,,"

DESCRIPTION:upload = "A module for nginx web server for handling file uploads using multipart/form-data encoding (RFC 1867)"
HOMEPAGE:upload = "http://www.grid.net.ru/nginx/upload.en.html"
LICENSE:upload = "BSD"
LIC_FILES_CHKSUM:upload = "file://LICENCE;md5=40edeb6e8250952d817fead4d6651fb4"
SRCREV:upload = "2f67cde5a0aaf7cffd43a71f5c4b443698909f4a"
SRC_URI:append = "git://github.com/vkholodkov/nginx-upload-module.git;protocol=https;branch=master;name=upload;destsuffix=upload-2.3.0"
PACKAGECONFIG[upload] = "--add-module=../upload-2.3.0,,"

DESCRIPTION:ndk = "The NDK is an Nginx module that is designed to extend the core functionality of the excellent Nginx webserver in a way that can be used as a basis of other Nginx modules"
HOMEPAGE:ndk = "https://github.com/vision5/ngx_devel_kit"
LICENSE:ndk = "BSD-3-Clause"
LIC_FILES_CHKSUM:ndk = "file://LICENSE;md5=005a7db35de6d299127dcce5e2a25cdb"
SRCREV:ndk = "a22dade76c838e5f377d58d007f65d35b5ce1df3"
SRC_URI:append = "git://github.com/vision5/ngx_devel_kit.git;protocol=https;branch=master;name=ndk;destsuffix=ndk-0.3.1"
PACKAGECONFIG[ndk] = "--add-module=../ndk-0.3.1,,"

DESCRIPTION:misc = "Various set_xxx directives added to nginx's rewrite module (md5/sha1, sql/json quoting, and many more)"
HOMEPAGE:misc = "https://github.com/openresty/set-misc-nginx-module"
LICENSE:misc = "BSD-2-Clause"
LIC_FILES_CHKSUM:misc = "file://${COREBASE}/meta/files/common-licenses/BSD-2-Clause;md5=cb641bc04cda31daea161b1bc15da69f"
SRCREV:misc = "f6639dc06c92ff301a845558f7b8a1ccef069997"
SRC_URI:append = "git://github.com/openresty/set-misc-nginx-module.git;protocol=https;branch=master;name=misc;destsuffix=misc-0.32"
PACKAGECONFIG[misc] = "--add-module=../ndk-0.3.1 --add-module=../misc-0.32,,"

DESCRIPTION:encrypt-session = "Encrypt and decrypt nginx variable values"
HOMEPAGE:encrypt-session = "https://github.com/openresty/encrypted-session-nginx-module"
LICENSE:encrypt-session = "BSD-2-Clause"
LIC_FILES_CHKSUM:encrypt-session = "file://${COREBASE}/meta/files/common-licenses/BSD-2-Clause;md5=cb641bc04cda31daea161b1bc15da69f"
SRCREV:encrypt-session = "58161ba15b1e4c77d1c5ffad37b95074b1084560"
SRC_URI:append = "git://github.com/openresty/encrypted-session-nginx-module.git;protocol=https;branch=master;name=encrypt-session;destsuffix=encrypt-session-0.0.8"
PACKAGECONFIG[encrypt-session] = "--add-module=../ndk-0.3.1 --add-module=../misc-0.32 --add-module=../encrypt-session-0.0.8,,"

NGINX_WWWDIR = "${WWWDIR}"

FILES:${PN} += "${nonarch_libdir}/tmpfiles.d ${NGINX_WWWDIR}"

do_install:append() {
	# Remove default html stuff
	rm -fr ${D}${NGINX_WWWDIR}/*

	# Install NchanSubscriber.js
#	install -d ${D}${NGINX_WWWDIR}/js
#	install -m 0644 ${WORKDIR}/nchan-*/NchanSubscriber.js ${D}${NGINX_WWWDIR}/js

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

	# Install PAM file
	install -d ${D}${sysconfdir}/pam.d
	install -m 0644 ${WORKDIR}/sshd-root ${D}${sysconfdir}/pam.d

	# Install new configuration directories and files
	install -d ${D}${sysconfdir}/${BPN}/location-conf.d
	install -m 0644 ${WORKDIR}/status.conf \
		${D}${sysconfdir}/${BPN}/location-conf.d/
	sed -i 's,/var/www/localhost/html,${NGINX_WWWDIR},g' ${WORKDIR}/default.conf
	install -m 0644 ${WORKDIR}/default.conf \
		${WORKDIR}/auth.conf ${D}${sysconfdir}/${BPN}/server-conf.d/
	install -m 0644 ${WORKDIR}/http.conf ${WORKDIR}/events.conf \
		${D}${sysconfdir}/${BPN}/conf.d/
	install -m 0644 ${WORKDIR}/nginx.conf ${D}${sysconfdir}/${BPN}/

	# Install SSL generation keys service
#	install -d ${D}${systemd_unitdir}/system
#	install -m 0644 ${WORKDIR}/sslgenkeys.service ${D}${systemd_unitdir}/system
}

USERADD_PARAM:${PN} = " \
    --system --no-create-home \
    --home ${NGINX_WWWDIR} \
    --groups www-data,shadow \
    --user-group ${NGINX_USER}"
