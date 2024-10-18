QEMUX64 = ${REPO}/qemu/build/qemu-system-x86_64

BIOS = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF.fd
CODEX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
VARSX64 = ${REPO}/edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd

ZEROIMG = ${REPO}/zero.img

TPMEMU = swtpm socket --tpmstate dir=/tmp/tpm --ctrl type=unixio,path=/tmp/tpm/swtpm-sock --log level=20

QFLAGSX64 = -M q35,pflash0=code,pflash1=vars -m 1G -nographic -drive if=none,id=code,format=raw,file=$(CODEX64),readonly=on -drive if=none,id=vars,format=raw,file=$(VARSX64),snapshot=on -drive file=$(ZEROIMG),format=raw,if=none,id=hd0 -device nvme,serial=deadbeef,drive=hd0 -chardev socket,id=chrtpm,path=/tmp/tpm/swtpm-sock -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 

qemu-build: qemu-config
	cd ${REPO}/qemu/build && \
	make -j$(NPROC)

edk2-build:
	cd ${REPO}/edk2 && \
	build

x64-run: tpm-run check-disk
	$(QEMUX64) $(QFLAGSX64)

x64-dbg: tpm-run check-disk
	$(QEMUX64) $(QFLAGSX64) -s -S 

x64-log: tpm-run check-disk
	$(QEMUX64) $(QFLAGSX64) > ${REPO}/logs/qemu-log.txt 2>&1

tpm-run:
	if ! test -d /tmp/tpm ; then mkdir /tmp/tpm ; fi
	$(TPMEMU) > ${REPO}/logs/tpm-log.txt 2>&1 &

qemu-config:
	if ! test -d ${REPO}/qemu/build ; then mkdir ${REPO}/qemu/build ; fi
	cd ${REPO}/qemu/build && \
	../configure --target-list=x86_64-softmmu --disable-werror --enable-libspdm --libspdm-crypto=mbedtls --enable-gcov --enable-debug --enable-nettle -enable-system 

check-disk:
	if ! test -f $(ZEROIMG) ; then dd if=/dev/zero of=$(ZEROIMG) bs=32M count=1 ; fi
