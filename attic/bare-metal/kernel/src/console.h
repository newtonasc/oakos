/* console.h -- console de texto desenhado pixel a pixel no framebuffer.
 *
 * O Limine ja nos entrega um framebuffer linear configurado pela firmware:
 * um ponteiro pra memoria de video onde cada pixel e um valor de 32 bits.
 * Nao existe "modo texto" aqui -- se voce quer uma letra na tela, voce
 * desenha os pixels dela. E o que console_putchar faz, usando a fonte
 * bitmap embutida em font.h. */
#pragma once

#include "kstd.h"
#include "../../limine/limine.h"

/* Cores no formato 0xRRGGBB. O console converte pro layout real do
 * framebuffer (que varia conforme o hardware) na hora de escrever. */
#define OAK_BG      0x0d1117
#define OAK_FG      0xc9d1d9
#define OAK_ACCENT  0x7ee787
#define OAK_DIM     0x6e7681
#define OAK_WARN    0xf0883e

bool console_init(struct limine_framebuffer *fb);
void console_putchar(char c);
void console_write(const char *s, size_t len);
void console_set_color(uint32_t rgb);
uint32_t console_get_color(void);
void console_clear(void);

uint64_t console_cols(void);
uint64_t console_rows(void);
