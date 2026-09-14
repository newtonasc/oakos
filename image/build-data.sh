#!/usr/bin/env bash
# Cria o disco de dados persistente do OakOS: workspace, conta Claude
# (~/.claude) e config da IDE (~/.config/code-server, onde mora a senha
# gerada por ela), todos montados por bind em cima do sistema (ver
# overlay/etc/fstab).
#
# Ao contrario de build/oakos.ext4 (o sistema, recriado a cada 'make'),
# este disco NUNCA e apagado por 'make'/'make clean' -- e onde o login e
# os arquivos do workspace sobrevivem a reconstrucoes da imagem. So roda
# se o arquivo ainda nao existir; idempotente de proposito, pra poder
# chamar de 'run.sh' toda vez sem custo.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build/oakos-data.ext4"
SIZE="${OAK_DATA_SIZE:-20G}"

if [ -f "$OUT" ]; then
    echo ">> $OUT ja existe, mantendo (apague na mao pra recriar do zero)"
    exit 0
fi

echo ">> criando disco de dados persistente ($SIZE, sparse)"
mkdir -p build

# Semeado via 'mke2fs -d', igual ao build-image.sh faz com o rootfs: evita
# precisar montar o disco (loop device, que pede privilegio) so pra copiar
# dois diretorios vazios pra dentro. O README fica so no workspace -- o
# claude/ comeca vazio mesmo, ninguem loga antes do primeiro boot.
SEED="$(mktemp -d)"
trap 'rm -rf "$SEED"' EXIT

mkdir -p "$SEED/workspace" "$SEED/claude" "$SEED/config/code-server"
cat > "$SEED/workspace/README.md" <<'MSG'
# workspace

Pasta padrao aberta pelo code-server. Vive no disco de dados persistente
(build/oakos-data.ext4, fora da imagem do sistema) -- sobrevive tanto a
reinicios quanto a reconstrucoes ('make clean && make').
MSG

mke2fs -q -t ext4 -L OAKDATA -d "$SEED" "$OUT" "$SIZE"

echo ">> $OUT criado ($(du -h "$OUT" | cut -f1) em disco)"
