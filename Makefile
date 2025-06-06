.SHELL := /usr/bin/bash
.ONESHELL:

REPO ?= $(shell pwd)

ifeq ($(shell uname -m), arm64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-linux-gnu-
else ifeq ($(shell uname -m), aarch64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-linux-gnu-
else ifeq ($(shell uname -m), x86_64)
TOOLCHAIN ?= GCC
GCC5_X64_PREFIX ?= 
endif

MKDIR = @mkdir -p
PYTHON = @$(shell which python3)
QEMUX64 = ${REPO}/qemu/build/qemu-system-x86_64

CODEX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
VARSX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS_INTEGRITY.fd

ZEROIMG = ${REPO}/images/zero.img
USBIMG = ${REPO}/images/usb.img

QFLAGSX64 = -M q35,smm=on -smp 4 -m 1G -nodefaults -bios none \
						-nographic \
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

TPMEMU = swtpm socket --tpm2 -d \
				 --tpmstate dir=/tmp/tpm,mode=0600,lock \
				 --ctrl type=unixio,path=/tmp/tpm/swtpm-sock,mode=0600,terminate \
				 --flags disable-auto-shutdown \
				 --log level=20,file=${REPO}/logs/tpm.txt \
				 --terminate

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
	@echo "    tpm           run TPM emulation"
	@echo "    dirs          create logs/, qemu/build/, and /tmp/tpm/"
	@echo 

.PHONY: all
all: init qemu edk2

.PHONY: init
init: dirs
	git submodule update --init --recursive
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
	@build -p OvmfPkg/OvmfPkgX64.dsc -t GCC5 -a X64 -b DEBUG -Y COMPILE_INFO -y ${REPO}/logs/OvmfPkgX64.log

.PHONY: run
run: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2
	$(QEMUX64) $(QFLAGSX64)

.PHONY: integrity
integrity: tpm
	$(PYTHON) ${REPO}/scripts/compute_hash -w ${REPO}/edk2 -m
	$(QEMUX64) $(QFLAGSX64)

.PHONY: tpm
tpm:
	$(TPMEMU)

qemu-config:
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

.PHONY: dirs
dirs:
	$(MKDIR) ${REPO}/logs/
	$(MKDIR) ${REPO}/qemu/build
	$(MKDIR) ${REPO}/images
	$(MKDIR) /tmp/tpm

