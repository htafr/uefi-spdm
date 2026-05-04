# SPDM in UEFI 

This is a M.Sc. project that uses EDK2 and QEMU to exchange SPDM messages
between PCIe and USB devices and the UEFI firmware.

This repo implements work from other repos[^1] [^2] [^3] with personal modifications.

### QEMU

QEMU compiles the LibSPDM in-tree (see `./configure --help`), and there are two files that 
make the LibSPDM API available to use: `backend/spdm.c` and `include/system/spdm.h`.

### EDK2

Based on the work of the DeviceSecurity branch in edk2-staging repo, I adapted the code 
to use the DXE stage in OVMF. The modifications consist in changing the code to use current 
SPDM functions available in EDK2 and to use future PCI DOE support yet to be approved.

You can check the modifications mainly in DeviceSecurityPkg directory.

# Clone

```bash
git clone https://github.com/htafr/uefi-spdm.git
cd uefi-spdm 
```

# Build

> My environment is based on Ubuntu 25.04 aarch64

## Ubuntu

Required packages.

```bash
# EDK2
sudo apt-get install build-essential uuid-dev iasl git nasm python-is-python3

# QEMU
sudo apt-get install libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build nettle-dev libgtk-3-dev

# TPM 
sudo apt-get install swtpm
```

## Build Instructions

```bash
make all
```

# Run 

```bash
# Run the emulation with GUI
make run

# Run the emulation without GUI
make run-cli

# Run the emulation to count CPU measures with perf KVM
make perf
```

# Certificates

The rsa2048 was generated using libspdm[^4] certificate generator script.

[^1]: [DeviceSecurity Branch at edk2-staging](https://github.com/tianocore/edk2-staging/blob/DeviceSecurity/DeviceSecurityTestPkg/readme.md)
[^2]: [PCI DOE initial support for EDK2 PR#5715](https://github.com/tianocore/edk2/pull/5715)
[^3]: [NVMe and PCI DOE implementation in QEMU](https://github.com/twilfredo/qemu-spdm-emulation-guide)
[^4]: [auto\_gen\_cert.sh](https://github.com/DMTF/libspdm/blob/a6ce1c966657f96bf3b4a6af08037abd9d00b306/unit_test/sample_key/auto_gen_cert.sh)

