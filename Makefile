.ONESHELL:
SHELL := /usr/bin/bash

REPO ?= $(shell pwd)
KEYS = ${REPO}/keys
GRUB = ${REPO}/../grub
LINUX = ${REPO}/../linux

ifeq ($(shell uname -m), arm64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-linux-gnu-
LDFLAGS ?= "-L/lib/aarch64-linux-gnu -L/usr/lib"
else ifeq ($(shell uname -m), aarch64)
TOOLCHAIN ?= AARCH64_GCC
GCC5_X64_PREFIX ?= x86_64-linux-gnu-
LDFLAGS ?= "-L/lib/aarch64-linux-gnu -L/usr/lib"
else ifeq ($(shell uname -m), x86_64)
TOOLCHAIN ?= GCC
GCC5_X64_PREFIX ?=
LDFLAGS ?= ""
endif

MKDIR = mkdir -p
PYTHON = $(shell which python3)
QEMUX64 = ${REPO}/qemu/build/qemu-system-x86_64
SWTPM = swtpm
CC = gcc

PKG_CONFIG_PATH ?= "/usr/lib/pkgconfig:${REPO}/libtpms/build/lib64/pkgconfig"
CFLAGS ?= "-I${REPO}/libtpms/include"
VENV_PATH ?= ${REPO}/.spdm-venv
BUILD ?= DEBUG

CODEX64 = ${REPO}/edk2/Build/OvmfX64/${BUILD}_GCC5/FV/OVMF_CODE.fd
VARSX64 = ${REPO}/ovmf_vars_custom.fd

ZEROIMG = ${REPO}/images/zero.img
DISKIMG = ${REPO}/images/disk.img
KEYSIMG = ${REPO}/images/keys.img
USBIMG = ${REPO}/images/usb.img

						# -d plugin \
						# -plugin /home/htafr/Git/uefi-spdm/qemu/build/tests/tcg/plugins/libinsn.so \
						# -D /home/htafr/Git/uefi-spdm/logs/instructions.log
QFLAGSX64 = -M q35,smm=on -smp 4 -m 1G -nodefaults -bios none \
						-chardev stdio,mux=on,id=char0 \
						-serial chardev:char0 \
						-mon chardev=char0,mode=readline \
						-device pcie-root-port,id=rp10,bus=pcie.0,addr=1.0,chassis=1,multifunction=on \
						-device pcie-root-port,id=rp11,bus=pcie.0,addr=1.1,chassis=2 \
						-device pcie-root-port,id=rp12,bus=pcie.0,addr=1.2,chassis=3 \
						-device pcie-root-port,id=rp13,bus=pcie.0,addr=1.3,chassis=4 \
						-device pcie-root-port,id=rp14,bus=pcie.0,addr=1.4,chassis=5 \
						-device pcie-root-port,id=rp15,bus=pcie.0,addr=1.5,chassis=6 \
						-device pcie-root-port,id=rp16,bus=pcie.0,addr=1.6,chassis=7 \
						-device virtio-serial-pci,bus=rp10 \
						-device virtconsole,chardev=char0,name=console.0 \
						-device isa-debugcon,iobase=0x402,chardev=char0 \
						-object rng-random,filename=/dev/urandom,id=rng0 \
						-device virtio-rng-pci,bus=rp11,rng=rng0 \
						-device virtio-gpu-pci,bus=rp12 \
						-device e1000e,netdev=net0,bus=rp13 \
						-netdev user,id=net0,hostfwd=tcp::5555-:22 \
						-usb \
						-device qemu-xhci,id=xhci,bus=rp14 \
						-device usb-storage,bus=xhci.0,drive=stick,removable=on \
						-device usb-kbd,bus=xhci.0 \
						-device usb-mouse,bus=xhci.0 \
						-device usb-ccid,bus=xhci.0 \
						-drive if=none,id=stick,format=raw,file=${USBIMG} \
						-global driver=cfi.pflash01,property=secure,value=on \
						-drive if=pflash,unit=0,format=raw,file=${CODEX64},readonly=on \
						-drive if=pflash,unit=1,format=raw,file=${VARSX64} \
						-drive file=${DISKIMG},format=raw,if=none,id=hd0 \
						-device nvme,bus=rp16,serial=deadbeef,drive=hd0 \
						-chardev socket,id=chrtpm,path=/tmp/tpm/swtpm-sock \
						-tpmdev emulator,id=tpm0,chardev=chrtpm \
						-device tpm-tis,tpmdev=tpm0

TPMEMU = $(SWTPM) socket --tpm2 -d \
				 --tpmstate dir=/tmp/tpm,mode=0600 \
				 --ctrl type=unixio,path=/tmp/tpm/swtpm-sock,mode=0600 \
				 --log level=20,file=${REPO}/logs/tpm.log

.PHONY: help
help:
	@echo "make [option]"
	@echo 
	@echo "options:"
	@echo "    help            print this message"
	@echo "    all             initialize repo, build qemu and edk2"
	@echo "    init            initialize git submodules, compile BaseTools,"
	@echo "                    create disk images, and create virtual environment"
	@echo "    qemu            configure and build qemu"
	@echo "    qemu-config     configure qemu"
	@echo "    edk2            build OVMF firmware"
	@echo "    generate_keys   generate platform keys using GnuTLS"
	@echo "    run             run emulation"
	@echo "    run-cli         run emulation without GUI"
	@echo "    dbg             run emulation to attach to a gdb instance"
	@echo "    integrity       run emulation with wrong supplied firmware hash"
	@echo "    tpm             run TPM emulation"
	@echo "    dirs            create logs/, qemu/build/, images/, keys/, /tmp/tpm"
	@echo "    clean           clean build"
	@echo "    clean-edk2      clean EDKII build"
	@echo "    clean-qemu      clean QEMU build"
	@echo 

.PHONY: all
all: init qemu edk2 busybox linux

.PHONY: init
init: dirs images
	$(MAKE) -C ${REPO}/edk2/BaseTools
	if ! test -d ${VENV_PATH}; then ${PYTHON} -m venv ${VENV_PATH}; fi
	source ${VENV_PATH}/bin/activate
	pip install setuptools PyYAML cryptography ${REPO}/ovmfvartool

.PHONY: images
images: clean-images
	dd if=/dev/zero of=${USBIMG} bs=32M count=1 status=progress
	dd if=/dev/zero of=${ZEROIMG} bs=32M count=2 status=progress
	dd if=/dev/zero of=${DISKIMG} bs=32M count=4 status=progress
	sgdisk -Z ${DISKIMG}
	sgdisk -n 1:0:+48MiB -t 1:ef00 ${DISKIMG}
	sgdisk -n 2:0:0 -t 2:8300 ${DISKIMG}

.PHONY: disk
disk: images
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	sudo mkfs.fat -F 32 -n EFI ${LOOP}p1
	sudo mkfs.ext4 ${LOOP}p2
	sudo losetup -D ${LOOP}

.PHONY: keys_img
keys_img:
	dd if=/dev/zero of=${KEYSIMG} bs=32M count=2 status=progress
	sgdisk -Z ${KEYSIMG}
	sgdisk -n 1:0:0 -t 1:ef00 ${KEYSIMG}
	sudo losetup ${LOOP} -P ${KEYSIMG}
	sudo mkfs.fat -F 32 -n EFI ${LOOP}p1
	sudo losetup -D ${LOOP}

.PHONY: qemu
qemu: qemu-config
	$(MAKE) -C ${REPO}/qemu/build

.PHONY: edk2
edk2:
	export WORKSPACE=${REPO}/edk2
	export GCC5_BIN=${GCC5_X64_PREFIX}
	source ${REPO}/edk2/edksetup.sh
	cd ${REPO}/edk2
	build -p OvmfPkg/OvmfPkgX64.dsc -t GCC5 -a X64 -b ${BUILD} -Y COMPILE_INFO -y ${REPO}/logs/OvmfPkgX64.log -DSECURE_BOOT_ENABLE=TRUE -DLIBSPDM_ENABLE=TRUE -DSMM_REQUIRE=TRUE

.PHONY: generate_keys
generate_keys:
	$(CC) -O3 -g -Wall $(shell pkg-config --cflags gnutls) -D${BUILD} ${REPO}/scripts/generate_keys.c -o ${REPO}/scripts/generate_keys $(shell pkg-config --libs gnutls)
	cd ${REPO}
	${REPO}/scripts/generate_keys

.PHONY: rcS
rcS:
	sudo cat <<EOF > ${REPO}/rcS
		#!/bin/sh

		mount -t devtmpfs devtmpfs /dev
		mount -t proc proc /proc
		mount -t sysfs sysfs /sys

		cat <<!

		Boot took \$$(cut -d' ' -f1 /proc/uptime seconds)

		!
		lshw -short
	EOF

.PHONY: inittab
inittab:
	sudo cat <<EOF > ${REPO}/inittab
		::sysinit:/etc/init.d/rcS
		::askfirst:/bin/cttyhack /bin/sh -l
		::respawn:/sbin/getty hvc0 9600 vt100
	EOF

.PHONY: creds
creds:
	sudo echo "root:x:0:0:root:/:/bin/sh" > passwd
	sudo echo "root:$$(openssl passwd -5 -noverify root):0::::::" > shadow

.PHONY: etc
etc: rcS inittab creds

.PHONY: busybox
busybox: disk etc dirs
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	sudo mount ${LOOP}p2 ${REPO}/mnt/drive
	sed 's|CONFIG_PREFIX=.*|CONFIG_PREFIX="${REPO}/mnt/drive"|' ${REPO}/configs/busybox.config > ${REPO}/busybox/.config
	ARCH=x86_64 CROSS_COMPILE=${GCC5_X64_PREFIX} $(MAKE) -C ${REPO}/busybox oldconfig
	ARCH=x86_64 CROSS_COMPILE=${GCC5_X64_PREFIX} $(MAKE) -C ${REPO}/busybox
	sudo ARCH=x86_64 CROSS_COMPILE=${GCC5_X64_PREFIX} $(MAKE) -C ${REPO}/busybox install
	sudo mkdir -p ${REPO}/mnt/drive/{bin,sbin,etc/init.d,proc,sys,usr/{bin,sbin,lib},lib,dev,mnt,root,tmp,var/log}
	sudo chmod +x ${REPO}/rcS
	sudo mv ${REPO}/rcS ${REPO}/mnt/drive/etc/init.d
	sudo mv ${REPO}/inittab ${REPO}/mnt/drive/etc
	sudo mv ${REPO}/passwd ${REPO}/mnt/drive/etc
	sudo mv ${REPO}/shadow ${REPO}/mnt/drive/etc
	pushd ${REPO}/mnt/drive
	sudo ln -sfn sbin/init init
	popd
	sudo umount ${REPO}/mnt/drive
	sudo losetup -D ${LOOP}

.PHONY: linux
linux: vars dirs
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	cp ${REPO}/configs/linux.config ${REPO}/linux/.config
	ARCH=x86_64 CROSS_COMPILE=${GCC5_X64_PREFIX} $(MAKE) -C ${REPO}/linux oldconfig
	ARCH=x86_64 CROSS_COMPILE=${GCC5_X64_PREFIX} $(MAKE) -C ${REPO}/linux
	sudo mount ${LOOP}p1 ${REPO}/mnt/efi
	sudo mkdir -p ${REPO}/mnt/efi/EFI/BOOT
	sudo sbsign --key ${KEYS}/DB.key --cert ${KEYS}/DB.crt --output ${REPO}/mnt/efi/EFI/BOOT/BOOTX64.EFI ${REPO}/linux/arch/x86/boot/bzImage
	sudo umount -d ${REPO}/mnt/efi
	sudo losetup -D ${LOOP}

.PHONY: vars
vars: generate_keys
	source ${VENV_PATH}/bin/activate
	python ${REPO}/scripts/generate_vars_yaml -w ${REPO}
	ovmfvartool compile ${REPO}/vars.yaml ${REPO}/ovmf_vars_custom.fd

.PHONY: run
run: tpm
	$(QEMUX64) $(QFLAGSX64)

.PHONY: perf
perf: tpm
	sudo perf kvm stat --event duration_time,instructions,branch-instructions,branch-misses,cpu-cycles,cache-misses,cache-references,stalled-cycles-backend,stalled-cycles-frontend $(QEMUX64) $(QFLAGSX64) -enable-kvm -nographic

.PHONY: run-cli
run-cli: tpm
	$(QEMUX64) $(QFLAGSX64) -nographic

.PHONY: dbg
dbg: tpm
	$(QEMUX64) $(QFLAGSX64) -nographic -s -S

.PHONY: integrity
integrity: tpm
	$(QEMUX64) $(QFLAGSX64)

.PHONY: tpm
tpm: dirs
	@$(TPMEMU)

qemu-config: dirs
	cd ${REPO}/qemu/build
	../configure \
		--target-list=x86_64-softmmu \
		--disable-werror \
		--enable-libspdm \
		--libspdm-crypto=mbedtls \
		--libspdm-toolchain=${TOOLCHAIN} \
		--enable-gcov \
		--enable-debug \
		--enable-gnutls \
		--enable-gtk \
		--enable-system \
		--enable-sdl \
		--enable-slirp \
		--enable-plugins \
		--enable-kvm

.PHONY: dirs
dirs:
	$(MKDIR) ${REPO}/logs/
	$(MKDIR) ${REPO}/qemu/build
	$(MKDIR) ${REPO}/images
	$(MKDIR) ${KEYS}
	$(MKDIR) /tmp/tpm
	$(MKDIR) ${REPO}/mnt/efi
	$(MKDIR) ${REPO}/mnt/drive
	$(MKDIR) ${REPO}/mnt/rootfs

.PHONY: clean
clean: clean-edk2 clean-qemu clean-images

clean-qemu:
	rm -rf ${REPO}/qemu/build

clean-edk2:
	rm -rf ${REPO}/edk2/Build

clean-images:
	rm -rf ${REPO}/images/*

