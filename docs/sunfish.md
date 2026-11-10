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

