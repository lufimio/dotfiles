#include "Placeholder.hpp"
#include <pango/pangocairo.h>
#include <utility>
#include <algorithm>

namespace dynamic_share {
bool Placeholder::valid(const std::string& text, int fontSize) {
    return text.size() <= 4096 && !text.contains('\0') && fontSize >= 8 && fontSize <= 128 &&
        g_utf8_validate(text.c_str(), static_cast<gssize>(text.size()), nullptr);
}
bool Placeholder::configure(std::string text, int fontSize) {
    if (!valid(text, fontSize))
        return false;
    m_text = std::move(text);
    m_fontSize = fontSize;
    return true;
}
cairo_surface_t* Placeholder::rasterize() const {
    auto* measuring = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
    auto* cr = cairo_create(measuring);
    auto* layout = pango_cairo_create_layout(cr);
    auto* font = pango_font_description_from_string("Sans");
    pango_font_description_set_absolute_size(font, m_fontSize * PANGO_SCALE);
    pango_layout_set_font_description(layout, font);
    pango_font_description_free(font);
    pango_layout_set_text(layout, m_text.c_str(), static_cast<int>(m_text.size())); // plain text, not markup
    pango_layout_set_width(layout, 960 * PANGO_SCALE);
    pango_layout_set_height(layout, 512 * PANGO_SCALE);
    pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
    PangoRectangle ink{}, logical{};
    pango_layout_get_pixel_extents(layout, &ink, &logical);
    const int width = std::max(1, logical.width + 16);
    const int height = std::max(1, logical.height + 16);
    cairo_destroy(cr);
    cairo_surface_destroy(measuring);
    auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    cr = cairo_create(surface);
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_set_source_rgba(cr, 0.92, 0.92, 0.92, 1.0);
    cairo_move_to(cr, 8 - logical.x, 8 - logical.y);
    pango_cairo_show_layout(cr, layout);
    g_object_unref(layout);
    cairo_destroy(cr);
    cairo_surface_flush(surface);
    return surface;
}
} // namespace dynamic_share
