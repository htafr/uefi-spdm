.SHELL := /usr/bin/bash
.ONESHELL:

REPO ?= $(shell pwd)

ifeq ($(shell uname -m), arm64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-suse-linux-
LDFLAGS ?= "-L/lib/aarch64-linux-gnu -L/usr/lib"
else ifeq ($(shell uname -m), aarch64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-suse-linux-
LDFLAGS ?= "-L/lib/aarch64-linux-gnu -L/usr/lib"
else ifeq ($(shell uname -m), x86_64)
TOOLCHAIN ?= GCC
GCC5_X64_PREFIX ?= gcc
LDFLAGS ?= ""
endif

MKDIR = @mkdir -p
PYTHON = @$(shell which python3)
QEMUX64 = ${REPO}/qemu/build/qemu-system-x86_64
# SWTPM = ${REPO}/swtpm/build/bin/swtpm
SWTPM = swtpm

PKG_CONFIG_PATH ?= "/usr/lib/pkgconfig:${REPO}/libtpms/build/lib64/pkgconfig"
CFLAGS ?= "-I${REPO}/libtpms/include"

CODEX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
VARSX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS_INTEGRITY.fd
# VARSX64 = ${REPO}/ovmf_vars_spdm.fd
# VARSX64 = ${REPO}/vars.fd

ZEROIMG = ${REPO}/images/zero.img
USBIMG = ${REPO}/images/usb.img

# -global driver=cfi.pflash01,property=secure,value=on
QFLAGSX64 = -M q35,smm=on -smp 4 -m 1G -nodefaults -bios none \
						-chardev stdio,mux=on,id=char0 \
						-serial chardev:char0 \
						-monitor vc \
						-device pcie-root-port,id=pci20,bus=pcie.0,chassis=1,addr=2.0,multifunction=on,pref64-reserve=32M \
						-device pcie-root-port,id=pci21,bus=pcie.0,chassis=2,addr=2.1 \
						-device pcie-root-port,id=pci22,bus=pcie.0,chassis=3,addr=2.2 \
						-device pcie-root-port,id=pci23,bus=pcie.0,chassis=4,addr=2.3 \
						-device pcie-root-port,id=pci30,bus=pcie.0,chassis=31,addr=3.0,multifunction=on,pref64-reserve=32M \
						-device pcie-root-port,id=pci31,bus=pcie.0,chassis=32,addr=3.1 \
						-device virtio-serial-pci,bus=pci21 \
						-device virtconsole,chardev=char0,id=console0 \
						-device isa-debugcon,iobase=0x402,chardev=char0 \
						-object rng-random,filename=/dev/urandom,id=rng0 \
						-device virtio-rng-pci,bus=pci22,rng=rng0 \
						-device virtio-gpu-pci,bus=pci23 \
						-device e1000e,netdev=net0,bus=pci30 -netdev user,id=net0,hostfwd=tcp::5555-:22 \
						-usb \
						-device qemu-xhci,id=xhci \
						-device usb-storage,bus=xhci.0,drive=stick,removable=on \
						-drive if=none,id=stick,format=raw,file=${USBIMG} \
						-global driver=cfi.pflash01,property=secure,value=on \
						-drive if=pflash,unit=0,format=raw,file=${CODEX64},readonly=on \
						-drive if=pflash,unit=1,format=raw,file=${VARSX64} \
						-drive file=${ZEROIMG},format=raw,if=none,id=hd0 \
						-device nvme,bus=pci20,serial=deadbeef,drive=hd0 \
						-chardev socket,id=chrtpm,path=/tmp/tpm/swtpm-sock \
						-tpmdev emulator,id=tpm0,chardev=chrtpm \
						-device tpm-tis,tpmdev=tpm0

TPMEMU = $(SWTPM) socket --tpm2 -d \
				 --tpmstate dir=/tmp/tpm,mode=0600,lock \
				 --ctrl type=unixio,path=/tmp/tpm/swtpm-sock,mode=0600,terminate \
				 --flags disable-auto-shutdown \
				 --log level=20,file=${REPO}/logs/tpm.log

.PHONY: help
help:
	@echo "make [option]"
	@echo 
	@echo "options:"
	@echo "    help          print this message"
	@echo "    all           initialize repo, build qemu and edk2"
	@echo "    init          initialize git submodules, compile BaseTools,"
	@echo "                  and create disk images"
	@echo "    qemu          configure and build qemu"
	@echo "    qemu-config   configure qemu"
	@echo "    edk2          build OVMF firmware"
	@echo "    run           run emulation"
	@echo "    run-cli       run emulation without GUI"
	@echo "    dbg           run emulation to attach to a gdb instance"
	@echo "    integrity     run emulation with wrong supplied firmware hash"
	@echo "    tpm           run TPM emulation"
	@echo "    dirs          create logs/, qemu/build/, images/, keys/, /tmp/tpm,"
	@echo "                  libtpms/build, and swtpm/build"
	@echo "    clean         clean build"
	@echo "    clean-edk2    clean EDKII build"
	@echo "    clean-qemu    clean QEMU build"
	@echo "    clean-libtpms clean libtpms build"
	@echo "    clean-swtpm   clean swtpm build"
	@echo 

.PHONY: all
all: init qemu edk2 swtpm

.PHONY: init
init: dirs
	$(MAKE) -C ${REPO}/edk2/BaseTools
	@dd if=/dev/zero of=${ZEROIMG} bs=32M count=1
	@dd if=/dev/zero of=${USBIMG} bs=32M count=1

.PHONY: qemu
qemu: qemu-config
	$(MAKE) -C ${REPO}/qemu/build

.PHONY: edk2
edk2:
	@export WORKSPACE=${REPO}/edk2
	@export GCC5_BIN=${GCC5_X64_PREFIX}
	@source ${REPO}/edk2/edksetup.sh
	@cd ${REPO}/edk2
	@build -p OvmfPkg/OvmfPkgX64.dsc -t GCC5 -a X64 -b DEBUG -Y COMPILE_INFO -y ${REPO}/logs/OvmfPkgX64.log -DSECURE_BOOT_ENABLE=TRUE -DLIBSPDM_ENABLE=TRUE
	# $(PYTHON) ${REPO}/scripts/generate_vars_yaml -w ${REPO}
	# source ${REPO}/../ovmfvartool/.venv/bin/activate
	# ovmfvartool compile ${REPO}/vars.yaml ${REPO}/ovmf_vars_spdm.fd

.PHONY: run
run: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2
	$(QEMUX64) $(QFLAGSX64)

.PHONY: run-cli
run-cli: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2
	$(QEMUX64) $(QFLAGSX64) -nographic

.PHONY: dbg
dbg: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2
	$(QEMUX64) $(QFLAGSX64) -nographic -s -S

.PHONY: integrity
integrity: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2 -m
	$(QEMUX64) $(QFLAGSX64)

.PHONY: tpm
tpm: dirs
	$(TPMEMU)

qemu-config: dirs
	@cd ${REPO}/qemu/build
	../configure \
		--target-list=x86_64-softmmu \
		--disable-werror \
		--enable-libspdm \
		--libspdm-crypto=mbedtls \
		--libspdm-toolchain=${TOOLCHAIN} \
		--enable-gcov \
		--enable-debug \
		--enable-nettle \
		--enable-gtk \
		--enable-system \
		--enable-sdl \
		--enable-slirp

# -nodes: No DES encryption
.PHONY: keys
keys: dirs
	openssl req -nodes -new -x509 -newkey rsa:2048 -keyout ${REPO}/keys/PK.key -out ${REPO}/keys/PK.crt -days 365 -subj "/CN=UEFI SPDM" -sha256
	openssl x509 -in ${REPO}/keys/PK.crt -out ${REPO}/keys/PK.cer -outform DER
	openssl req -nodes -new -x509 -newkey rsa:2048 -keyout ${REPO}/keys/KEK.key -out ${REPO}/keys/KEK.crt -days 365 -subj "/CN=UEFI SPDM" -sha256
	openssl x509 -in ${REPO}/keys/KEK.crt -out ${REPO}/keys/KEK.cer -outform DER

.PHONY: dirs
dirs:
	$(MKDIR) ${REPO}/logs/
	$(MKDIR) ${REPO}/qemu/build
	$(MKDIR) ${REPO}/images
	$(MKDIR) ${REPO}/keys
	$(MKDIR) ${REPO}/libtpms/build
	$(MKDIR) ${REPO}/swtpm/build
	$(MKDIR) /tmp/tpm

.PHONY: clean
clean: clean-edk2 clean-qemu clean-swtpm clean-libtpms

clean-qemu:
	rm -rf ${REPO}/qemu/build

clean-edk2:
	rm -rf ${REPO}/edk2/Build

clean-libtpms:
	rm -rf ${REPO}/libtpms/build
	$(MAKE) -C ${REPO}/libtpms maintainer-clean

clean-swtpm:
	rm -rf ${REPO}/swtpm/build
	$(MAKE) -C ${REPO}/swtpm maintainer-clean

