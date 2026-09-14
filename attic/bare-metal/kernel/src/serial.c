#include "serial.h"

#define COM1 0x3f8

/* Offsets dos registradores da UART, relativos a porta base. */
#define REG_DATA        0   /* dados (leitura/escrita)                        */
#define REG_INT_ENABLE  1   /* habilitacao de interrupcoes                    */
#define REG_FIFO_CTRL   2   /* controle da FIFO                               */
#define REG_LINE_CTRL   3   /* formato da linha (bits, paridade, stop)        */
#define REG_MODEM_CTRL  4   /* controle de modem                              */
#define REG_LINE_STATUS 5   /* status: da pra transmitir? chegou byte?        */

#define LINE_STATUS_TX_EMPTY 0x20  /* bit 5: buffer de transmissao vazio      */

void serial_init(void) {
    outb(COM1 + REG_INT_ENABLE, 0x00);  /* sem interrupcoes: vamos por polling */
    outb(COM1 + REG_LINE_CTRL,  0x80);  /* DLAB=1: expoe o divisor de baud     */
    outb(COM1 + REG_DATA,       0x03);  /* divisor = 3 -> 115200/3 = 38400 bps */
    outb(COM1 + REG_INT_ENABLE, 0x00);  /* parte alta do divisor               */
    outb(COM1 + REG_LINE_CTRL,  0x03);  /* DLAB=0, 8 bits, sem paridade, 1 stop */
    outb(COM1 + REG_FIFO_CTRL,  0xc7);  /* liga e limpa a FIFO, trigger 14     */
    outb(COM1 + REG_MODEM_CTRL, 0x0b);  /* DTR + RTS + OUT2 ligados            */
}

/* Espera a UART aceitar o proximo byte. Polling puro -- lento, mas sem
 * dependencia de interrupcoes, que ainda nem configuramos. */
static void wait_tx_ready(void) {
    while ((inb(COM1 + REG_LINE_STATUS) & LINE_STATUS_TX_EMPTY) == 0) {
        /* ocupado */
    }
}

void serial_putchar(char c) {
    /* Terminais esperam CRLF; o kernel so emite '\n'. */
    if (c == '\n') {
        wait_tx_ready();
        outb(COM1 + REG_DATA, '\r');
    }
    wait_tx_ready();
    outb(COM1 + REG_DATA, (uint8_t)c);
}

void serial_write(const char *s, size_t len) {
    for (size_t i = 0; i < len; i++) {
        serial_putchar(s[i]);
    }
}
