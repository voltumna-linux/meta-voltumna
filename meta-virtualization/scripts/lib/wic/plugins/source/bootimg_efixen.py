#
# Copyright (c) 2026, Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# DESCRIPTION
# This implements the 'bootimg_efixen' source plugin class for 'wic'.
#
# Creates an EFI System Partition that boots Xen via GRUB chainloading
# xen.efi.  GRUB is installed as the default EFI boot application
# (bootx64.efi) for broad firmware compatibility (OVMF, Hyper-V, bare
# metal), and its grub.cfg chainloads xen.efi which handles the actual
# Xen/dom0 boot using native EFI boot services.
#
# Bootloader arguments use the --- separator convention (same as the
# bootimg_biosxen plugin) to split Xen hypervisor options from Linux
# kernel options:
#
#   bootloader --append="dom0_mem=512M console=com1 --- console=hvc0 root=/dev/sda2"
#
# Optional source param: initrd
#   part /boot --source bootimg-efixen --sourceparams="initrd=initramfs.cpio.gz"
#

import logging
import os
import shutil

from glob import glob

from wic import WicError
from wic.pluginbase import SourcePlugin
from wic.misc import (exec_cmd, exec_native_cmd,
                      get_bitbake_var, BOOTDD_EXTRA_SPACE)

logger = logging.getLogger('wic')


