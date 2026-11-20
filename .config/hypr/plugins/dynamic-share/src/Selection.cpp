#include "Selection.hpp"

#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <nlohmann/json.hpp>
#include <limits>
#include <map>
#include <chrono>
#include <unistd.h>

namespace dynamic_share {
namespace {
bool privateWindow(PHLWINDOW window) {
    return !window->m_ruleApplicator || window->m_ruleApplicator->noScreenShare().valueOrDefault();
}
}

struct Selection::Impl {
    SourcePolicy& policy;
    const std::string instance = std::to_string(getpid()) + "-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    PHLWINDOWREF selectedWindow;
    PHLMONITORREF selectedMonitor;
    PHLWORKSPACEREF selectedWorkspace;
    std::function<bool(PHLWINDOW)> excluded;
    std::map<std::uint64_t, PHLWINDOWREF> windows;
    std::map<std::uint64_t, PHLMONITORREF> monitors;
    std::map<std::uint64_t, PHLWORKSPACEREF> workspaces;
    std::uint64_t nextWindow = 0, nextMonitor = 0, nextWorkspace = 0, nextSource = 0;
    CHyprSignalListener sourceUnmapped, sourceDestroyed, sourceHidden, monitorGone;
    CHyprSignalListener rulesChanged, layerRulesChanged, locked, unlocked;

