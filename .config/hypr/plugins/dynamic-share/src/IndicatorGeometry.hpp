#pragma once
#include <algorithm>
#include <cmath>
#include <optional>

namespace dynamic_share {
struct IndicatorInsets {
    double left = 0, top = 0, right = 0, bottom = 0; // logical shell reservations
};
struct IndicatorBox {
    double x, y, width, height; // transformed monitor-local pixels
};
inline std::optional<IndicatorBox> indicatorOutputBox(double width, double height, double scale, int borderWidth,
                                                       const IndicatorInsets& reserved = {}) {
    if (!std::isfinite(width) || !std::isfinite(height) || !std::isfinite(scale) ||
        !std::isfinite(reserved.left) || !std::isfinite(reserved.top) ||
        !std::isfinite(reserved.right) || !std::isfinite(reserved.bottom) ||
        width <= 0 || height <= 0 || scale <= 0 || borderWidth < 0 || borderWidth > 32)
        return {};
    const double inset = (borderWidth + 2) * scale;
    const double left = std::clamp(reserved.left * scale, 0.0, width);
    const double top = std::clamp(reserved.top * scale, 0.0, height);
    const double right = std::clamp(reserved.right * scale, 0.0, width);
    const double bottom = std::clamp(reserved.bottom * scale, 0.0, height);
    const IndicatorBox box{left + inset, top + inset, width - left - right - 2 * inset, height - top - bottom - 2 * inset};
    if (box.width <= 0 || box.height <= 0)
        return {};
    return box;
}
} // namespace dynamic_share
