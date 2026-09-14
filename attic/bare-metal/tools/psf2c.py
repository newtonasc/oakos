#!/usr/bin/env python3
"""Converte uma fonte PSF (v1 ou v2) num array C embutido no kernel.

Uso: psf2c.py <entrada.psf[.gz]> <saida.h>
Gera apenas os 256 primeiros glifos (Latin-1), que e o que o console usa.
"""
import gzip, struct, sys

def load(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as f:
        return f.read()

def parse(data):
    if data[:2] == b"\x36\x04":                       # PSF1
        charsize = data[3]
        count = 512 if (data[2] & 0x01) else 256
        return 8, charsize, count, data[4:4 + count * charsize]
    if data[:4] == b"\x72\xb5\x4a\x86":               # PSF2
        _, _, hdrsize, _, count, charsize, height, width = struct.unpack("<8I", data[:32])
        if width != 8:
            sys.exit(f"erro: so suportamos fontes de 8px de largura (essa tem {width})")
        return width, height, count, data[hdrsize:hdrsize + count * charsize]
    sys.exit("erro: nao parece um arquivo PSF")

def main():
    src, dst = sys.argv[1], sys.argv[2]
    w, h, count, glyphs = parse(load(src))
    count = min(count, 256)
    glyphs = glyphs[:count * h]

    with open(dst, "w") as out:
        out.write("/* Gerado por tools/psf2c.py a partir de %s -- nao edite a mao. */\n" % src)
        out.write("#pragma once\n#include <stdint.h>\n\n")
        out.write("#define FONT_WIDTH  %d\n#define FONT_HEIGHT %d\n" % (w, h))
        out.write("#define FONT_GLYPHS %d\n\n" % count)
        out.write("static const uint8_t font_bitmap[FONT_GLYPHS][FONT_HEIGHT] = {\n")
        for c in range(count):
            row = glyphs[c * h:(c + 1) * h]
            out.write("    { " + ", ".join("0x%02x" % b for b in row) + " },\n")
        out.write("};\n")
    print(f"{dst}: {count} glifos de {w}x{h}")

main()
