WINSDK_NO_SYMLINK ?= "0"

archive_sdk:prepend:sdkmingw32 () {
	if [ "${WINSDK_NO_SYMLINK}" = "1" ]; then
		for parse_type in "file" "directory"; do
			find "${SDK_OUTPUT}/${SDKPATH}" -type l -print | while read -r symlink; do
				target=$(readlink -f "$symlink" || echo "NOTVALID")
				if [ "$target" = "NOTVALID" ]; then
					bbnote "Deleting invalid symlink: $symlink"
					rm -f $symlink
					continue
				fi
				if [ ! -e "$target" ]; then
					bbnote "Deleting dead symlink: $symlink"
					rm -f $symlink
				elif [ -d "$target" ]; then
					if [ "$parse_type" = "directory" ]; then
						rm "$symlink" && cp -r "$target" "$symlink"
					fi
				else
					if [ "$parse_type" = "file" ]; then
						rm "$symlink" && cp "$target" "$symlink"
					fi
				fi
			done
		done
		# With the above symlink handling, we've copied correct contents.
		# But we still face possible newly generated symlinks in the above process.
		# For example, in case of multilib, there will be links like below:
		#   x86-64-v3-poky-linux/lib64/x86_64-poky-linux/15.2.0/32/64/32
		# This xxx/32/64/32 is a useless dead link and we can just remove it.
		# Anyway, all these newly generated symlinks can be deleted!
		find "${SDK_OUTPUT}/${SDKPATH}" -type l -delete
	fi
}
