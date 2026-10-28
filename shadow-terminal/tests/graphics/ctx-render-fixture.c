#define CTX_IMPLEMENTATION
#define CTX_RASTERIZER 1
#define CTX_PARSER 1
#define CTX_EVENTS 0
#define CTX_VT 0
#include "ctx.h"
#include <stdio.h>
int main(void) {
    unsigned char pixels[96 * 64 * 4] = {0};
    Ctx *ctx = ctx_new_for_framebuffer(pixels, 96, 64, 96 * 4, CTX_FORMAT_RGBA8);
    ctx_parse(ctx, "rgba 0 0 0 0 rectangle 0 0 96 64 fill save rectangle 4 4 80 48 clip translate 8 8 rgba 0.2 0.6 0.9 1 rectangle 0 0 30 20 fill moveTo 0 30 lineTo 50 30 lineWidth 2 stroke fontSize 12 moveTo 0 45 text 'ctx' restore");
    unsigned nonzero = 0;
    for (unsigned i = 0; i < sizeof(pixels); i++) nonzero += pixels[i] != 0;
    printf("pixels=%u alpha_inside=%u alpha_outside=%u\n", nonzero, pixels[(12*96+12)*4+3], pixels[(60*96+90)*4+3]);
    ctx_destroy(ctx);
    return !(nonzero && pixels[(12*96+12)*4+3] && !pixels[(60*96+90)*4+3]);
}
