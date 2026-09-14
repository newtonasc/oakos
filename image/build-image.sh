#!/usr/bin/env bash
# Transforma o tarball do rootfs num disco ext4 bootavel, e extrai o kernel
# e o initrd pra fora (o QEMU vai carregar os dois direto, sem bootloader).
#
# Todo o trabalho acontece dentro de 'unshare --map-auto', onde os uids do
# tarball (root=0, etc.) sao remapeados corretamente -- de novo, sem sudo.
set -euo pipefail

cd "$(dirname "$0")/.."

SIZE="${SIZE:-20G}"  # com Docker rodando 3 projetos, imagens somam rapido --
                      # e sparse, so ocupa disco de verdade o que for usado
TAR="build/rootfs.tar"

[ -f "$TAR" ] || { echo "!! $TAR nao existe -- rode 'make rootfs' primeiro"; exit 1; }

echo ">> desempacotando e montando imagem de $SIZE"

unshare --map-auto --map-root-user --setuid 0 --setgid 0 -- \
    bash -euo pipefail -c '
        rm -rf build/rootfs
        mkdir -p build/rootfs

        # Nos de dispositivo (/dev/console e cia) nao podem ser criados dentro
        # de um namespace de usuario -- e o kernel monta devtmpfs em /dev no
        # boot de qualquer forma, entao pular nao custa nada.
        tar -xf build/rootfs.tar -C build/rootfs --exclude="./dev/*"

        cp build/rootfs/boot/vmlinuz-*   build/vmlinuz
        cp build/rootfs/boot/initrd.img-* build/initrd.img

        rm -f build/oakos.ext4
        mke2fs -q -t ext4 -L OAKOS -d build/rootfs build/oakos.ext4 '"$SIZE"'
    '

echo
echo ">> build/oakos.ext4   ($(du -h build/oakos.ext4 | cut -f1) em disco)"
echo ">> build/vmlinuz      $(file -b build/vmlinuz | cut -c1-60)"
echo ">> build/initrd.img   ($(du -h build/initrd.img | cut -f1))"
