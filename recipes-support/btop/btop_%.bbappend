inherit update-alternatives

ALTERNATIVE:${PN} += "top"
ALTERNATIVE_LINK_NAME[top] = "${bindir}/top"
ALTERNATIVE_TARGET[top] = "${bindir}/btop"
ALTERNATIVE_PRIORITY[top] = "300"
