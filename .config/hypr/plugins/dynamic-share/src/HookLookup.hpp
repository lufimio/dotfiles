#pragma once

#include <stdexcept>
#include <string>
#include <string_view>

namespace dynamic_share {

struct HookTarget {
    // Hyprland searches raw mangled symbols, NOT demangled C++ method names.
    std::string_view query;
    std::string_view demangledPrefix;
};

inline constexpr HookTarget RENDER_HOOK{"CScreenshareFrame", "Screenshare::CScreenshareFrame::render("};
inline constexpr HookTarget SHARE_HOOK{"CScreenshareFrame", "Screenshare::CScreenshareFrame::share("};
inline constexpr HookTarget SIZE_HOOK{"CScreenshareSession", "Screenshare::CScreenshareSession::bufferSize("};
inline constexpr HookTarget END_HOOK{"CHyprOpenGLImpl", "Render::GL::CHyprOpenGLImpl::end("};
inline constexpr HookTarget SCANOUT_HOOK{"canAttemptDirectScanoutFast", "Monitor::CMonitor::canAttemptDirectScanoutFast("};

template <typename Lookup>
void* resolveHook(const HookTarget& target, Lookup lookup) {
    void* address = nullptr;
    for (const auto& match : lookup(std::string{target.query})) {
        if (!match.demangled.starts_with(target.demangledPrefix))
            continue;
        if (address && address != match.address)
            throw std::runtime_error("ambiguous capture hook: " + std::string{target.demangledPrefix});
        address = match.address;
    }
    if (!address)
        throw std::runtime_error("capture hook not found: " + std::string{target.demangledPrefix});
    return address;
}

} // namespace dynamic_share
