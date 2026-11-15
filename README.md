# hio-es3000-linux6 — Huawei ES3000 (`hio`) PCIe SSD driver, port to Linux 6.8

**Status: experimental / work in progress. Do not use on a card that holds data you care about.**

Huawei's out-of-tree block driver `hio` (Tecal ES3000 PCIe SSD) was last maintained for Linux 4.x.
This repo is an attempt to make it build and run on a modern kernel (target: Ubuntu 22.04 HWE, `6.8.0-*-generic`).

- Base: the `ubuntu/hio` tree from Canonical's kernel git (driver version `2.1.0.23`, GPL-2.0, Copyright Huawei Technologies).
  Its Linux-4.x era block-layer / timer / DMA / procfs APIs were rewritten for 6.8.
- Hardware tested: ES3000 v1, 800 GB, PCI id `19e5:0007` (listed as `/* v1 */` in the driver's PCI table).
- `upstream/` keeps the unmodified base; `linux-6.8-port.patch` is the full diff (`diff -u upstream/hio.c hio.c`).

## What works / does not (as of first commit)
| Step | Result |
|---|---|
| Builds against `6.8.0-138-generic` (gcc-12) | yes |
| `insmod hio.ko`, card enumerates as `/dev/hioa` (~803 GB) | yes |
| Reading blocks (`partition table`, `dd`) | **no** — earlier builds hit `cmd timeout` / `Buffer I/O error` |
| Latest changes (IOMMU `dma_map_sg`, `bio_split_to_limits`) | not yet verified |

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

## License
GPL-2.0 (see `COPYING`), same as the upstream driver. No warranty. Not affiliated with Huawei or Canonical.