    explicit Impl(SourcePolicy& p) : policy(p) {}
    ~Impl() {
        rulesChanged.reset();
        layerRulesChanged.reset();
        locked.reset();
        unlocked.reset();
        clear();
    }
    void clear() {
        sourceUnmapped.reset();
        sourceDestroyed.reset();
        sourceHidden.reset();
        monitorGone.reset();
        invalidate();
    }
    // Safe to call from a source's own event: do not destroy that listener here.
    void invalidate() {
        selectedWindow.reset();
        selectedMonitor.reset();
        selectedWorkspace.reset();
        policy.clearSource();
    }
    CaptureTarget current() {
        policy.setLocked(!g_pSessionLockManager || g_pSessionLockManager->isSessionLocked());
        if (!policy.source())
            return {};
        if (policy.source()->kind == SourceKind::Workspace) {
            const auto workspace = selectedWorkspace.lock();
            const auto output = workspace ? workspace->m_monitor.lock() : nullptr;
            if (!workspace || !output || !output->m_enabled) {
                invalidate();
                return {};
            }
            return {{}, {}, workspace};
        }
        if (policy.source()->kind == SourceKind::Monitor) {
            const auto output = selectedMonitor.lock();
            if (!output || !output->m_enabled || !State::monitorState()->contains(output)) {
                invalidate();
                return {};
            }
            return {{}, output, {}};
        }
        const auto window = selectedWindow.lock();
        if (!window || !window->mapped() || window->isHidden()) {
            invalidate();
            return {};
        }
        policy.setPrivate(policy.source()->id, privateWindow(window));
        return {window, {}, {}};
    }
    bool ready() {
        current();
        return g_pSessionLockManager && !policy.locked();
    }
    void catalog() {
        std::erase_if(windows, [](const auto& entry) {
            return entry.second.expired() || !entry.second->mapped();
        });
        std::erase_if(monitors, [](const auto& entry) {
            return entry.second.expired() || !entry.second->m_enabled;
        });
        const auto liveWorkspaces = State::Workspace::state()->workspacesCopy();
        std::erase_if(workspaces, [&](const auto& entry) {
            const auto workspace = entry.second.lock();
            return !workspace || std::ranges::find(liveWorkspaces, workspace) == liveWorkspaces.end();
        });
        for (const auto& w : Desktop::windowState()->windows()) {
            if (!w->mapped() || (excluded && excluded(w)))
                continue;
            bool known = false;
            for (const auto& [_, weak] : windows)
                known |= weak.lock() == w;
            if (!known && nextWindow < std::numeric_limits<std::int64_t>::max())
                windows.emplace(++nextWindow, w);
        }
        for (const auto& output : State::monitorState()->monitors()) {
            if (!output->m_enabled)
                continue;
            bool known = false;
            for (const auto& [_, weak] : monitors)
                known |= weak.lock() == output;
            if (!known && nextMonitor < std::numeric_limits<std::int64_t>::max())
                monitors.emplace(++nextMonitor, output);
        }
        for (const auto& workspace : liveWorkspaces) {
            // The helper workspace is an implementation detail, not a target.
            if (workspace->displayName() == "dynamic-share-anchor")
                continue;
            bool known = false;
            for (const auto& [_, weak] : workspaces)
                known |= weak.lock() == workspace;
            if (!known && nextWorkspace < std::numeric_limits<std::int64_t>::max())
                workspaces.emplace(++nextWorkspace, workspace);
        }
    }
    Result selectWindow(PHLWINDOW window) {
        if (!ready())
            return {false, "session locked or lock manager unavailable"};
        if (!window || !window->mapped() || window->isHidden() || (excluded && excluded(window)))
            return {false, "no shareable window with that identity"};
        if (nextSource == std::numeric_limits<SourceId>::max())
            return {false, "source identity counter exhausted"};
        clear();
        const auto cookie = ++nextSource;
        selectedWindow = window;
        policy.select({cookie, privateWindow(window), SourceKind::Window});
        const auto invalidateSelected = [this, cookie] {
            if (policy.source() && policy.source()->id == cookie)
                invalidate();
        };
        sourceUnmapped = window->m_events.unmap.listen(invalidateSelected);
        sourceDestroyed = window->m_events.destroy.listen(invalidateSelected);
        sourceHidden = window->m_events.hide.listen([this] { current(); });
        if (policy.source()->privateContent)
            return {false, "selected window is private; Dynamic Share will be empty"};
        return {true, "Dynamic Share window target selected"};
    }
    Result selectMonitor(PHLMONITOR output) {
        if (!ready())
            return {false, "session locked or lock manager unavailable"};
        if (!output || !output->m_enabled || !State::monitorState()->contains(output))
            return {false, "no enabled monitor with that identity"};
        if (nextSource == std::numeric_limits<SourceId>::max())
            return {false, "source identity counter exhausted"};
        clear();
        selectedMonitor = output;
        const auto cookie = ++nextSource;
        policy.select({cookie, false, SourceKind::Monitor});
        monitorGone = output->m_events.disconnect.listen([this, cookie] {
            if (policy.source() && policy.source()->id == cookie)
                invalidate();
        });
        return {true, "Dynamic Share monitor target selected (whole output, subject to capture privacy)"};
    }
    Result selectWorkspace(PHLWORKSPACE workspace) {
        if (!ready())
            return {false, "session locked or lock manager unavailable"};
        const auto output = workspace ? workspace->m_monitor.lock() : nullptr;
        if (!workspace || !output || !output->m_enabled || workspace->displayName() == "dynamic-share-anchor")
            return {false, "no shareable workspace with that identity"};
        if (nextSource == std::numeric_limits<SourceId>::max())
            return {false, "source identity counter exhausted"};
        clear();
        selectedWorkspace = workspace;
        const auto cookie = ++nextSource;
        policy.select({cookie, false, SourceKind::Workspace});
        sourceDestroyed = workspace->m_events.destroy.listen([this, cookie] {
            if (policy.source() && policy.source()->id == cookie)
                invalidate();
        });
        return {true, "Dynamic Share workspace selected (windows only, without desktop shell)"};
    }
};

Selection::Selection(SourcePolicy& p) : m_impl(std::make_unique<Impl>(p)) {}
Selection::~Selection() = default;
void Selection::startObservers(std::function<bool(PHLWINDOW)> excluded) {
    auto& s = *m_impl;
    s.excluded = std::move(excluded);
    s.rulesChanged = Event::bus()->m_events.window.updateRules.listen([&s](PHLWINDOW window) {
        if (s.policy.source() && s.policy.source()->kind != SourceKind::Window)
            s.policy.invalidateFrames(); // a privacy mask may change while a frame is in flight
        else if (window == s.selectedWindow.lock())
            s.current();
    });
    s.layerRulesChanged = Event::bus()->m_events.layer.updateRules.listen([&s](PHLLS) {
        if (s.policy.source() && s.policy.source()->kind != SourceKind::Window)
            s.policy.invalidateFrames();
    });
    if (g_pSessionLockManager) {
        s.locked = g_pSessionLockManager->m_events.lock.listen([&s] { s.policy.setLocked(true); });
        s.unlocked = g_pSessionLockManager->m_events.unlock.listen([&s] { s.current(); });
    }
    s.current();
}
void Selection::clear() { m_impl->clear(); }
CaptureTarget Selection::current() { return m_impl->current(); }
Selection::Result Selection::focusedWindow() { return m_impl->selectWindow(Desktop::focusState()->window()); }
Selection::Result Selection::window(std::uint64_t id) {
    m_impl->catalog();
    const auto it = m_impl->windows.find(id);
    return m_impl->selectWindow(it == m_impl->windows.end() ? nullptr : it->second.lock());
}
Selection::Result Selection::focusedMonitor() { return m_impl->selectMonitor(Desktop::focusState()->monitor()); }
Selection::Result Selection::monitor(std::uint64_t id) {
    m_impl->catalog();
    const auto it = m_impl->monitors.find(id);
    return m_impl->selectMonitor(it == m_impl->monitors.end() ? nullptr : it->second.lock());
}
Selection::Result Selection::monitor(const std::string& name) {
    for (const auto& output : State::monitorState()->monitors())
        if (output->m_name == name)
            return m_impl->selectMonitor(output);
    return {false, "monitor connector name is not present"};
}
Selection::Result Selection::focusedWorkspace() {
    const auto output = Desktop::focusState()->monitor();
    return m_impl->selectWorkspace(output ? (output->m_activeSpecialWorkspace ? output->m_activeSpecialWorkspace : output->m_activeWorkspace) : nullptr);
}
Selection::Result Selection::workspace(std::uint64_t id) {
    m_impl->catalog();
    const auto it = m_impl->workspaces.find(id);
    return m_impl->selectWorkspace(it == m_impl->workspaces.end() ? nullptr : it->second.lock());
}
std::uint64_t Selection::windowId() {
    m_impl->catalog();
    for (const auto& [id, weak] : m_impl->windows)
        if (weak.lock() == m_impl->selectedWindow.lock())
            return id;
    return 0;
}
std::uint64_t Selection::monitorId() {
    m_impl->catalog();
    for (const auto& [id, weak] : m_impl->monitors)
        if (weak.lock() == m_impl->selectedMonitor.lock())
            return id;
    return 0;
}
std::uint64_t Selection::workspaceId() {
    m_impl->catalog();
    for (const auto& [id, weak] : m_impl->workspaces)
        if (weak.lock() == m_impl->selectedWorkspace.lock())
            return id;
    return 0;
}
std::string Selection::name() {
    const auto target = current();
    return target.window ? target.window->metadata().title() :
        (target.monitor ? target.monitor->m_name : (target.workspace ? target.workspace->displayName() : ""));
}
std::string Selection::instance() const { return m_impl->instance; }
std::string Selection::sourcesJson() {
    m_impl->catalog();
    nlohmann::json result = {{"instance", m_impl->instance}, {"windows", nlohmann::json::array()}, {"monitors", nlohmann::json::array()},
                             {"workspaces", nlohmann::json::array()}};
    for (const auto& [id, weak] : m_impl->windows) {
        const auto window = weak.lock();
        if (!window || window->isHidden() || (m_impl->excluded && m_impl->excluded(window)))
            continue;
        result["windows"].push_back({{"id", id}, {"title", window->metadata().title()},
                                    {"app_id", window->metadata().appID()}, {"private", privateWindow(window)},
                                    {"selected", window == m_impl->selectedWindow.lock()}});
    }
    for (const auto& [id, weak] : m_impl->monitors) {
        const auto output = weak.lock();
        if (!output)
            continue;
        result["monitors"].push_back({{"id", id}, {"name", output->m_name},
                                     {"width", output->m_transformedSize.x}, {"height", output->m_transformedSize.y},
                                     {"selected", output == m_impl->selectedMonitor.lock()}});
    }
    for (const auto& [id, weak] : m_impl->workspaces) {
        const auto workspace = weak.lock();
        if (workspace)
            result["workspaces"].push_back({{"id", id}, {"name", workspace->displayName()},
                                           {"selected", workspace == m_impl->selectedWorkspace.lock()}});
    }
    return result.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
}
} // namespace dynamic_share