class BootimgEfiXenPlugin(SourcePlugin):
    """
    Create an EFI System Partition for Xen boot via GRUB chainloading xen.efi.
    """

    name = 'bootimg_efixen'

    @classmethod
    def do_configure_partition(cls, part, source_params, creator, cr_workdir,
                               oe_builddir, bootimg_dir, kernel_dir,
                               native_sysroot):
        hdddir = "%s/hdd/boot" % cr_workdir
        install_cmd = "install -d %s/EFI/BOOT" % hdddir
        exec_cmd(install_cmd)

        bootloader = creator.ks.bootloader

        # Split bootloader args at '---': Xen options --- Linux kernel options
        xen_options = "dom0_mem=512M console=com1,vga com1=115200,8n1"
        kernel_options = ""
        if bootloader.append:
            separator_pos = bootloader.append.find('---')
            if separator_pos != -1:
                xen_options = bootloader.append[:separator_pos].strip()
                kernel_options = bootloader.append[separator_pos + 3:].strip()
            else:
                kernel_options = bootloader.append.strip()

        kernel = get_bitbake_var("KERNEL_IMAGETYPE")
        if get_bitbake_var("INITRAMFS_IMAGE_BUNDLE") == "1":
            if get_bitbake_var("INITRAMFS_IMAGE"):
                kernel = "%s-%s.bin" % \
                    (get_bitbake_var("KERNEL_IMAGETYPE"),
                     get_bitbake_var("INITRAMFS_LINK_NAME"))

        # GRUB config: chainload xen.efi from the same directory
        grubefi_conf = ""
        grubefi_conf += "serial --unit=0 --speed=115200 --word=8 "
        grubefi_conf += "--parity=no --stop=1\n"
        grubefi_conf += "terminal_output console serial\n"
        grubefi_conf += "default=0\n"
        grubefi_conf += "timeout=%s\n\n" % bootloader.timeout
        grubefi_conf += "menuentry 'Xen' {\n"
        grubefi_conf += "    chainloader /EFI/BOOT/xen.efi\n"
        grubefi_conf += "}\n"

        cfg_path = "%s/EFI/BOOT/grub.cfg" % hdddir
        logger.debug("Writing GRUB chainloader config %s", cfg_path)
        with open(cfg_path, "w") as cfg:
            cfg.write(grubefi_conf)

        # Xen EFI config: xen.efi looks for xen.cfg in its own directory.
        # kernel= takes filename followed by kernel cmdline.
        kernel_line = "%s %s" % (kernel, kernel_options)

        xen_cfg = "[global]\n"
        xen_cfg += "default=dom0\n\n"
        xen_cfg += "[dom0]\n"
        xen_cfg += "options=%s\n" % xen_options
        xen_cfg += "kernel=%s\n" % kernel_line

        initrd = source_params.get('initrd')
        if initrd:
            initrds = initrd.split(';')
            xen_cfg += "ramdisk=%s\n" % initrds[0]

        xen_cfg_path = "%s/EFI/BOOT/xen.cfg" % hdddir
        logger.debug("Writing Xen EFI config %s", xen_cfg_path)
        with open(xen_cfg_path, "w") as cfg:
            cfg.write(xen_cfg)

    @classmethod
    def do_prepare_partition(cls, part, source_params, creator, cr_workdir,
                             oe_builddir, bootimg_dir, kernel_dir,
                             rootfs_dir, native_sysroot):
        if not kernel_dir:
            kernel_dir = get_bitbake_var("DEPLOY_DIR_IMAGE")
            if not kernel_dir:
                raise WicError("Couldn't find DEPLOY_DIR_IMAGE, exiting")

        hdddir = "%s/hdd/boot" % cr_workdir

        # Install GRUB EFI binary as the default boot application.
        # Save grub.cfg before the copy (grub-efi deploy overwrites EFI/BOOT/)
        shutil.copyfile("%s/hdd/boot/EFI/BOOT/grub.cfg" % cr_workdir,
                        "%s/grub.cfg" % cr_workdir)
        xen_cfg_bak = "%s/xen.cfg" % cr_workdir
        shutil.copyfile("%s/hdd/boot/EFI/BOOT/xen.cfg" % cr_workdir,
                        xen_cfg_bak)
        for mod in [x for x in os.listdir(kernel_dir)
                    if x.startswith("grub-efi-")]:
            cp_cmd = "cp -v -p %s/%s %s/EFI/BOOT/%s" % \
                (kernel_dir, mod, hdddir, mod[9:])
            exec_cmd(cp_cmd, True)
        shutil.move("%s/grub.cfg" % cr_workdir,
                    "%s/hdd/boot/EFI/BOOT/grub.cfg" % cr_workdir)
        shutil.move(xen_cfg_bak,
                    "%s/hdd/boot/EFI/BOOT/xen.cfg" % cr_workdir)

        out = glob(os.path.join(hdddir, 'EFI', 'BOOT', 'boot*.efi'))
        if not out:
            raise WicError("No GRUB EFI binary found. "
                           "Check that grub-efi is built.")

        # Install xen.efi alongside GRUB — chainloaded by grub.cfg
        machine = get_bitbake_var("MACHINE")
        xen_efi = "xen-%s.efi" % machine
        xen_src = os.path.join(kernel_dir, xen_efi)
        if not os.path.exists(xen_src):
            raise WicError("Xen EFI binary not found: %s" % xen_src)

        install_cmd = "install -m 0644 %s %s/EFI/BOOT/xen.efi" % \
            (xen_src, hdddir)
        exec_cmd(install_cmd)

        # Install dom0 kernel — xen.efi resolves paths in xen.cfg
        # relative to its own directory (EFI/BOOT/)
        kernel = get_bitbake_var("KERNEL_IMAGETYPE")
        if get_bitbake_var("INITRAMFS_IMAGE_BUNDLE") == "1":
            if get_bitbake_var("INITRAMFS_IMAGE"):
                kernel = "%s-%s.bin" % \
                    (get_bitbake_var("KERNEL_IMAGETYPE"),
                     get_bitbake_var("INITRAMFS_LINK_NAME"))

        install_cmd = "install -m 0644 %s/%s %s/EFI/BOOT/%s" % \
            (kernel_dir, kernel, hdddir, kernel)
        exec_cmd(install_cmd)

        # Install initrd files if specified
        initrd = source_params.get('initrd')
        if initrd:
            initrds = initrd.split(';')
            for rd in initrds:
                install_cmd = "install -m 0644 %s/%s %s/EFI/BOOT/%s" % \
                    (kernel_dir, rd, hdddir, os.path.basename(rd))
                exec_cmd(install_cmd)

        # Create FAT filesystem for the ESP
        du_cmd = "du --apparent-size -ks %s" % hdddir
        out = exec_cmd(du_cmd)
        blocks = int(out.split()[0])

        extra_blocks = part.get_extra_block_count(blocks)
        if extra_blocks < BOOTDD_EXTRA_SPACE:
            extra_blocks = BOOTDD_EXTRA_SPACE

        blocks += extra_blocks

        if blocks < part.fixed_size:
            blocks = part.fixed_size

        logger.debug("Added %d extra blocks to %s to get to %d total blocks",
                     extra_blocks, part.mountpoint, blocks)

        bootimg = "%s/boot.img" % cr_workdir
        label = part.label if part.label else "ESP"

        sector_size = getattr(creator, 'sector_size', 512)
        dosfs_cmd = "mkdosfs -v -n %s -i %s -S %d -C %s %d" % \
                    (label, part.fsuuid, sector_size, bootimg, blocks)
        exec_native_cmd(dosfs_cmd, native_sysroot)

        mcopy_cmd = "mcopy -v -p -i %s -s %s/* ::/" % (bootimg, hdddir)
        exec_native_cmd(mcopy_cmd, native_sysroot)

        chmod_cmd = "chmod 644 %s" % bootimg
        exec_cmd(chmod_cmd)

        du_cmd = "du --apparent-size -Lks %s" % bootimg
        out = exec_cmd(du_cmd)
        bootimg_size = out.split()[0]

        part.size = int(bootimg_size)
        part.source_file = bootimg
