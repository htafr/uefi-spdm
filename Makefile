.ONESHELL:
SHELL := /usr/bin/bash

# $(eval GUID := $(shell uuidgen))
# openssl req -x509 -new -nodes -sha256 -subj "/CN=LARC/" -key ${KEYS}/PK.key -outform PEM -out ${KEYS}/PK.pem -days 365
# sed \
# 	-e "s/^-----BEGIN CERTIFICATE-----$$/${GUID}:/" \
# 	-e "/^-----END CERTIFICATE-----$$/d" \
# 	${KEYS}/PK.pem \
# 	| tr -d '\n' >${KEYS}/PK.oemstr
# openssl x509 -in ${KEYS}/PK.pem -inform PEM -out ${KEYS}/PK.cer -outform DER
# sbsiglist --owner ${GUID} --type x509 --output ${KEYS}/PK.esl ${KEYS}/PK.cer
# sbvarsign --key ${KEYS}/PK.key --cert ${KEYS}/PK.pem --output ${KEYS}/PK.auth ${KEYS}/PK ${KEYS}/PK.esl
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
GCC5_X64_PREFIX ?= gcc
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

CODEX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
# VARSX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS_INTEGRITY.fd
# VARSX64 = ${REPO}/ovmf_vars_spdm.fd
VARSX64 = ${REPO}/ovmf_vars_custom.fd
# VARSX64 = ${REPO}/vars.fd

ZEROIMG = ${REPO}/images/zero.img
DISKIMG = ${REPO}/images/disk.img
# DISKIMG = ${REPO}/../linux/disk.img
KEYSIMG = ${REPO}/images/keys.img
USBIMG = ${REPO}/images/usb.img

# -global driver=cfi.pflash01,property=secure,value=on
QFLAGSX64 = -M q35,smm=on -smp 4 -m 1G -nodefaults -bios none \
						-chardev stdio,mux=on,id=char0 \
						-serial chardev:char0 \
						-parallel chardev:char0 \
						-device pcie-root-port,id=pci20,bus=pcie.0,chassis=1,addr=2.0,multifunction=on,pref64-reserve=32M \
						-device pcie-root-port,id=pci21,bus=pcie.0,chassis=2,addr=2.1 \
						-device pcie-root-port,id=pci22,bus=pcie.0,chassis=3,addr=2.2 \
						-device pcie-root-port,id=pci23,bus=pcie.0,chassis=4,addr=2.3 \
						-device pcie-root-port,id=pci30,bus=pcie.0,chassis=31,addr=3.0,multifunction=on,pref64-reserve=32M \
						-device pcie-root-port,id=pci31,bus=pcie.0,chassis=32,addr=3.1 \
						-device virtio-serial-pci,bus=pci21 \
						-device virtconsole,chardev=char0,name=console.0 \
						-device isa-debugcon,iobase=0x402,chardev=char0 \
						-object rng-random,filename=/dev/urandom,id=rng0 \
						-device virtio-rng-pci,bus=pci22,rng=rng0 \
						-device virtio-gpu-pci,bus=pci23 \
						-device e1000e,netdev=net0,bus=pci30 -netdev user,id=net0,hostfwd=tcp::5555-:22 \
						-usb \
						-device qemu-xhci,id=xhci \
						-device usb-storage,bus=xhci.0,drive=stick,removable=on \
						-device usb-kbd,bus=xhci.0 \
						-device usb-mouse,bus=xhci.0 \
						-drive if=none,id=stick,format=raw,file=${USBIMG} \
						-global driver=cfi.pflash01,property=secure,value=on \
						-drive if=pflash,unit=0,format=raw,file=${CODEX64},readonly=on \
						-drive if=pflash,unit=1,format=raw,file=${VARSX64} \
						-drive file=${DISKIMG},format=raw,if=none,id=hd0 \
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
all: init qemu edk2

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
edk2: generate_keys
	export WORKSPACE=${REPO}/edk2
	export GCC5_BIN=${GCC5_X64_PREFIX}
	source ${REPO}/edk2/edksetup.sh
	cd ${REPO}/edk2
	build -p OvmfPkg/OvmfPkgX64.dsc -t GCC5 -a X64 -b DEBUG -Y COMPILE_INFO -y ${REPO}/logs/OvmfPkgX64.log -DSECURE_BOOT_ENABLE=TRUE -DLIBSPDM_ENABLE=TRUE -DSMM_REQUIRE=TRUE

.PHONY: generate_keys
generate_keys:
	$(CC) -O3 -g -Wall $(shell pkg-config --cflags gnutls) ${REPO}/scripts/generate_keys.c -o ${REPO}/scripts/generate_keys $(shell pkg-config --libs gnutls)
	cd ${REPO}
	${REPO}/scripts/generate_keys

.PHONY: enroll-setup
enroll-setup: dirs images vars
	$(eval LOOP := $(shell sudo losetup -fP --show ${KEYSIMG}))
	sudo mount ${LOOP}p1 /mnt/efi
	sudo cp ${KEYS}/PK.* /mnt/efi
	sudo cp ${KEYS}/KEK.* /mnt/efi
	sudo cp ${KEYS}/DB.* /mnt/efi
	sudo chmod 644 /mnt/efi/PK.*
	sudo chmod 644 /mnt/efi/KEK.*
	sudo chmod 644 /mnt/efi/DB.*
	sudo umount /mnt/efi
	sudo losetup -D ${LOOP}

