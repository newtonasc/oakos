#!/usr/bin/env bash
# Monta a imagem auto-bootavel do OakOS: disco GPT com ESP (FAT32,
# systemd-boot) + particao raiz (ext4) -- pra rodar fora do QEMU, em
# pendrive ou VPS.
#
# Diferente de build/oakos.ext4 (usado por run.sh): aquele nem tem tabela
# de particao, e o QEMU carrega kernel/initrd direto com -kernel/-initrd,
# sem bootloader nenhum -- ~10s mais rapido por ciclo de teste, mas nao
# boota em hardware/VPS de verdade (nao ha firmware ali pra entender
# -kernel). Esta imagem aqui e a outra ponta: um disco que qualquer
# firmware UEFI sabe bootar sozinho.
#
# Tudo sem privilegio, na mesma linha do resto do projeto: sgdisk escreve
# a tabela de particao direto no arquivo (nao precisa montar nada), e a
# ESP e escrita via mtools (mcopy/mmd), que le/escreve um FAT32 sem montar
# tambem. Cada particao e montada como arquivo solto e colada no disco
# final por offset com 'dd' -- evita loop device, que pediria privilegio.
set -euo pipefail

cd "$(dirname "$0")/.."

ROOTFS_DIR="build/rootfs"
OUT="build/oakos-bootable.img"
ESP_SIZE_MIB=256
ROOT_SIZE_MIB="${ROOT_SIZE_MIB:-8192}"

[ -d "$ROOTFS_DIR" ] || {
    echo "!! falta $ROOTFS_DIR -- rode 'make image' primeiro (e o que deixa"
    echo "!! essa pasta populada; build-image.sh nao apaga no final)"
    exit 1
}

EFI_BIN="$ROOTFS_DIR/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
[ -f "$EFI_BIN" ] || {
    echo "!! nao achei $EFI_BIN -- 'systemd-boot-efi' esta em image/packages.list?"
    exit 1
}

VMLINUZ="$(ls "$ROOTFS_DIR"/boot/vmlinuz-* | head -1)"
INITRD="$(ls "$ROOTFS_DIR"/boot/initrd.img-* | head -1)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> montando a ESP ($ESP_SIZE_MIB MiB, FAT32)"
ESP_IMG="$WORK/esp.img"
truncate -s "${ESP_SIZE_MIB}M" "$ESP_IMG"
mformat -i "$ESP_IMG" -F ::

mmd -i "$ESP_IMG" ::/EFI ::/EFI/BOOT ::/EFI/systemd ::/loader ::/loader/entries

# BOOTX64.EFI: caminho de fallback que TODO firmware UEFI tenta sozinho
# quando nao ha entrada de boot gravada na NVRAM -- essencial aqui, porque
# nao existe um "instalador" rodando dentro de um pendrive/VPS pra chamar
# 'bootctl install' e gravar essa entrada antes do primeiro boot.
mcopy -i "$ESP_IMG" "$EFI_BIN" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP_IMG" "$EFI_BIN" ::/EFI/systemd/systemd-bootx64.efi
mcopy -i "$ESP_IMG" "$VMLINUZ" ::/vmlinuz-oakos
mcopy -i "$ESP_IMG" "$INITRD"  ::/initrd-oakos.img

cat > "$WORK/loader.conf" <<'EOF'
timeout 0
default oakos
EOF
mcopy -i "$ESP_IMG" "$WORK/loader.conf" ::/loader/loader.conf

# root=LABEL=OAKOS, nao /dev/vdaN: o numero da particao pode mudar
# conforme o disco (pendrive vs VPS vs QEMU), o label nao.
cat > "$WORK/oakos.conf" <<'EOF'
title   OakOS
linux   /vmlinuz-oakos
initrd  /initrd-oakos.img
options root=LABEL=OAKOS rw console=tty0 console=ttyS0,115200 quiet
EOF
mcopy -i "$ESP_IMG" "$WORK/oakos.conf" ::/loader/entries/oakos.conf

echo ">> montando a particao raiz ($ROOT_SIZE_MIB MiB, ext4)"
ROOT_IMG="$WORK/root.img"
# unshare --map-root-user: mesmo truque do build-image.sh. Sem isso, o
# mke2fs (rodando como usuario comum) nem consegue ENTRAR em diretorios
# como var/cache/apt/archives/partial (0700, dono e um uid remapeado que
# so faz sentido dentro do namespace que gerou o rootfs.tar). Como root
# dentro de um user namespace, a checagem de permissao e ignorada --
# achado rodando de verdade (Permission denied), nao suposto.
unshare --map-auto --map-root-user --setuid 0 --setgid 0 -- \
    mke2fs -q -t ext4 -L OAKOS -d "$ROOTFS_DIR" "$ROOT_IMG" "${ROOT_SIZE_MIB}M"

echo ">> montando o disco GPT (ESP + raiz)"
TOTAL_MIB=$(( ESP_SIZE_MIB + ROOT_SIZE_MIB + 4 )) # +4 MiB: folga p/ header/backup do GPT
rm -f "$OUT"
truncate -s "${TOTAL_MIB}M" "$OUT"

sgdisk -o "$OUT" >/dev/null
sgdisk -n "1:0:+${ESP_SIZE_MIB}M" -t 1:ef00 -c 1:"EFI System" "$OUT" >/dev/null
sgdisk -n 2:0:0 -t 2:8304 -c 2:"oakos-root" "$OUT" >/dev/null

part_offset() {
    local sector
    sector="$(sgdisk -i "$1" "$OUT" | awk '/^First sector:/ {print $3}')"
    echo $(( sector * 512 ))
}
ESP_OFFSET="$(part_offset 1)"
ROOT_OFFSET="$(part_offset 2)"

# sgdisk alinha particoes em limites de 1 MiB por padrao -- se algum dia
# isso mudar (ou o layout acima mudar), o dd por seek=1M abaixo escreveria
# no lugar errado. Falha alto e visivel em vez de gerar imagem corrompida
# silenciosamente.
for off in "$ESP_OFFSET" "$ROOT_OFFSET"; do
    (( off % 1048576 == 0 )) || {
        echo "!! particao fora do alinhamento de 1 MiB esperado ($off bytes) -- sgdisk mudou de comportamento?"
        exit 1
    }
done

dd if="$ESP_IMG"  of="$OUT" bs=1M seek=$(( ESP_OFFSET  / 1048576 )) conv=notrunc status=none
dd if="$ROOT_IMG" of="$OUT" bs=1M seek=$(( ROOT_OFFSET / 1048576 )) conv=notrunc status=none

echo
echo ">> $OUT   ($(du -h "$OUT" | cut -f1) em disco, $TOTAL_MIB MiB alocados)"
