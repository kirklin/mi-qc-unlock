# Xiaomi QC bootloader unlock — macOS

Bootloader unlock and relock for Xiaomi and Redmi devices with Qualcomm Snapdragon SoCs, driven from macOS.

## Works on the latest security patches

The `fastboot oem set-gpu-preemption-value 0 androidboot.selinux=permissive` command that older approaches used was removed after the March 2026 patch. This tool does not use that command. Instead an in-kernel preload `.so` running on the live system escalates to uid=0 and switches SELinux to permissive; from there the flow writes an old ABL and the unlock payload directly to the block device. That path continues to work on the latest security patches — verified end-to-end on Xiaomi 17 Ultra with security patch 2026-08-01, kernel 6.12.69, HyperOS 4.

## Supported chipsets and devices

| Chipset | SoC | Devices |
|---------|-----|---------|
| 8E5 | Snapdragon 8 Elite 2 | Xiaomi 17 / 17 Pro / 17 Pro Max / 17 Ultra, Redmi K90 Pro Max |
| 8E | Snapdragon 8 Elite | Xiaomi 15 / 15 Pro / 15 Ultra, Redmi K80 Pro / K90 / K90 Ultra, Xiaomi MIX Flip 2, Xiaomi Pad 8 Pro |
| 8SGen4 | Snapdragon 8s Gen 4 | Redmi Turbo 4 Pro, Xiaomi Civi 5 Pro, Xiaomi Pad 8 |
| 8Gen3 | Snapdragon 8 Gen 3 | Xiaomi 14 / 14 Pro / 14 Ultra, Redmi K70 Pro / K80, Xiaomi MIX Flip, Xiaomi MIX Fold 4 |
| 8SGen3 | Snapdragon 8s Gen 3 | Redmi Turbo 3, Xiaomi Civi 4 Pro, Xiaomi Pad 7 / Pad 7 Pro |
| 8Gen2 | Snapdragon 8 Gen 2 | Xiaomi 13 / 13 Pro / 13 Ultra, Redmi K60 Pro / K70, Xiaomi Pad 6S Pro, Xiaomi MIX Fold 3 (**you must supply your own root + SELinux permissive**) |

## Prerequisites

```bash
brew install android-platform-tools
```

## Usage

```bash
./unlock_mac.sh
```

The script prompts for unlock or relock, then:
- Detects device model, kernel, SoC via ADB
- Identifies the chipset family
- Selects the correct exploit, ABL, and (for non-8E5) modified GPT plus unlock boot image
- Runs the kernel exploit for root and SELinux permissive
- Backs up the current ABL to the tool directory
- Applies the unlock (see flow below)
- Restores original partition tables and ABL
- Factory resets and reboots

## Unlock flow

### 8E5 (Snapdragon 8 Elite 2)

1. Push and execute preload `.so` (kernel exploit → root + SELinux permissive)
2. Backup `abl_a` to local file
3. Write old ABL to `abl_a` and `abl_b`
4. Write `gbl_efi_unlock.efi` to `efisp`
5. Reboot to fastboot
6. GBL EFI runs at next boot, unlocks RPMB
7. Verify `unlocked: yes` via `fastboot getvar`
8. Overwrite `efisp` with the all-zero blank image
9. Restore original ABL from backup
10. Erase `userdata` and `metadata`, reboot

### 8E / 8SGen4 / 8Gen3 / 8SGen3 / 8Gen2

1. Push and execute exploit binary (preload `.so` for 8E/8SGen4, standalone ELF for 8Gen3/8SGen3, none for 8Gen2)
2. Backup `abl_a` to local file
3. Write factory ABL to `abl_a` and `abl_b`
4. Write modified `gpt_both4` (renames `vbmeta_a/b`, `pvmfw_a/b`, `qupfw_a/b` to disable verified boot)
5. Reboot to fastboot
6. Flash unlock boot image via `fastboot flash boot`
7. Reboot — unlock boot image runs without vbmeta verification and modifies RPMB
8. Verify `unlocked: yes`
9. Flash official `gpt_both0` through `gpt_both5` to restore partition tables
10. Restore original ABL from backup
11. Erase `userdata` and `metadata`, reboot

## Directory layout

```
xiaomi-sd8eg5-bootloader-unlock-relock/
├── unlock_mac.sh
├── payloads/
│   ├── 8e5/
│   ├── 8e/
│   ├── 8sgen4/
│   ├── 8gen3/
│   ├── 8sgen3/
│   ├── 8gen2/
│   └── misc/
└── abl_backup_*.img  (created by unlock_mac.sh)
```

## Notes

- 8Gen2 has no bundled exploit; obtain root and set SELinux to permissive on your own before running the tool.
- 8E5 tested end-to-end on Xiaomi 17 Ultra (Sept 2026, security patch 2026-08-01, kernel 6.12.69, HyperOS 4).
- Other chipsets: flow is implemented, not yet verified on real hardware.
- If the unlock leaves the device unable to boot, restore the original ABL from the backup file and erase `userdata` and `metadata` via fastboot.
