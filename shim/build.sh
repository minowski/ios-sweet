#!/bin/bash
# Build the shim and wrap it in a boot.img v2 that mirrors the stock PixelOS header.
set -euo pipefail
if [ "${1:-}" = --sunfish ]; then
	if [ "$#" -ne 4 ]; then
		echo "usage: $0 --sunfish PAYLOAD STOCK_BOOT_IMAGE OUTPUT_DIR" >&2
		exit 2
	fi
	payload=$(realpath "$2")
	stock=$(realpath "$3")
	output=$(realpath -m "$4")
	target_flags=-DSUNFISH
else
	payload=${1:-}
	output=out
	target_flags=
fi
cd "$(dirname "$0")"
CC=aarch64-linux-gnu-gcc
OBJCOPY=aarch64-linux-gnu-objcopy
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
mkdir -p "$output"
for f in start.S shim.c console.c mmu.c fdt.c loader.c ufs.c; do
	$CC $CFLAGS $target_flags -c "$f" -o "$output/${f%.*}.o"
done
# The image runs wherever ABL puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$(aarch64-linux-gnu-readelf -r "$output/shim.o" "$output/console.o" "$output/mmu.o" "$output/fdt.o" "$output/loader.o" "$output/ufs.o" | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	"$output/start.o" "$output/shim.o" "$output/console.o" "$output/mmu.o" "$output/fdt.o" "$output/loader.o" "$output/ufs.o" -o "$output/shim.elf"
$OBJCOPY -O binary "$output/shim.elf" "$output/Image"
# ABL copies the file; pad to image_size so .bss/stacks exist as zeroed bytes.
size=$(aarch64-linux-gnu-nm "$output/shim.elf" | awk '$3=="_end"{print strtonum("0x"$1)}')
truncate -s "$size" "$output/Image"
# Ramdisk: an xnu payload (tools/mkpayload.py) if given as $1, else an empty
# newc cpio (ABL dislikes a zero-size ramdisk on some builds) -> diagnostics.
if [ -n "$payload" ]; then
	cp "$payload" "$output/ramdisk.bin"
else
	(cd out && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
fi
if [ -n "$target_flags" ]; then
	python3 ../tools/mksunfishboot.py "$stock" "$output/Image" "$output/ramdisk.bin" "$output/sunfish-boot.img"
	exit 0
fi
mkbootimg --header_version 2 --kernel "$output/Image" --ramdisk out/ramdisk.bin \
	--dtb ../dtb/boot_unpacked/dtb --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
	--tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
	--os_version 17.0.0 --os_patch_level 2035-06 \
	--cmdline "console=null" -o out/shim-boot.img
# Host render of the console layout.
gcc -O1 -Wall -o out/host_test console.c host_test.c && ./out/host_test
ls -l "$output/Image" out/shim-boot.img
