#
# Copyright (c) 2013, Intel Corporation.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# DESCRIPTION
# This implements the 'direct' imager plugin class for 'wic'
#
# AUTHORS
# Tom Zanussi <tom.zanussi (at] linux.intel.com>
#

import logging
import os
import random
import shutil
import tempfile
import uuid

from time import strftime

from oe.path import copyhardlinktree

from wic import WicError
from wic.filemap import sparse_copy
from wic.ksparser import KickStart, KickStartError
from wic.pluginbase import PluginMgr, ImagerPlugin
from wic.misc import get_bitbake_var, exec_cmd, exec_native_cmd

logger = logging.getLogger('wic')

class DirectPlugin(ImagerPlugin):
    """
    Install a system into a file containing a partitioned disk image.

    An image file is formatted with a partition table, each partition
    created from a rootfs or other OpenEmbedded build artifact and dd'ed
    into the virtual disk. The disk image can subsequently be dd'ed onto
    media and used on actual hardware.
    """
    name = 'direct'

    def __init__(self, wks_file, rootfs_dir, bootimg_dir, kernel_dir,
                 native_sysroot, oe_builddir, options):
        try:
            self.ks = KickStart(wks_file)
        except KickStartError as err:
            raise WicError(str(err))

        # parse possible 'rootfs=name' items
        self.rootfs_dir = dict(rdir.split('=') for rdir in rootfs_dir.split(' '))
        self.bootimg_dir = bootimg_dir
        self.kernel_dir = kernel_dir
        self.native_sysroot = native_sysroot
        self.oe_builddir = oe_builddir

        self.debug = options.debug
        self.outdir = options.outdir
        self.compressor = options.compressor
        self.bmap = options.bmap
        self.no_fstab_update = options.no_fstab_update
        self.updated_fstab_path = None

        self.name = "%s-%s" % (os.path.splitext(os.path.basename(wks_file))[0],
                               strftime("%Y%m%d%H%M"))
        self.workdir = self.setup_workdir(options.workdir)
        self._image = None
        self.ptable_format = self.ks.bootloader.ptable
        self.parts = self.ks.partitions

        # as a convenience, set source to the boot partition source
        # instead of forcing it to be set via bootloader --source
        for part in self.parts:
            if not self.ks.bootloader.source and part.mountpoint == "/boot":
                self.ks.bootloader.source = part.source
                break

        image_path = self._full_path(self.workdir, self.parts[0].disk, "direct")
        self._image = PartitionedImage(image_path, self.ptable_format,
                                       self.parts, self.native_sysroot,
                                       options.extra_space)

    def setup_workdir(self, workdir):
        if workdir:
            if os.path.exists(workdir):
                raise WicError("Internal workdir '%s' specified in wic arguments already exists!" % (workdir))

            os.makedirs(workdir)
            return workdir
        else:
            return tempfile.mkdtemp(dir=self.outdir, prefix='tmp.wic.')

    def do_create(self):
        """
        Plugin entry point.
        """
        try:
            self.create()
            self.assemble()
            self.finalize()
            self.print_info()
        finally:
            self.cleanup()

    def update_fstab(self, image_rootfs):
        """Assume partition order same as in wks"""
        if not image_rootfs:
            return

        fstab_path = image_rootfs + "/etc/fstab"
        if not os.path.isfile(fstab_path):
            return

        with open(fstab_path) as fstab:
            fstab_lines = fstab.readlines()

        updated = False
        for part in self.parts:
            if not part.realnum or not part.mountpoint \
               or part.mountpoint == "/" or not (part.mountpoint.startswith('/') or part.mountpoint == "swap"):
                continue

            if part.use_uuid:
                if part.fsuuid:
                    # FAT UUID is different from others
                    if len(part.fsuuid) == 10:
                        device_name = "UUID=%s-%s" % \
                                       (part.fsuuid[2:6], part.fsuuid[6:])
                    else:
                        device_name = "UUID=%s" % part.fsuuid
                else:
                    device_name = "PARTUUID=%s" % part.uuid
            elif part.use_label:
                device_name = "LABEL=%s" % part.label
            else:
                # mmc device partitions are named mmcblk0p1, mmcblk0p2..
                prefix = 'p' if  part.disk.startswith('mmcblk') else ''
                device_name = "/dev/%s%s%d" % (part.disk, prefix, part.realnum)

            opts = part.fsopts if part.fsopts else "defaults"
            passno = part.fspassno if part.fspassno else "0"
            line = "\t".join([device_name, part.mountpoint, part.fstype,
                              opts, "0", passno]) + "\n"

            fstab_lines.append(line)
            updated = True

        if updated:
            self.updated_fstab_path = os.path.join(self.workdir, "fstab")
            with open(self.updated_fstab_path, "w") as f:
                f.writelines(fstab_lines)
            if os.getenv('SOURCE_DATE_EPOCH'):
                fstab_time = int(os.getenv('SOURCE_DATE_EPOCH'))
                os.utime(self.updated_fstab_path, (fstab_time, fstab_time))

    def _full_path(self, path, name, extention):
        """ Construct full file path to a file we generate. """
        return os.path.join(path, "%s-%s.%s" % (self.name, name, extention))

    #
    # Actual implemention
    #
    def create(self):
        """
        For 'wic', we already have our build artifacts - we just create
        filesystems from the artifacts directly and combine them into
        a partitioned image.
        """
        if not self.no_fstab_update:
            self.update_fstab(self.rootfs_dir.get("ROOTFS_DIR"))

        for part in self.parts:
            # get rootfs size from bitbake variable if it's not set in .ks file
            if not part.size:
                # and if rootfs name is specified for the partition
                image_name = self.rootfs_dir.get(part.rootfs_dir)
                if image_name and os.path.sep not in image_name:
                    # Bitbake variable ROOTFS_SIZE is calculated in
                    # Image._get_rootfs_size method from meta/lib/oe/image.py
                    # using IMAGE_ROOTFS_SIZE, IMAGE_ROOTFS_ALIGNMENT,
                    # IMAGE_OVERHEAD_FACTOR and IMAGE_ROOTFS_EXTRA_SPACE
                    rsize_bb = get_bitbake_var('ROOTFS_SIZE', image_name)
                    if rsize_bb:
                        part.size = int(round(float(rsize_bb)))

        self._image.prepare(self)
        self._image.layout_partitions()
        self._image.create()

    def assemble(self):
        """
        Assemble partitions into disk image
        """
        self._image.assemble()

    def finalize(self):
        """
        Finalize the disk image.

        For example, prepare the image to be bootable by e.g.
        creating and installing a bootloader configuration.
        """
        source_plugin = self.ks.bootloader.source
        disk_name = self.parts[0].disk
        if source_plugin:
            # Don't support '-' in plugin names
            source_plugin = source_plugin.replace("-", "_")
            plugin = PluginMgr.get_plugins('source')[source_plugin]
            plugin.do_install_disk(self._image, disk_name, self, self.workdir,
                                   self.oe_builddir, self.bootimg_dir,
                                   self.kernel_dir, self.native_sysroot)

        full_path = self._image.path
        # Generate .bmap
        if self.bmap:
            logger.debug("Generating bmap file for %s", disk_name)
            python = os.path.join(self.native_sysroot, 'usr/bin/python3-native/python3')
            bmaptool = os.path.join(self.native_sysroot, 'usr/bin/bmaptool')
            exec_native_cmd("%s %s create %s -o %s.bmap" % \
                            (python, bmaptool, full_path, full_path), self.native_sysroot)
        # Compress the image
        if self.compressor:
            logger.debug("Compressing disk %s with %s", disk_name, self.compressor)
            exec_cmd("%s %s" % (self.compressor, full_path))

    def print_info(self):
        """
        Print the image(s) and artifacts used, for the user.
        """
        msg = "The new image(s) can be found here:\n"

        extension = "direct" + {"gzip": ".gz",
                                "bzip2": ".bz2",
                                "xz": ".xz",
                                None: ""}.get(self.compressor)
        full_path = self._full_path(self.outdir, self.parts[0].disk, extension)
        msg += '  %s\n\n' % full_path

        msg += 'The following build artifacts were used to create the image(s):\n'
        for part in self.parts:
            if part.rootfs_dir is None:
                continue
            if part.mountpoint == '/':
                suffix = ':'
            else:
                suffix = '["%s"]:' % (part.mountpoint or part.label)
            rootdir = part.rootfs_dir
            msg += '  ROOTFS_DIR%s%s\n' % (suffix.ljust(20), rootdir)

        msg += '  BOOTIMG_DIR:                  %s\n' % self.bootimg_dir
        msg += '  KERNEL_DIR:                   %s\n' % self.kernel_dir
        msg += '  NATIVE_SYSROOT:               %s\n' % self.native_sysroot

        logger.info(msg)

    @property
    def rootdev(self):
        """
        Get root device name to use as a 'root' parameter
        in kernel command line.

        Assume partition order same as in wks
        """
        for part in self.parts:
            if part.mountpoint == "/":
                if part.uuid:
                    return "PARTUUID=%s" % part.uuid
                elif part.label and self.ptable_format != 'msdos':
                    return "PARTLABEL=%s" % part.label
                else:
                    suffix = 'p' if part.disk.startswith('mmcblk') else ''
                    return "/dev/%s%s%-d" % (part.disk, suffix, part.realnum)

    def cleanup(self):
        if self._image:
            self._image.cleanup()

        # Move results to the output dir
        if not os.path.exists(self.outdir):
            os.makedirs(self.outdir)

        for fname in os.listdir(self.workdir):
            path = os.path.join(self.workdir, fname)
            if os.path.isfile(path):
                shutil.move(path, os.path.join(self.outdir, fname))

        # remove work directory when it is not in debugging mode
        if not self.debug:
            shutil.rmtree(self.workdir, ignore_errors=True)

