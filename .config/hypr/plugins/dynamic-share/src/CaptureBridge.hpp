#pragma once

#include "SourcePolicy.hpp"
#include "Selection.hpp"
#include "IndicatorSettings.hpp"
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <functional>
#include <memory>
#include <string>
#include <utility>

namespace dynamic_share {

// Experimental native bridge, pinned to the same Hyprland ABI as Plugin.cpp.
// Only a trusted XDPH request for our owned helper window is dynamically routed.
class __attribute__((visibility("hidden"))) CaptureBridge {
  public:
    using Resolver = std::function<CaptureTarget()>;
    CaptureBridge(SourcePolicy& policy, Resolver refreshSource);
    ~CaptureBridge();
    CaptureBridge(const CaptureBridge&) = delete;
    CaptureBridge& operator=(const CaptureBridge&) = delete;

    std::pair<bool, std::string> start(void* pluginHandle);
    void stop();
    void observe(PHLWINDOW window);
    [[nodiscard]] bool isAnchor(PHLWINDOW window) const;
    [[nodiscard]] bool available() const;
    [[nodiscard]] bool hookInstalled() const;
    [[nodiscard]] bool active() const;
    [[nodiscard]] bool helperRunning() const;
    [[nodiscard]] std::string helperPath() const;
    void sourceSizing(bool enabled);
    [[nodiscard]] bool sourceSizing() const;
    bool placeholder(std::string text, int fontSize);
    [[nodiscard]] std::string placeholderText() const;
    [[nodiscard]] int placeholderFontSize() const;
    std::pair<bool, std::string> indicator(const IndicatorSettings&);
    IndicatorSettings indicatorSettings() const;

  private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace dynamic_share
