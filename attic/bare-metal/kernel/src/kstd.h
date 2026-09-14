/* kstd.h -- o minimo de "libc" que um kernel freestanding precisa.
 *
 * Nao existe stdlib aqui: nada de malloc, printf ou strlen prontos.
 * O compilador, porem, *assume* que memcpy/memset/memmove/memcmp existem
 * (ele emite chamadas a elas sozinho, ao copiar structs por exemplo).
 * Por isso precisamos implementa-las na mao. */
#pragma once

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int   memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);

/* Trava a CPU de vez: desabilita interrupcoes e dorme para sempre.
 * Usado no fim do kmain e em panicos. */
static inline void halt_forever(void) {
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}

/* Acesso a portas de I/O do x86. Toda a comunicacao com hardware legado
 * (serial, teclado, timer) passa por essas duas instrucoes. */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" :: "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}
