do_install:append:beaglebone() {
    kerneldir=${D}${KERNEL_BUILD_ROOT}${KERNEL_VERSION}
    install -d $kerneldir/build/arch/arm/boot/dts

    (
	cd ${S}/arch/arm/boot/dts

    	cp am335x-bone-common.dtsi am335x-boneblack-common.dtsi \
		am335x-boneblack.dts am33xx-clocks.dtsi \
		am33xx-l4.dtsi am33xx.dtsi tps65217.dtsi \
		$kerneldir/build/arch/arm/boot/dts
    )
}
