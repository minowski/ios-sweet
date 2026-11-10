## Sunfish port plan

This work targets the Pixel 4a separately from Redmi Note 10 Pro. KNOWN
means documented or established in source, with hardware handoff still
unverified. UNKNOWN values must be supplied or measured before enabling
the corresponding path.

| Area | Sweet | Sunfish and source |
| --- | --- | --- |
| Machine / ADT | SWEET, `xiaomi,sweet`, synthetic ECID and firmware strings | KNOWN SUNFISH, `google,sunfish`, own synthetic ECID and firmware strings. Shared non-PAC SM7150 core and D22AP/iPhone10,3 userland ABI. |
| CPU / interrupts | 8 Kryo 470 CPUs, 19.2 MHz, GICD/R 0x17a00000/0x17a60000, Group 1 CNTV 19, PSCI SMC | KNOWN shared SoC layout to reuse. UNKNOWN firmware handoff, boot CPU MPIDR, secondary bring-up and clock metadata. Check Qualcomm sdmmagpie sources and stock DTB; start with one CPU. |
| Android wrapper | v2 with PixelOS offsets, DTB, page size and spoofed version | UNKNOWN stock header fields and DTB selection on current firmware. Read from a user-supplied stock Sunfish boot image; verify ABL accepts the wrapper and passes DTB/initrd at EL1. |
| RAM / shim reset | 0xb0000000 + 0x4d000000 or 0x100000000 + 0xfcc00000, 1 MiB panic reserve; Sweet IMEM/PSHOLD fallback | UNKNOWN safe contiguous bank after bootloader fixups and all reserved/XPU carve-outs. Require explicit base/size from stock DTB and confirmed firmware layout; skip Sweet reset/probe path. |
| Framebuffer | 0x9c000000, 1080×2400, stride 4320, 32-bit a8r8g8b8, video-mode splash | KNOWN 1080×2340 OLED. UNKNOWN active splash base, reserved extent, stride, pixel format, panel mode and refresh kick. Check stock DTB / selected panel and ABL handoff; disable early Sweet writes. |
| Touch | Goodix GT9896, QUP SE7 0xa84000, 0x5d, Sweet TLMM and PM6150L LDO11 vote | KNOWN stock-family DTS shows ST FTS at SE7 I²C 0x49, IRQ TLMM9, reset TLMM8, switch TLMM72. UNKNOWN panel/revision wiring, power and interrupt setup. No Goodix/RPMh accesses until a Sunfish driver exists. |
| Keys | PM6150 PON power and volume-down; PM6150L GPIO2 volume-up via SPMI | KNOWN Sunfish common DTS lists PM6150L GPIO2 active-low volume-up. UNKNOWN verified PON mapping and SPMI channel/PID/SID routing; cross-check PON and stock DTB before enabling. |
| Battery / regulators | Sweet SPMI arbiter, fuel gauge and RPMh command DB/TCS | UNKNOWN actual gauge, register and rail sequence. Inspect Sunfish battery/regulator DTS and Qualcomm PMIC sources; use no live probe. |
| UFS / logging | UFS at 0x01d84000, warm ABL host, GPT userdata root, end-of-partition log | KNOWN UFS/A-B. UNKNOWN ABL link, LUN/GPT, DMA/clock/PHY and safe log region. Verify stock DTB and Qualcomm UFS sources before enabling UFS. Use RAM-disk root for initial boot. |
| Boot arguments / root | `cpus=6`, writable UFS, `sweetfb_*`, `sweettouch`, `sweetkeys`, USB and persistent log | KNOWN initial single-CPU, RAM-disk and board drivers disabled. UNKNOWN safe later USB logging and root storage. No root tweaks planned. |

Sources: [Sunfish DTS family](https://github.com/GrapheneOS-Archive/kernel_msm-coral/tree/13/arch/arm64/boot/dts/google),
[LineageOS Sunfish specs](https://github.com/LineageOS/lineage_wiki/blob/main/_data/devices/sunfish.yml).

### Build and temporary boot

Use Linux with the Sweet shim dependencies (AArch64 GCC/binutils,
GNU awk, AOSP `mkbootimg`) and an approved `SUNFISH` kernel artifact.
Supply the official stock boot image for the installed Sunfish firmware,
a confirmed 32 MiB-aligned RAM base and 16 KiB-aligned RAM size, and a
small HFS+ test root image with a userspace entry point. The RAM size
includes the top 1 MiB reserved by `mkadt.py` for panic data. The shim
checks payload extents and overlaps with the loaded shim and initrd, but
cannot establish that a proposed address is safe against firmware or XPU
reservations.

If you want to run kernel CI, publish the feature branch and dispatch the
workflow on that ref yourself after reviewing the changes.

```sh
git push -u origin sunfish-port
gh workflow run xnu.yml -R minowski/ios-sweet --ref sunfish-port -f machine_config=SUNFISH
# Once the run finishes, use its ID.
gh run download "$RUN_ID" -R minowski/ios-sweet -n xnu-kernel -D "$BUILD_DIR/xnu"
```

Set `BUILD_DIR` to an absolute directory outside the checkout and set
`STOCK_BOOT`, `TEST_ROOT`, `RAM_BASE` and `RAM_SIZE` to the confirmed
inputs described above. Run from the checkout root.

```sh
mkdir -p "$BUILD_DIR"
python3 tools/mkadt.py "$BUILD_DIR/sunfish.adt" --target sunfish \
    --ram-base "$RAM_BASE" --ram-size "$RAM_SIZE"
python3 tools/mkpayload.py "$BUILD_DIR/xnu/kernel.development.sunfish" \
    "$BUILD_DIR/sunfish.adt" "$BUILD_DIR/payload.bin" --ramdisk "$TEST_ROOT" \
    --cmdline 'debug=0xc serial=0 cpus=1 keepsyms=1 -enable_kprintf_spam rd=md0 sweettouch=0 sweetkeys=0 sweetbattery=0 sweetusb=0 sweetlog=0'
bash shim/build.sh --sunfish "$BUILD_DIR/payload.bin" "$STOCK_BOOT" "$BUILD_DIR/shim"
```

The boot wrapper expects stock v2 with an embedded DTB and will reject
other layouts. It reuses the stock page size, load addresses and version.
ABL acceptance, image download limits, DTB/DTBO selection, initrd
placement and EL1 entry remain hardware checks.

On the unlocked Pixel 4a in bootloader mode, verify the product before
sending the image. This is a temporary boot with no partition flashing.

```sh
fastboot getvar product           # expect sunfish
fastboot boot "$BUILD_DIR/shim/sunfish-boot.img" 2>&1 | tee "$BUILD_DIR/fastboot.log"
```

Read the host-side bootloader transcript with
`cat "$BUILD_DIR/fastboot.log"`. `OKAY` confirms the bootloader command,
not XNU entry. The initial profile has no kernel log transport. The Sweet
recovery script expects a ring at the end of `userdata` and is inapplicable.
First establish a verified splash or debug transport. Then check shim
entry, XNU handoff, timer interrupts, RAM-disk root mount, and userspace in
that order. Before enabling OLED output, check the panel actually
selected by the device's DTBO and whether ABL scanout displays successive
buffer writes without a DSI kickoff. The source family contains both
command and video panel definitions.

Leave UFS and writes disabled until the LUN, GPT layout and root strategy
have been verified. The RAM-disk build uses no Sunfish-specific root tweaks.

