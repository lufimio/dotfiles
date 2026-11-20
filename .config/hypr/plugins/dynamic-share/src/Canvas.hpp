#pragma once

#include <algorithm>
#include <cmath>
#include <optional>

namespace dynamic_share {

struct CanvasFit {
    float scale;
    double x, y;
};

inline std::optional<CanvasFit> fitCanvas(double width, double height, double sourceWidth, double sourceHeight) {
    if (!std::isfinite(width) || !std::isfinite(height) || !std::isfinite(sourceWidth) || !std::isfinite(sourceHeight) ||
        width <= 0 || height <= 0 || sourceWidth <= 0 || sourceHeight <= 0)
        return {};
    const auto scale = std::min(width / sourceWidth, height / sourceHeight);
    return CanvasFit{static_cast<float>(scale), (width - sourceWidth * scale) / 2, (height - sourceHeight * scale) / 2};
}

} // namespace dynamic_share
