DESCRIPTION = "Software to control cameras manufactured by Hamamatsu Photonics"
HOMEPAGE = "https://www.hamamatsu.com/us/en/product/cameras/software/driver-software.html"
LICENSE = "CLOSED"

SRC_URI = " \
	https://www.hamamatsu.com/content/dam/hamamatsu-photonics/sites/static/sys/dcam-api-for-linux/tar-gz/DCAM-API_Lite_for_Linux_v24.4.6764.tar.gz;name=api-lite \
	"

SRC_URI[api-lite.sha256sum] = "a8038662e53fdf71f842470ffc060149a3463f3cd18ebeddd812d347fac8cfc7"
COMPATIBLE_HOST = "x86_64.*-linux"
