#!/usr/bin/env bash
# Boota o OakOS no QEMU.
#
# Nao usamos bootloader por enquanto: o QEMU carrega kernel e initrd
# diretamente (-kernel/-initrd). Isso corta uns 10 segundos de cada ciclo de
# teste. Um bootloader de verdade entra quando a imagem precisar bootar
# fora do QEMU (pendrive, VPS, hardware real).
set -euo pipefail

cd "$(dirname "$0")"

MEM="${MEM:-4G}"    # Docker + IDE + varios projetos ao mesmo tempo pedem mais
CPUS="${CPUS:-4}"

for f in build/vmlinuz build/initrd.img build/oakos.ext4; do
    [ -f "$f" ] || { echo "!! falta $f -- rode 'make' primeiro"; exit 1; }
done

# Disco de dados persistente (workspace + conta Claude): criado uma vez so,
# nunca apagado por 'make'/'make clean'. Chamado direto aqui (nao so pelo
# 'make data') pra quem roda './run.sh' sem passar pelo Makefile tambem
# ganhar persistencia -- o script e idempotente, nao custa nada se o
# arquivo ja existe.
image/build-data.sh

# KVM da velocidade quase nativa, mas so se tivermos permissao no /dev/kvm.
# Sem ele o QEMU emula por software (TCG): funciona, so e mais lento.
#
# -cpu qemu64 (o "generico" classico do QEMU) NAO tem instrucoes que o
# V8/Node modernos esperam -- Claude Code literalmente crasha com "trap
# invalid opcode" nele (testado, nao suposto). '-cpu max' expoe tudo que o
# TCG consegue emular e resolve; com KVM, '-cpu host' ja da o hardware real.
if [ -w /dev/kvm ]; then
    ACCEL=(-accel kvm -cpu host)
    echo ">> aceleracao: KVM"
else
    ACCEL=(-accel tcg -cpu max)
    echo ">> aceleracao: TCG (software) -- adicione seu usuario ao grupo kvm pra acelerar"
fi

# console=tty0 primeiro, ttyS0 por ultimo: o ultimo vira /dev/console, que e
# onde o systemd poe o getty. Como rodamos -nographic, queremos a serial.
CMDLINE="root=/dev/vda rw console=tty0 console=ttyS0,115200 quiet ${OAK_CMDLINE:-}"

# hostfwd expoe portas do guest no host (esta maquina WSL2). O WSL2, por sua
# vez, encaminha localhost automaticamente pro Windows -- entao o navegador
# do seu PC chega em qualquer uma delas sem configurar nada a mais.
#
# IMPORTANTE: isso so importa pra VOCE ver as coisas de fora. Dentro da VM,
# os projetos ja se enxergam livremente uns aos outros por localhost (ou por
# nome de servico, se estiverem no mesmo docker compose) -- essa lista nao
# afeta em nada a comunicacao entre eles.
#
# 8080 e fixa (a IDE). O resto cobre os padroes mais comuns de dev server,
# o bastante pra uns 3 projetos simultaneos sem precisar editar nada:
DEFAULT_PORTS=(3000 3001 3002 5173 5174 8000 8001 5000)

# Precisa de mais? Sem editar o script:
#   OAK_PORTS="4000 9000" ./run.sh
read -ra EXTRA_PORTS <<< "${OAK_PORTS:-}"
ALL_PORTS=(8080 "${DEFAULT_PORTS[@]}" "${EXTRA_PORTS[@]}")

NETDEV="user,id=net0"
for p in "${ALL_PORTS[@]}"; do
    NETDEV+=",hostfwd=tcp::${p}-:${p}"
done

echo ">> IDE em http://localhost:8080"
echo ">> portas de projeto encaminhadas: ${DEFAULT_PORTS[*]} ${EXTRA_PORTS[*]}"
echo ">> ctrl-a x para sair do QEMU"
echo

exec qemu-system-x86_64 \
    -machine q35 \
    "${ACCEL[@]}" \
    -m "$MEM" -smp "$CPUS" \
    -kernel build/vmlinuz \
    -initrd build/initrd.img \
    -append "$CMDLINE" \
    -drive file=build/oakos.ext4,if=virtio,format=raw \
    -drive file=build/oakos-data.ext4,if=virtio,format=raw \
    -netdev "$NETDEV" \
    -device virtio-net-pci,netdev=net0 \
    -nographic
