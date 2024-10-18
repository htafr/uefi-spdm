DIR ?= $(PWD)

ifeq ($(WORKSPACE),)
	export WORKSPACE=$(DIR)
	export PACKAGES_PATH=$(DIR)/edk2
	export GCC5_X64_PREFIX=x86_64-linux-gnu-
	source $(DIR)/edk2/edksetup.sh
endif

QEMUX64 = $(DIR)/qemu/build/qemu-system-x86_64

BIOS = $(DIR)/Build/OvmfX64/DEBUG_GCC5/FV/OVMF.fd
CODEX64 = $(DIR)/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
VARSX64 = $(DIR)/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd

ZEROIMG = $(DIR)/zero.img

TPMEMU = swtpm socket --tpmstate dir=/tmp/tpm --ctrl type=unixio,path=/tmp/tpm/swtpm-sock --log level=20

QFLAGSX64 = -M q35,pflash0=code,pflash1=vars -m 1G -nographic -drive if=none,id=code,format=raw,file=$(CODEX64),readonly=on -drive if=none,id=vars,format=raw,file=$(VARSX64),snapshot=on -drive file=$(ZEROIMG),format=raw,if=none,id=hd0 -device nvme,serial=deadbeef,drive=hd0 -chardev socket,id=chrtpm,path=/tmp/tpm/swtpm-sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 

qemu-config:
	if ! test -d $(DIR)/qemu/build ; then mkdir $(DIR)/qemu/build ; fi
	pushd $(DIR)/qemu/build
	../configure --target-list=x86_64-softmmu --disable-werror --enable-libspdm --libspdm-crypto=mbedtls --enable-gcov --enable-debug --enable-nettle -enable-system 
	popd
	if ! test -f $(ZEROIMG) ; then dd if=/dev/zero of=$(ZEROIMG) bs=32M count=1 ; fi

qemu-build: qemu-config
	pushd $(DIR)/qemu/build
	make -j$(NPROC)
	popd

edk2-build:
	build

tpm-run:
	if ! test -d /tmp/tpm ; then mkdir /tmp/tpm ; fi
	$(TPMEMU) > $(DIR)/logs/tpm-log.txt 2>&1 &

x64-run: tpm-run
	$(QEMUX64) $(QFLAGSX64)

x64-dbg: tpm-run
	$(QEMUX64) $(QFLAGSX64) -s -S 

x64-log: tpm-run
	$(QEMUX64) $(QFLAGSX64) > $(DIR)/logs/qemu-log.txt 2>&1