# Overhead of the MBR partitioning scheme (just one sector)
MBR_OVERHEAD = 1

# Overhead of the GPT partitioning scheme
GPT_OVERHEAD = 34

# Size of a sector in bytes
SECTOR_SIZE = 512

class PartitionedImage():
    """
    Partitioned image in a file.
    """

    def __init__(self, path, ptable_format, partitions, native_sysroot=None, extra_space=0):
        self.path = path  # Path to the image file
        self.numpart = 0  # Number of allocated partitions
        self.realpart = 0 # Number of partitions in the partition table
        self.primary_part_num = 0  # Number of primary partitions (msdos)
        self.extendedpart = 0      # Create extended partition before this logical partition (msdos)
        self.extended_size_sec = 0 # Size of exteded partition (msdos)
        self.logical_part_cnt = 0  # Number of total logical paritions (msdos)
        self.offset = 0   # Offset of next partition (in sectors)
        self.min_size = 0 # Minimum required disk size to fit
                          # all partitions (in bytes)
        self.ptable_format = ptable_format  # Partition table format
        # Disk system identifier
        if os.getenv('SOURCE_DATE_EPOCH'):
            self.identifier = random.Random(int(os.getenv('SOURCE_DATE_EPOCH'))).randint(1, 0xffffffff)
        else:
            self.identifier = random.SystemRandom().randint(1, 0xffffffff)

        self.partitions = partitions
        self.partimages = []
        # Size of a sector used in calculations
        sector_size_str = get_bitbake_var('WIC_SECTOR_SIZE')
        if sector_size_str is not None:
            try:
                self.sector_size = int(sector_size_str)
            except ValueError:
                self.sector_size = SECTOR_SIZE
        else:
            self.sector_size = SECTOR_SIZE

        self.native_sysroot = native_sysroot
        num_real_partitions = len([p for p in self.partitions if not p.no_table])
        self.extra_space = extra_space

        # calculate the real partition number, accounting for partitions not
        # in the partition table and logical partitions
        realnum = 0
        for part in self.partitions:
            if part.no_table:
                part.realnum = 0
            else:
                realnum += 1
                if self.ptable_format == 'msdos' and realnum > 3 and num_real_partitions > 4:
                    part.realnum = realnum + 1
                    continue
                part.realnum = realnum

        # generate parition and filesystem UUIDs
        for part in self.partitions:
            if not part.uuid and part.use_uuid:
                if self.ptable_format in ('gpt', 'gpt-hybrid'):
                    part.uuid = str(uuid.uuid4())
                else: # msdos partition table
                    part.uuid = '%08x-%02d' % (self.identifier, part.realnum)
            if not part.fsuuid:
                if part.fstype == 'vfat' or part.fstype == 'msdos':
                    part.fsuuid = '0x' + str(uuid.uuid4())[:8].upper()
                else:
                    part.fsuuid = str(uuid.uuid4())
            else:
                #make sure the fsuuid for vfat/msdos align with format 0xYYYYYYYY
                if part.fstype == 'vfat' or part.fstype == 'msdos':
                    if part.fsuuid.upper().startswith("0X"):
                        part.fsuuid = '0x' + part.fsuuid.upper()[2:].rjust(8,"0")
                    else:
                        part.fsuuid = '0x' + part.fsuuid.upper().rjust(8,"0")

    def prepare(self, imager):
        """Prepare an image. Call prepare method of all image partitions."""
        for part in self.partitions:
            # need to create the filesystems in order to get their
            # sizes before we can add them and do the layout.
            part.prepare(imager, imager.workdir, imager.oe_builddir,
                         imager.rootfs_dir, imager.bootimg_dir,
                         imager.kernel_dir, imager.native_sysroot,
                         imager.updated_fstab_path)

            # Converting kB to sectors for parted
            part.size_sec = part.disk_size * 1024 // self.sector_size

    def layout_partitions(self):
        """ Layout the partitions, meaning calculate the position of every
        partition on the disk. The 'ptable_format' parameter defines the
        partition table format and may be "msdos". """

        logger.debug("Assigning %s partitions to disks", self.ptable_format)

        # The number of primary and logical partitions. Extended partition and
        # partitions not listed in the table are not included.
        num_real_partitions = len([p for p in self.partitions if not p.no_table])

        # Go through partitions in the order they are added in .ks file
        for num in range(len(self.partitions)):
            part = self.partitions[num]

            if self.ptable_format == 'msdos' and part.part_name:
                raise WicError("setting custom partition name is not " \
                               "implemented for msdos partitions")

            if self.ptable_format == 'msdos' and part.part_type:
                # The --part-type can also be implemented for MBR partitions,
                # in which case it would map to the 1-byte "partition type"
                # filed at offset 3 of the partition entry.
                raise WicError("setting custom partition type is not " \
                               "implemented for msdos partitions")

            if part.mbr and self.ptable_format != 'gpt-hybrid':
                raise WicError("Partition may only be included in MBR with " \
                               "a gpt-hybrid partition table")

            # Get the disk where the partition is located
            self.numpart += 1
            if not part.no_table:
                self.realpart += 1

            if self.numpart == 1:
                if self.ptable_format == "msdos":
                    overhead = MBR_OVERHEAD
                elif self.ptable_format in ("gpt", "gpt-hybrid"):
                    overhead = GPT_OVERHEAD

                # Skip one sector required for the partitioning scheme overhead
                self.offset += overhead

            if self.ptable_format == "msdos":
                if self.primary_part_num > 3 or \
                   (self.extendedpart == 0 and self.primary_part_num >= 3 and num_real_partitions > 4):
                    part.type = 'logical'
                # Reserve a sector for EBR for every logical partition
                # before alignment is performed.
                if part.type == 'logical':
                    self.offset += 2

            align_sectors = 0
            if part.align:
                # If not first partition and we do have alignment set we need
                # to align the partition.
                # FIXME: This leaves a empty spaces to the disk. To fill the
                # gaps we could enlargea the previous partition?

                # Calc how much the alignment is off.
                align_sectors = self.offset % (part.align * 1024 // self.sector_size)

                if align_sectors:
                    # If partition is not aligned as required, we need
                    # to move forward to the next alignment point
                    align_sectors = (part.align * 1024 // self.sector_size) - align_sectors

                    logger.debug("Realignment for %s%s with %s sectors, original"
                                 " offset %s, target alignment is %sK.",
                                 part.disk, self.numpart, align_sectors,
                                 self.offset, part.align)

                    # increase the offset so we actually start the partition on right alignment
                    self.offset += align_sectors

            if part.offset is not None:
                offset = part.offset // self.sector_size

                if offset * self.sector_size != part.offset:
                    raise WicError("Could not place %s%s at offset %d with sector size %d" % (part.disk, self.numpart, part.offset, self.sector_size))

                delta = offset - self.offset
                if delta < 0:
                    raise WicError("Could not place %s%s at offset %d: next free sector is %d (delta: %d)" % (part.disk, self.numpart, part.offset, self.offset, delta))

                logger.debug("Skipping %d sectors to place %s%s at offset %dK",
                             delta, part.disk, self.numpart, part.offset)

                self.offset = offset

            part.start = self.offset
            self.offset += part.size_sec

            if not part.no_table:
                part.num = self.realpart
            else:
                part.num = 0

            if self.ptable_format == "msdos" and not part.no_table:
                if part.type == 'logical':
                    self.logical_part_cnt += 1
                    part.num = self.logical_part_cnt + 4
                    if self.extendedpart == 0:
                        # Create extended partition as a primary partition
                        self.primary_part_num += 1
                        self.extendedpart = part.num
                    else:
                        self.extended_size_sec += align_sectors
                    self.extended_size_sec += part.size_sec + 2
                else:
                    self.primary_part_num += 1
                    part.num = self.primary_part_num

            logger.debug("Assigned %s to %s%d, sectors range %d-%d size %d "
                         "sectors (%d bytes).", part.mountpoint, part.disk,
                         part.num, part.start, self.offset - 1, part.size_sec,
                         part.size_sec * self.sector_size)

        # Once all the partitions have been layed out, we can calculate the
        # minumim disk size
        self.min_size = self.offset
        if self.ptable_format in ("gpt", "gpt-hybrid"):
            self.min_size += GPT_OVERHEAD

        self.min_size *= self.sector_size
        self.min_size += self.extra_space

    def _create_partition(self, device, parttype, fstype, start, size):
        """ Create a partition on an image described by the 'device' object. """

        # Start is included to the size so we need to substract one from the end.
        end = start + size - 1
        logger.debug("Added '%s' partition, sectors %d-%d, size %d sectors",
                     parttype, start, end, size)

        cmd = "export PARTED_SECTOR_SIZE=%d; parted -s %s unit s mkpart %s" % \
                     (self.sector_size, device, parttype)
        if fstype:
            cmd += " %s" % fstype
        cmd += " %d %d" % (start, end)

        return exec_native_cmd(cmd, self.native_sysroot)

    def _write_identifier(self, device, identifier):
        logger.debug("Set disk identifier %x", identifier)
        with open(device, 'r+b') as img:
            img.seek(0x1B8)
            img.write(identifier.to_bytes(4, 'little'))

    def _make_disk(self, device, ptable_format, min_size):
        logger.debug("Creating sparse file %s", device)
        with open(device, 'w') as sparse:
            os.ftruncate(sparse.fileno(), min_size)

        logger.debug("Initializing partition table for %s", device)
        exec_native_cmd("export PARTED_SECTOR_SIZE=%d; parted -s %s mklabel %s" %
                        (self.sector_size, device, ptable_format), self.native_sysroot)

    def _write_disk_guid(self):
        if self.ptable_format in ('gpt', 'gpt-hybrid'):
            if os.getenv('SOURCE_DATE_EPOCH'):
                self.disk_guid = uuid.UUID(int=int(os.getenv('SOURCE_DATE_EPOCH')))
            else:
                self.disk_guid = uuid.uuid4()

            logger.debug("Set disk guid %s", self.disk_guid)
            sfdisk_cmd = "sfdisk --sector-size %s --disk-id %s %s" % \
                        (self.sector_size, self.path, self.disk_guid)
            exec_native_cmd(sfdisk_cmd, self.native_sysroot)

    def create(self):
        self._make_disk(self.path,
                        "gpt" if self.ptable_format == "gpt-hybrid" else self.ptable_format,
                        self.min_size)

        self._write_identifier(self.path, self.identifier)
        self._write_disk_guid()

        if self.ptable_format == "gpt-hybrid":
            mbr_path = self.path + ".mbr"
            self._make_disk(mbr_path, "msdos", self.min_size)
            self._write_identifier(mbr_path, self.identifier)

        logger.debug("Creating partitions")

        hybrid_mbr_part_num = 0

        for part in self.partitions:
            if part.num == 0:
                continue

            if self.ptable_format == "msdos" and part.num == self.extendedpart:
                # Create an extended partition (note: extended
                # partition is described in MBR and contains all
                # logical partitions). The logical partitions save a
                # sector for an EBR just before the start of a
                # partition. The extended partition must start one
                # sector before the start of the first logical
                # partition. This way the first EBR is inside of the
                # extended partition. Since the extended partitions
                # starts a sector before the first logical partition,
                # add a sector at the back, so that there is enough
                # room for all logical partitions.
                self._create_partition(self.path, "extended",
                                       None, part.start - 2,
                                       self.extended_size_sec)

            if part.fstype == "swap":
                parted_fs_type = "linux-swap"
            elif part.fstype == "vfat":
                parted_fs_type = "fat32"
            elif part.fstype == "msdos":
                parted_fs_type = "fat16"
                if not part.system_id:
                    part.system_id = '0x6' # FAT16
            else:
                # Type for ext2/ext3/ext4/btrfs
                parted_fs_type = "ext2"

            # Boot ROM of OMAP boards require vfat boot partition to have an
            # even number of sectors.
            if part.mountpoint == "/boot" and part.fstype in ["vfat", "msdos"] \
               and part.size_sec % 2:
                logger.debug("Subtracting one sector from '%s' partition to "
                             "get even number of sectors for the partition",
                             part.mountpoint)
                part.size_sec -= 1

            self._create_partition(self.path, part.type,
                                   parted_fs_type, part.start, part.size_sec)

            if self.ptable_format == "gpt-hybrid" and part.mbr:
                hybrid_mbr_part_num += 1
                if hybrid_mbr_part_num > 4:
                    raise WicError("Extended MBR partitions are not supported in hybrid MBR")
                self._create_partition(mbr_path, "primary",
                                       parted_fs_type, part.start, part.size_sec)

            if self.ptable_format in ("gpt", "gpt-hybrid") and (part.part_name or part.label):
                partition_label = part.part_name if part.part_name else part.label
                logger.debug("partition %d: set name to %s",
                             part.num, partition_label)
                exec_native_cmd("sfdisk --sector-size %s --part-label %s %d %s" % \
                                         (self.sector_size, self.path, part.num,
                                          partition_label), self.native_sysroot)
            if part.part_type:
                logger.debug("partition %d: set type UID to %s",
                             part.num, part.part_type)
                exec_native_cmd("sfdisk --sector-size %s --part-type %s %d %s" % \
                                         (self.sector_size, self.path, part.num,
                                          part.part_type), self.native_sysroot)

            if part.uuid and self.ptable_format in ("gpt", "gpt-hybrid"):
                logger.debug("partition %d: set UUID to %s",
                             part.num, part.uuid)
                exec_native_cmd("sfdisk --sector-size %s --part-uuid %s %d %s" % \
                                (self.sector_size, self.path, part.num, part.uuid),
                                self.native_sysroot)

            if part.active:
                flag_name = "legacy_boot" if self.ptable_format in ('gpt', 'gpt-hybrid') else "boot"
                logger.debug("Set '%s' flag for partition '%s' on disk '%s'",
                             flag_name, part.num, self.path)
                exec_native_cmd("export PARTED_SECTOR_SIZE=%d; parted -s %s set %d %s on" % \
                                (self.sector_size, self.path, part.num, flag_name),
                                self.native_sysroot)
                if self.ptable_format == 'gpt-hybrid' and part.mbr:
                    exec_native_cmd("export PARTED_SECTOR_SIZE=%d; parted -s %s set %d %s on" % \
                                    (self.sector_size, mbr_path, hybrid_mbr_part_num, "boot"),
                                    self.native_sysroot)
            if part.system_id:
                exec_native_cmd("sfdisk --sector-size %s --part-type %s %s %s" % \
                                (self.sector_size, self.path, part.num, part.system_id),
                                self.native_sysroot)

            if part.hidden and self.ptable_format == "gpt":
                logger.debug("Set hidden attribute for partition '%s' on disk '%s'",
                             part.num, self.path)
                exec_native_cmd("sfdisk --sector-size %s --part-attrs %s %s RequiredPartition" % \
                                (self.sector_size, self.path, part.num),
                                self.native_sysroot)

        if self.ptable_format == "gpt-hybrid":
            # Write a protective GPT partition
            hybrid_mbr_part_num += 1
            if hybrid_mbr_part_num > 4:
                raise WicError("Extended MBR partitions are not supported in hybrid MBR")

            # parted cannot directly create a protective GPT partition, so
            # create with an arbitrary type, then change it to the correct type
            # with sfdisk
            self._create_partition(mbr_path, "primary", "fat32", 1, GPT_OVERHEAD)
            exec_native_cmd("sfdisk --sector-size %s --part-type %s %d 0xee" % \
                            (self.sector_size, mbr_path, hybrid_mbr_part_num),
                            self.native_sysroot)

            # Copy hybrid MBR
            with open(mbr_path, "rb") as mbr_file:
                with open(self.path, "r+b") as image_file:
                    mbr = mbr_file.read(512)
                    image_file.write(mbr)

    def cleanup(self):
        pass

    def assemble(self):
        logger.debug("Installing partitions")

        for part in self.partitions:
            source = part.source_file
            if source:
                # install source_file contents into a partition
                sparse_copy(source, self.path, seek=part.start * self.sector_size)

                logger.debug("Installed %s in partition %d, sectors %d-%d, "
                             "size %d sectors", source, part.num, part.start,
                             part.start + part.size_sec - 1, part.size_sec)

                partimage = self.path + '.p%d' % part.num
                os.rename(source, partimage)
                self.partimages.append(partimage)
