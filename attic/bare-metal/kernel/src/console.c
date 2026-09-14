#include "console.h"
#include "font.h"

static struct limine_framebuffer *g_fb;
static uint32_t *g_pixels;      /* framebuffer como array de pixels de 32 bits */
static uint64_t  g_pitch_px;    /* pixels por linha (pode ser > largura!)      */
static uint64_t  g_cols, g_rows;
static uint64_t  g_cx, g_cy;    /* cursor, em celulas de texto                 */
static uint32_t  g_fg = OAK_FG;

/* Traduz um 0xRRGGBB para o layout de bits real deste framebuffer.
 * Quase sempre e 8/8/8 em posicoes 16/8/0, mas o protocolo nos da as
 * mascaras justamente pra nao termos que chutar. */
static uint32_t encode(uint32_t rgb) {
    uint32_t r = (rgb >> 16) & 0xff;
    uint32_t g = (rgb >> 8)  & 0xff;
    uint32_t b =  rgb        & 0xff;

    r >>= (8 - g_fb->red_mask_size);
    g >>= (8 - g_fb->green_mask_size);
    b >>= (8 - g_fb->blue_mask_size);

    return (r << g_fb->red_mask_shift)
         | (g << g_fb->green_mask_shift)
         | (b << g_fb->blue_mask_shift);
}

bool console_init(struct limine_framebuffer *fb) {
    /* So sabemos lidar com 32 bits por pixel. Outros formatos existem, mas
     * sao raros o bastante pra ficarem de fora por enquanto. */
    if (fb == NULL || fb->bpp != 32) {
        return false;
    }

    g_fb       = fb;
    g_pixels   = fb->address;
    /* pitch vem em BYTES por linha. Convertemos pra pixels. Ele costuma ser
     * maior que a largura visivel -- ha padding no fim de cada linha. */
    g_pitch_px = fb->pitch / 4;
    g_cols     = fb->width  / FONT_WIDTH;
    g_rows     = fb->height / FONT_HEIGHT;
    g_cx = g_cy = 0;

    console_clear();
    return true;
}

uint64_t console_cols(void) { return g_cols; }
uint64_t console_rows(void) { return g_rows; }

void console_set_color(uint32_t rgb) { g_fg = rgb; }
uint32_t console_get_color(void)     { return g_fg; }

void console_clear(void) {
    uint32_t bg = encode(OAK_BG);
    for (uint64_t y = 0; y < g_fb->height; y++) {
        for (uint64_t x = 0; x < g_fb->width; x++) {
            g_pixels[y * g_pitch_px + x] = bg;
        }
    }
    g_cx = g_cy = 0;
}

/* Sobe a tela inteira uma linha de texto e limpa a ultima. */
static void scroll(void) {
    uint64_t line_px = FONT_HEIGHT * g_pitch_px;
    uint64_t visible = g_rows * FONT_HEIGHT * g_pitch_px;

    memmove(g_pixels, g_pixels + line_px, (visible - line_px) * sizeof(uint32_t));

    uint32_t bg = encode(OAK_BG);
    for (uint64_t i = visible - line_px; i < visible; i++) {
        g_pixels[i] = bg;
    }
    g_cy = g_rows - 1;
}

static void newline(void) {
    g_cx = 0;
    if (++g_cy >= g_rows) {
        scroll();
    }
}

/* Desenha um glifo: cada byte da fonte e uma linha de 8 pixels, um bit por
 * pixel, do bit mais significativo (esquerda) pro menos (direita). */
static void draw_glyph(unsigned char ch, uint64_t cx, uint64_t cy) {
    uint32_t fg = encode(g_fg);
    uint32_t bg = encode(OAK_BG);
    uint64_t px = cx * FONT_WIDTH;
    uint64_t py = cy * FONT_HEIGHT;

    for (uint64_t row = 0; row < FONT_HEIGHT; row++) {
        uint8_t bits = font_bitmap[ch][row];
        for (uint64_t col = 0; col < FONT_WIDTH; col++) {
            bool on = bits & (0x80 >> col);
            g_pixels[(py + row) * g_pitch_px + px + col] = on ? fg : bg;
        }
    }
}

void console_putchar(char c) {
    if (g_fb == NULL) {
        return;
    }

    switch (c) {
    case '\n':
        newline();
        return;
    case '\r':
        g_cx = 0;
        return;
    case '\t':
        do {
            console_putchar(' ');
        } while (g_cx % 4 != 0);
        return;
    }

    if (g_cx >= g_cols) {
        newline();
    }
    draw_glyph((unsigned char)c, g_cx, g_cy);
    g_cx++;
}

void console_write(const char *s, size_t len) {
    for (size_t i = 0; i < len; i++) {
        console_putchar(s[i]);
    }
}
