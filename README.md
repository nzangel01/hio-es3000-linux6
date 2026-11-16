# hio-es3000-linux6 — Huawei ES3000 (`hio`) PCIe SSD driver, port to Linux 6.8

**Status: works on one tested card (8 h soak, 0 data mismatches; needs airflow). Power-loss safety untested. Keep backups.**

Huawei's out-of-tree block driver `hio` (Tecal ES3000 PCIe SSD) was last maintained for Linux 4.x.
This repo is an attempt to make it build and run on a modern kernel (target: Ubuntu 22.04 HWE, `6.8.0-*-generic`).

- Base: the `ubuntu/hio` tree from Canonical's kernel git (driver version `2.1.0.23`, GPL-2.0, Copyright Huawei Technologies).
  Its Linux-4.x era block-layer / timer / DMA / procfs APIs were rewritten for 6.8.
- Hardware tested: ES3000 v1, 800 GB, PCI id `19e5:0007` (listed as `/* v1 */` in the driver's PCI table).
- `upstream/` keeps the unmodified base; `linux-6.8-port.patch` is the full diff (`diff -u upstream/hio.c hio.c`).

## What works / does not (2026-11-15, kernel 6.8.0-138-generic)
| Step | Result |
|---|---|
| Builds against `6.8.0-138-generic` (gcc-12) | yes |
| `insmod hio.ko`, card enumerates as `/dev/hioa` (~803 GB) | yes |
| ext4 format + mount, direct I/O | yes (reported: ~1.5 GB/s read, ~1.3 GB/s write 1M; 4K QD1 ~6k IOPS) |
| IOMMU (Intel DMAR) fix: use coalesced `dma_nsegs` from `pci_map_sg` | included |
| Full reset (`SSD_FULL_RESET_REG` 0x1B0 = 0x5A, protocol V3.1.1+) at load | included; the card may need a PCIe reset / power cycle if left in a bad state by an older build |
| Survives reboot | yes (auto-load, udev rule, fstab mount; random 1 GiB file SHA-1 intact) |
| 8 h soak (`hio_soak.sh`: 154 rounds x 32 GiB write + drop caches + read-back byte compare) | **0 mismatches**, no `hioerr`, no DMAR/IOMMU fault, no I/O error |
| Thermal | needs airflow: without a fan the card reported `Over temperature` after ~3 min of sustained writes and throttled to ~2-6 MB/s; with a weak fan blowing on it, back to normal (~400 MB/s with this test's data generator) and stable for the rest of the run. Data stayed correct even while throttled |
| Write mode speed | with a 1 h fan-cooled run: `wmode=2` (write-through) wrote ~100 MB/s (9 rounds, 0 mismatches); `wmode=0` (write buffer) wrote ~390-430 MB/s (6 rounds x 32 GiB, 0 mismatches). Both limited by the test's data generator at the high end; the card's rated sequential is ~2.2 GB/s read / ~1.2 GB/s write |
| Power-loss behaviour | **not tested**; `get bm operationstatus failed` is logged, so assume no power-loss protection. `options hio wmode=2` (write-through) is the conservative choice (~4x slower writes); `wmode=0` is fine if the data can be recreated (e.g. downloaded AI models) |

Writing to a card through an unverified driver can hang the machine. Test read-only first.

## Build
```sh
sudo apt install build-essential gcc-12 linux-headers-$(uname -r)
make            # produces hio.ko
sudo insmod hio.ko
dmesg | grep -i hio
```
The kernel's own compiler must match (Ubuntu 6.8 HWE kernels are built with gcc-12).

## Alternative that already works
Ubuntu 18.04 / 20.04 kernels (4.15 / 5.4) ship a prebuilt `hio.ko` in `linux-modules-extra`
(`kernel/ubuntu/hio/hio.ko`). The 20.04.6 live-server ISO also contains it.

## Rebuild automatically on kernel updates (DKMS)
Out-of-tree modules are per kernel: after an Ubuntu kernel update `hio.ko` is gone until rebuilt
(seen on the tested box: 6.8.0-138 -> 6.8.0-149). No per-kernel releases are needed, the source builds against whatever kernel headers are installed.
```sh
sudo apt install dkms linux-headers-$(uname -r)
sudo cp -r . /usr/src/hio-2.1.0.23-linux6
sudo dkms add -m hio -v 2.1.0.23-linux6
sudo dkms install -m hio -v 2.1.0.23-linux6
```
Status: `dkms.conf` is untested until the result is added here.

## License
GPL-2.0 (see `COPYING`), same as the upstream driver. No warranty. Not affiliated with Huawei or Canonical.

## Install on Ubuntu 24.04 (what worked on the tested box)
```sh
sudo install -D hio.ko /lib/modules/$(uname -r)/extra/hio.ko && sudo depmod -a
echo hio | sudo tee /etc/modules-load.d/hio.conf
sudo cp 61-huawei-hio.rules /etc/udev/rules.d/     # stock 60-persistent-storage.rules skips hio*, so no /dev/disk/by-uuid link
# /etc/fstab (nofail so a missing card cannot hang boot):
# UUID=<fs-uuid> /mnt/huawei ext4 defaults,nofail,x-systemd.device-timeout=30 0 2
```
Module parameters (e.g. `wmode`) are declared with perm 0, so they do **not** appear in `/sys/module/hio/parameters/`;
check with `modinfo hio` and set via `/etc/modprobe.d/hio.conf` (`options hio wmode=2` = write-through).
`hiowarn: get bm operationstatus failed` means the backup-capacitor status chip did not answer; treat the card as having no power-loss protection.

## Checking the card
`sudo cat /proc/hio/info` prints driver/firmware/PCB versions only (tested card: driver 2.1.0.23, 803 GB, bridge and controller FW 326).
It does not show the write mode or temperature, so `options hio wmode=2` cannot be confirmed from sysfs/procfs;
temperature problems show up in the kernel log (`hiowarn: ... Over temperature` / `Temperature is OK`).
`hiowarn: some fault found in the history info` appears at every load on the tested card and had no visible effect in the 8 h soak.