.PHONY: grub
grub: vars
	cd ${GRUB}
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	sudo mount ${LOOP}p1 /mnt/efi
	sudo mount ${LOOP}p2 /mnt/drive
	TARGET_CC=${GCC5_X64_PREFIX}gcc ./configure --target=x86_64 --with-platform=efi --disable-werror
	$(MAKE)
	sudo TARGET_CC=${GCC5_X64_PREFIX}gcc ./grub-install \
		--target=x86_64-efi \
		--directory=grub-core \
		--efi-directory=/mnt/efi/ \
		--bootloader-id=GRUB \
		--modules="normal part_msdos part_gpt multiboot" \
		--root-directory=/mnt/drive/ \
		--no-floppy ${LOOP}
	sudo sbsign --key ${KEYS}/DB.key --cert ${KEYS}/DB.crt --output /mnt/efi/EFI/BOOT/BOOTX64.EFI /mnt/efi/EFI/GRUB/grubx64.efi
	sudo umount /mnt/efi /mnt/drive
	sudo losetup -D ${LOOP}

# sudo sbsign --key ${KEYS}/DB.key --cert ${KEYS}/DB.crt --output /mnt/efi/EFI/BOOT/BOOTX64.EFI /mnt/efi/EFI/BOOT/orig.efi
.PHONY: ext2
ext2:
	sudo mount -o loop ${REPO}/../buildroot/output/images/rootfs.ext2 /mnt/rootfs
	sudo umount -d /mnt/rootfs

.PHONY: buildroot
buildroot: vars
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	sudo mount -o loop ${REPO}/../buildroot/output/images/rootfs.ext2 /mnt/rootfs
	sudo mount ${LOOP}p1 /mnt/efi
	sudo mount ${LOOP}p2 /mnt/drive
	sudo cp -r /mnt/rootfs/* /mnt/drive
	sudo mkdir -p /mnt/efi/EFI/BOOT
	sudo sbsign --key ${KEYS}/DB.key --cert ${KEYS}/DB.crt --output /mnt/efi/EFI/BOOT/BOOTX64.EFI ${REPO}/../buildroot/output/images/bzImage
	sudo umount -d /mnt/rootfs /mnt/efi /mnt/drive

.PHONY: rcS
rcS:
	sudo cat <<EOF > ${REPO}/rcS
		#!/bin/sh

		mount -t devtmpfs none /dev
		mount -t proc none /proc
		mount -t sysfs none /sys

		cat <<!

		Boot took $(cut -d' ' -f1 /proc/uptime seconds)

		!
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
	sudo echo "root:$(openssl passwd -noverify root):0::::::" > shadow

.PHONY: etc
etc: rcS inittab creds

.PHONY: busybox
busybox: disk etc
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	sudo mount ${LOOP}p2 ${REPO}/mnt/drive
	cp ${REPO}/configs/busybox.config ${REPO}/busybox/.config
	ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu- $(MAKE) -C ${REPO}/busybox oldconfig
	ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu- $(MAKE) -C ${REPO}/busybox
	sudo ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu- $(MAKE) -C ${REPO}/busybox install
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
linux: vars
	$(eval LOOP := $(shell sudo losetup -fP --show ${DISKIMG}))
	cp ${REPO}/configs/linux.config ${REPO}/linux/.config
	ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu- $(MAKE) -C ${REPO}/linux oldconfig
	ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu- $(MAKE) -C ${REPO}/linux
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
		--enable-slirp

# -nodes: No DES encryption
.PHONY: keys
keys: dirs
	openssl req -newkey rsa:2048 -nodes -keyout ${KEYS}/TEST_PK.key -new -x509 -sha256 -days 365 -subj "/CN=SPDM" -out ${KEYS}/TEST_PK.pem
	openssl req -new -newkey rsa:2048 -nodes -outform PEM -keyout ${KEYS}/TEST_KEK.key -out ${KEYS}/TEST_KEK.csr
	openssl x509 -req -in ${KEYS}/TEST_KEK.csr -days 365 -CA ${KEYS}/TEST_PK.pem -CAkey ${KEYS}/TEST_PK.key -CAcreateserial -out ${KEYS}/TEST_KEK.pem
	for k in PK KEK; do \
		openssl x509 -inform PEM -in ${KEYS}/TEST_$$k.pem -outform DER -out ${KEYS}/TEST_$$k.der
	done

.PHONY: dirs
dirs:
	$(MKDIR) ${REPO}/logs/
	$(MKDIR) ${REPO}/qemu/build
	$(MKDIR) ${REPO}/images
	$(MKDIR) ${KEYS}
	$(MKDIR) /tmp/tpm
	sudo $(MKDIR) /mnt/efi
	sudo $(MKDIR) /mnt/drive
	sudo $(MKDIR) /mnt/rootfs

.PHONY: clean
clean: clean-edk2 clean-qemu clean-images

clean-qemu:
	rm -rf ${REPO}/qemu/build

clean-edk2:
	rm -rf ${REPO}/edk2/Build

clean-images:
	rm -rf ${REPO}/images/*

