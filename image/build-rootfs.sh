#!/usr/bin/env bash
# Constroi o sistema de arquivos raiz do OakOS a partir do Debian.
#
# Usa mmdebstrap em modo 'unshare': tudo acontece dentro de um namespace de
# usuario, entao nao precisamos de sudo. Dentro do namespace nosso uid parece
# root, o que basta pra montar um rootfs com dono e permissoes corretos.
set -euo pipefail

cd "$(dirname "$0")/.."

SUITE="${SUITE:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
OUT="build/rootfs.tar"

# Le a lista de pacotes ignorando comentarios e linhas vazias.
PKGS="$(grep -vE '^\s*#|^\s*$' image/packages.list | awk '{print $1}' | paste -sd,)"

echo ">> suite:   $SUITE"
echo ">> pacotes: $(echo "$PKGS" | tr ',' '\n' | wc -l)"
echo

mkdir -p build

mmdebstrap \
    --mode=unshare \
    --variant=minbase \
    --architectures=amd64 \
    --components=main \
    --include="$PKGS" \
    --aptopt='Acquire::Retries "3"' \
    --customize-hook='tar -C overlay -cf - . | tar -C "$1" -xf -' \
    --customize-hook='cp image/chroot-setup.sh "$1/tmp/"' \
    --customize-hook="chroot \"\$1\" env OAK_SUITE=$SUITE bash /tmp/chroot-setup.sh" \
    --customize-hook='rm -f "$1/tmp/chroot-setup.sh"' \
    "$SUITE" "$OUT" "$MIRROR"

echo
echo ">> $OUT  ($(du -h "$OUT" | cut -f1))"
