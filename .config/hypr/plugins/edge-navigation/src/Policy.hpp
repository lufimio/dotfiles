#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace edge_navigation {
enum class Zone { NONE, LEFT, RIGHT, UP, DOWN, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT };
struct Corner { bool enabled = false; double size = 4; int delay = 300; bool duringDrag = false; };
struct Settings {
    bool enabled = true, dragEdges = true, smooth = true, externalDrags = true, windowDrags = true;
    double edgeSize = 16, speed = 900;
    int delay = 500, repeat = 700;
    std::array<Corner, 4> corners;
};
inline Zone hit(double x, double y, double w, double h, bool external, bool dragging, const Settings& s, bool windowMove = false) {
    if (!s.enabled || !std::isfinite(x) || !std::isfinite(y) || w <= 0 || h <= 0 || x < 0 || y < 0 || x >= w || y >= h)
        return Zone::NONE;
    for (int i = 0; i < 4; ++i) {
        const auto& c = s.corners[i];
        const double size = std::min({c.size, w / 2, h / 2});
        if (c.enabled && (!dragging || ((external || windowMove) && c.duringDrag)) &&
            ((i % 2 == 0) ? x < size : x >= w - size) &&
            ((i < 2) ? y < size : y >= h - size))
            return static_cast<Zone>(static_cast<int>(Zone::TOP_LEFT) + i);
    }
    if (!((external && s.externalDrags) || (windowMove && s.windowDrags)) || !s.dragEdges)
        return Zone::NONE;
    const double size = std::min({s.edgeSize, w / 2, h / 2});
    const std::array<double, 4> distances{x, w - x, y, h - y};
    auto index = std::min_element(distances.begin(), distances.end()) - distances.begin();
    return distances[index] <= size ? static_cast<Zone>(static_cast<int>(Zone::LEFT) + index) : Zone::NONE;
}
inline bool corner(Zone z) { return z >= Zone::TOP_LEFT; }
inline int delay(Zone z, const Settings& s) {
    return corner(z) ? s.corners[static_cast<int>(z) - static_cast<int>(Zone::TOP_LEFT)].delay : s.delay;
}
inline double scrollOffset(double current, bool next, double speed, double seconds, double maximum) {
    if (!std::isfinite(current) || !std::isfinite(speed) || !std::isfinite(seconds))
        return 0;
    return std::clamp(current + (next ? 1 : -1) * speed * std::clamp(seconds, 0.0, 0.05), 0.0, std::max(0.0, maximum));
}
// Monotonic milliseconds; zone/monitor changes must re-arm dwell. Corners fire
// once until exit, while directional steps repeat only after their own delay.
struct Dwell {
    Zone zone = Zone::NONE;
    uint64_t identity = 0;
    int64_t entered = 0, firedAt = 0;
    bool fired = false;
    void reset() { *this = {}; }
    bool ready(Zone next, uint64_t id, int64_t now, const Settings& s) {
        if (next != zone || id != identity) {
            zone = next; identity = id; entered = now; fired = false;
        }
        if (zone == Zone::NONE || (fired && corner(zone)))
            return false;
        if (now - (fired ? firedAt : entered) < (fired ? s.repeat : delay(zone, s)))
            return false;
        fired = true; firedAt = now;
        return true;
    }
};
}
