# OakOS -- um sistema operacional onde o agente e a interface.

.PHONY: all rootfs image run clean distclean deps

all: image

## rootfs: baixa e monta o sistema de arquivos raiz (demorado na 1a vez)
rootfs: build/rootfs.tar

build/rootfs.tar: image/packages.list image/chroot-setup.sh $(shell find overlay -type f 2>/dev/null)
	@image/build-rootfs.sh

## image: gera o disco ext4 bootavel + kernel + initrd
image: build/oakos.ext4

build/oakos.ext4: build/rootfs.tar
	@image/build-image.sh

## run: boota o OakOS no QEMU
run: build/oakos.ext4
	@./run.sh

## clean: apaga a imagem, mantem o rootfs baixado
clean:
	rm -rf build/rootfs build/oakos.ext4 build/vmlinuz build/initrd.img

## distclean: apaga tudo, inclusive o rootfs (forca novo download)
distclean:
	rm -rf build

## deps: mostra o que precisa estar instalado no host
deps:
	@echo "sudo apt install -y mmdebstrap uidmap debian-archive-keyring \\"
	@echo "    e2fsprogs qemu-system-x86 qemu-utils"
	@echo "sudo usermod -aG kvm $$USER   # e reabrir o terminal"
