#!/usr/bin/env python3
"""Wrap a Sunfish shim using a caller-supplied stock Android v2 boot header."""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile


def stock_layout(path):
    with path.open('rb') as image:
        header = image.read(1660)
        if len(header) != 1660 or header[:8] != b'ANDROID!':
            raise ValueError('expected a stock Android boot image')
        kernel, kaddr, ramdisk, raddr, second, saddr, tags, page, version, osver = (
            struct.unpack_from('<10I', header, 8))
        if version != 2 or page < len(header) or page > 65536 or page & (page - 1):
            raise ValueError('expected Android boot header v2 with a valid page size')
        recovery, _, header_size, dtb_size, dtb_addr = struct.unpack_from('<IQIIQ', header, 1632)
        if second or recovery or header_size != len(header) or not dtb_size:
            raise ValueError('expected stock A/B v2 layout with DTB and no second stage or recovery DTBO')
        image.seek(page + ((kernel + page - 1) // page + (ramdisk + page - 1) // page) * page)
        dtb = image.read(dtb_size)
        if len(dtb) != dtb_size:
            raise ValueError('stock image DTB is truncated')
    args = ['--header_version', '2', '--pagesize', str(page), '--base', '0']
    for key, value in [('kernel_offset', kaddr), ('ramdisk_offset', raddr),
                       ('second_offset', saddr), ('tags_offset', tags), ('dtb_offset', dtb_addr)]:
        args.extend(['--' + key, hex(value)])
    board = header[48:64].split(b'\0', 1)[0].decode('ascii')
    if board:
        args.extend(['--board', board])
    if osver >> 11:
        args.extend(['--os_version', '.'.join(str((osver >> shift) & 127) for shift in (25, 18, 11))])
    if osver & 0x7ff:
        args.extend(['--os_patch_level', f'{2000 + ((osver >> 4) & 127):04d}-{osver & 15:02d}'])
    return args, dtb


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('stock_boot', 'shim', 'payload', 'output'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    try:
        options, dtb = stock_layout(args.stock_boot)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'stock.dtb'
        path.write_bytes(dtb)
        subprocess.run(['mkbootimg', *options, '--kernel', str(args.shim),
                        '--ramdisk', str(args.payload), '--dtb', str(path),
                        '--cmdline', 'console=null', '-o', str(args.output)], check=True)


if __name__ == '__main__':
    main()

