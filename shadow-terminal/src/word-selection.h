#pragma once
#include <gtk/gtk.h>
#include <vte/vte.h>
typedef struct _ShadowWord ShadowWord;
ShadowWord *shadow_word_at(VteTerminal *terminal, double x, double y);
const char *shadow_word_text(ShadowWord *word);
void shadow_word_draw(ShadowWord *word, cairo_t *cr);
void shadow_word_free(ShadowWord *word);
gboolean shadow_event_coordinates(const VteEventContext *context, double *x, double *y);
