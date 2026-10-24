#include "word-selection.h"
#include <string.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

struct _ShadowWord {
    char *text;
    GArray *rectangles;
};

/* VTE owns matching and terminal-cell hit testing. Highlighting the matched
 * cells adds presentation only; it does not reconstruct terminal contents. */
static char *match_at(VteTerminal *terminal, VteRegex *regex, double x, double y) {
    char *match = NULL;
    vte_terminal_check_regex_simple_at(terminal, x, y, &regex, 1, 0, &match);
    return match;
}

ShadowWord *shadow_word_at(VteTerminal *terminal, double x, double y) {
    const char *exceptions = vte_terminal_get_word_char_exceptions(terminal);
    if (!exceptions) exceptions = "-#%&+,./=?@\\_~:";
    GString *pattern = g_string_new("(?m)[\\p{L}\\p{N}\\p{M}");
    for (const char *p = exceptions; *p; p = g_utf8_next_char(p))
        g_string_append_printf(pattern, "\\x{%x}", g_utf8_get_char(p));
    g_string_append(pattern, "]+|[^\\s]");
    GError *error = NULL;
    VteRegex *regex = vte_regex_new_for_match(pattern->str, -1, VTE_REGEX_FLAGS_DEFAULT | PCRE2_MULTILINE, &error);
    g_string_free(pattern, TRUE);
    if (!regex) { g_clear_error(&error); return NULL; }
    char *text = match_at(terminal, regex, x, y);
    if (!text || strlen(text) > 65536) { g_free(text); vte_regex_unref(regex); return NULL; }
    GtkBorder padding;
    gtk_style_context_get_padding(gtk_widget_get_style_context(GTK_WIDGET(terminal)), &padding);
    int width = vte_terminal_get_char_width(terminal), height = vte_terminal_get_char_height(terminal);
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
        g_free(text); vte_regex_unref(regex); return NULL;
    }
    int col = x / width, row = y / height;
    int columns = vte_terminal_get_column_count(terminal), rows = vte_terminal_get_row_count(terminal);
    if (col >= columns || row >= rows) { g_free(text); vte_regex_unref(regex); return NULL; }
    int first = col, last = col;
    for (int direction = -1; direction <= 1; direction += 2) {
        int edge = col;
        for (int i = col + direction; i >= 0 && i < columns && ABS(i - col) < 4096; i += direction) {
            char *candidate = match_at(terminal, regex, (i + 0.5) * width, (row + 0.5) * height);
            gboolean same = g_strcmp0(candidate, text) == 0;
            g_free(candidate);
            if (!same) break;
            edge = i;
        }
        if (direction < 0) first = edge; else last = edge;
    }
    ShadowWord *word = g_new0(ShadowWord, 1);
    word->text = text;
    word->rectangles = g_array_new(FALSE, FALSE, sizeof(graphene_rect_t));
    graphene_rect_t rect = GRAPHENE_RECT_INIT(padding.left + first * width, padding.top + row * height,
                                             (last - first + 1) * width, height);
    g_array_append_val(word->rectangles, rect);
    vte_regex_unref(regex);
    return word;
}

const char *shadow_word_text(ShadowWord *word) { return word->text; }

void shadow_word_draw(ShadowWord *word, cairo_t *cr) {
    cairo_set_source_rgba(cr, 0.35, 0.55, 1.0, 0.35);
    for (guint i = 0; i < word->rectangles->len; i++) {
        graphene_rect_t rect = g_array_index(word->rectangles, graphene_rect_t, i);
        cairo_rectangle(cr, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    }
    cairo_fill(cr);
}

void shadow_word_free(ShadowWord *word) {
    if (!word) return;
    g_free(word->text);
    g_array_unref(word->rectangles);
    g_free(word);
}

gboolean shadow_event_coordinates(const VteEventContext *context, double *x, double *y) {
    return vte_event_context_get_coordinates(context, x, y);
}
