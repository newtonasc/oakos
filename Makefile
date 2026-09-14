# OakOS -- um sistema operacional onde o agente e a interface.

.PHONY: all rootfs image data bootable run clean distclean deps

all: image

## rootfs: baixa e monta o sistema de arquivos raiz (demorado na 1a vez)
rootfs: build/rootfs.tar

build/rootfs.tar: image/packages.list image/chroot-setup.sh $(shell find overlay -type f 2>/dev/null)
	@image/build-rootfs.sh

## image: gera o disco ext4 bootavel + kernel + initrd
image: build/oakos.ext4

build/oakos.ext4: build/rootfs.tar
	@image/build-image.sh

## data: cria (uma vez so) o disco de dados persistente -- workspace + conta
## Claude. NUNCA e alvo de 'clean'/'distclean': e o que sobrevive a rebuilds.
data: build/oakos-data.ext4

build/oakos-data.ext4:
	@image/build-data.sh

## bootable: gera a imagem GPT auto-bootavel (ESP + systemd-boot), pra
## pendrive/VPS. Depende de 'image' pra garantir build/rootfs fresco.
bootable: image
	@image/build-bootable.sh

## run: boota o OakOS no QEMU (boot rapido, -kernel/-initrd, sem bootloader)
run: build/oakos.ext4 data
	@./run.sh

## run-bootable: boota a imagem GPT via firmware UEFI (OVMF) -- valida o
## bootloader de verdade, mais lento pra iterar que 'run'
run-bootable: bootable
	@./run-bootable.sh

## clean: apaga a imagem, mantem o rootfs baixado e o disco de dados
clean:
	rm -rf build/rootfs build/oakos.ext4 build/oakos-bootable.img \
	       build/OVMF_VARS.fd build/vmlinuz build/initrd.img

## distclean: apaga tudo, inclusive o rootfs (forca novo download) -- MENOS
## o disco de dados (oakos-data.ext4): e o unico artefato de verdade
## persistente do projeto (login, workspace, senha da IDE). Pra apagar
## esse tambem, e na mao: 'rm build/oakos-data.ext4'.
distclean:
	[ -d build ] && find build -mindepth 1 -maxdepth 1 ! -name oakos-data.ext4 -exec rm -rf {} + || true

## deps: mostra o que precisa estar instalado no host
deps:
	@echo "sudo apt install -y mmdebstrap uidmap debian-archive-keyring \\"
	@echo "    e2fsprogs qemu-system-x86 qemu-utils mtools"
	@echo "sudo usermod -aG kvm $$USER   # e reabrir o terminal"
