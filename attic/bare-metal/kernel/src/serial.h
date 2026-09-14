/* serial.h -- driver da porta serial (UART 16550, COM1).
 *
 * Por que serial num SO de 2026? Porque e o canal de debug mais confiavel que
 * existe: funciona antes do video, nao depende de nada, e o QEMU consegue
 * redirecionar tudo pro seu terminal. Quando o kernel quebrar cedo demais pra
 * desenhar na tela, e a serial que vai te contar o que aconteceu. */
#pragma once

#include "kstd.h"

void serial_init(void);
void serial_putchar(char c);
void serial_write(const char *s, size_t len);
