WINSDK_NO_SYMLINK ?= "0"

archive_sdk:prepend:sdkmingw32 () {
	if [ "${WINSDK_NO_SYMLINK}" = "1" ]; then
		for parse_type in "file" "directory"; do
			find "${SDK_OUTPUT}/${SDKPATH}" -type l -print0 | while IFS= read -r -d '' symlink; do
				target=$(readlink -f "$symlink" || echo "NOTVALID")
				if [ "$target" = "NOTVALID" ]; then
					continue
				fi
				if [ ! -e "$target" ]; then
					continue
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
	fi
}
