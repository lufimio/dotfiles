#pragma once

#include "SourcePolicy.hpp"
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <functional>
#include <memory>
#include <string>
#include <utility>

namespace dynamic_share {

struct CaptureTarget {
    PHLWINDOW window;
    PHLMONITOR monitor; // non-null only for an explicitly selected whole output
    PHLWORKSPACE workspace;
};

class __attribute__((visibility("hidden"))) Selection {
  public:
    using Result = std::pair<bool, std::string>;
    explicit Selection(SourcePolicy&);
    ~Selection();
    void startObservers(std::function<bool(PHLWINDOW)> excluded);
    void clear();
    CaptureTarget current();
    Result focusedWindow();
    Result window(std::uint64_t id);
    Result focusedMonitor();
    Result monitor(std::uint64_t id);
    Result monitor(const std::string& name);
    Result focusedWorkspace();
    Result workspace(std::uint64_t id);
    std::string sourcesJson();
    std::uint64_t windowId();
    std::uint64_t monitorId();
    std::uint64_t workspaceId();
    std::string name();
    std::string instance() const;

  private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};
} // namespace dynamic_share
