#!/usr/bin/env bash
# Boota a imagem auto-bootavel do OakOS (build/oakos-bootable.img) via
# firmware UEFI de verdade (OVMF), sem -kernel/-initrd -- valida que o
# systemd-boot na ESP sobe o sistema sozinho, do jeito que um pendrive ou
# VPS bootaria. Separado do run.sh (boot rapido via QEMU) de proposito:
# sao dois caminhos de boot diferentes, um nao substitui o outro.
set -euo pipefail

cd "$(dirname "$0")"

MEM="${MEM:-4G}"
CPUS="${CPUS:-4}"

[ -f build/oakos-bootable.img ] || {
    echo "!! falta build/oakos-bootable.img -- rode 'make bootable' primeiro"
    exit 1
}

OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS_TEMPLATE=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] || { echo "!! nao achei $OVMF_CODE -- falta o pacote 'ovmf'"; exit 1; }

# OVMF_VARS e a NVRAM (estado gravavel) do firmware -- o template do
# pacote e so leitura, cada VM precisa da propria copia.
OVMF_VARS="build/OVMF_VARS.fd"
[ -f "$OVMF_VARS" ] || cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"

if [ -w /dev/kvm ]; then
    ACCEL=(-accel kvm -cpu host)
    echo ">> aceleracao: KVM"
else
    ACCEL=(-accel tcg -cpu max)
    echo ">> aceleracao: TCG (software) -- adicione seu usuario ao grupo kvm pra acelerar"
fi

echo ">> boot via UEFI (systemd-boot na ESP) -- sem -kernel/-initrd"
echo ">> IDE em http://localhost:8080"
echo ">> ctrl-a x para sair do QEMU"
echo

exec qemu-system-x86_64 \
    -machine q35 \
    "${ACCEL[@]}" \
    -m "$MEM" -smp "$CPUS" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive file=build/oakos-bootable.img,if=virtio,format=raw \
    -netdev user,id=net0,hostfwd=tcp::8080-:8080 \
    -device virtio-net-pci,netdev=net0 \
    -nographic
