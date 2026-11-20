#pragma once
#include <cairo.h>
#include <string>

namespace dynamic_share {

class Placeholder {
  public:
    static bool valid(const std::string& text, int fontSize);
    bool configure(std::string text, int fontSize);
    // Transparent text texture. The native frame beneath it is always black.
    cairo_surface_t* rasterize() const;
    const std::string& text() const { return m_text; }
    int fontSize() const { return m_fontSize; }

  private:
    std::string m_text = "Nothing is being shared";
    int m_fontSize = 32;
};
} // namespace dynamic_share
