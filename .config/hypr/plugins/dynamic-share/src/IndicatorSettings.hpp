#pragma once
#include "SourcePolicy.hpp"
#include <charconv>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string_view>

namespace dynamic_share {
struct IndicatorStyle {
    std::uint32_t borderColor = 0xf38ba8ff, glowColor = 0xf38ba8ff; // RRGGBBAA
    int borderWidth = 3, glowSize = 16, radius = 10;
    double glowOpacity = 0.25;
    bool operator==(const IndicatorStyle&) const = default;
    bool valid() const {
        return borderWidth >= 0 && borderWidth <= 32 && glowSize >= 0 && glowSize <= 128 &&
            radius >= 0 && radius <= 128 && std::isfinite(glowOpacity) && glowOpacity >= 0 && glowOpacity <= 1;
    }
};
struct IndicatorSettings {
    bool enabled = false;
    bool windows = true, workspaces = true, monitors = true;
    IndicatorStyle window, workspace, monitor;
    bool operator==(const IndicatorSettings&) const = default;
    bool valid() const { return window.valid() && workspace.valid() && monitor.valid(); }
    const IndicatorStyle& style(SourceKind kind) const {
        switch (kind) {
            case SourceKind::Workspace: return workspace;
            case SourceKind::Monitor: return monitor;
            default: return window;
        }
    }
};
inline std::optional<std::uint32_t> indicatorColor(std::string_view text) {
    if (!text.starts_with('#'))
        return {};
    text.remove_prefix(1);
    if (text.size() != 6 && text.size() != 8)
        return {};
    std::uint32_t color = 0;
    const auto result = std::from_chars(text.data(), text.data() + text.size(), color, 16);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size())
        return {};
    return text.size() == 6 ? (color << 8) | 0xff : color;
}
} // namespace dynamic_share
