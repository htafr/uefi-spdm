# SPDM in UEFI 

This is a working in progress project that uses EDK2 and QEMU to exchange SPDM messages
between PCI devices and the firmware driver.

This repo implements work from other repos[^1] [^2] [^3] with personal modifications.

# Personal modifications

### QEMU
QEMU compiles the LibSPDM in-tree (see `./configure --help`) and there are two files that 
make the LibSPDM API available to use: `backend/spdm.c` and `include/sysemu/spdm.h`. Moreover, 
there are modifications in `hw/nvme/ctrl.c` to use the implementations of `spdm.c`.

Files related to PCI DOE were also modified to exchange the SPDM messages and two new 
files were added, `hw/nvme/auth.c` and `hw/nvme/auth.c`, to configure SPDM context.

### EDK2

Based on the work of the DeviceSecurity branch in edk2-staging repo, I adapted the code 
to use the DXE stage in OVMF. The modifications consist in changing the code to use current 
SPDM functions available in EDK2 and to use future PCI DOE support yet to be approved.

You can check the modifications mainly in DeviceSecurity and DeployCert folder in OvmfPkg.

# Clone

```bash
git clone https://github.com/htafr/uefi-spdm.git
cd uefi-spdm 
git submodule update --init --recursive
```

# Build

> My environment is based on Ubuntu 24.04 LTS aarch64.

Install required packages.

```bash
# EDK2
sudo apt-get install build-essential uuid-dev iasl git nasm python-is-python3

# QEMU
sudo apt-get install libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build nettle-dev

# TPM emulation 
sudo apt-get install swtpm
```


EDK2 needs to build its BaseTools.

```bash
make -C edk2/BaseTools
```

Copy files `target.txt` and `tools_def.txt`. The latter is needed only if the environment is not x86_64.

```bash
cp files/target.txt files/tools_def.txt edk2/Conf
```

Run the Makefile commands.

```bash
make qemu-build
make edk2-build
```

# Run 

The Makefile has three running rules: **x64-run**, **x64-dbg** and **x64-log**.

1. **x64-run**: normal qemu run 
2. **x64-dbg**: attach qemu to gdb
3. **x64-log**: persist qemu output to logs/log-x64.txt

[^1]: [DeviceSecurity Branch at edk2-staging](https://github.com/tianocore/edk2-staging/blob/DeviceSecurity/DeviceSecurityTestPkg/readme.md)
[^2]: [PCI DOE initial support for EDK2 PR#5715 (still not approved in 18/10/2024)](https://github.com/tianocore/edk2/pull/5715)
[^3]: [NVMe and PCI DOE implementation in QEMU](https://github.com/twilfredo/qemu-spdm-emulation-guide)

