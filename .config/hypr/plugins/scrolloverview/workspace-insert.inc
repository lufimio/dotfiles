// Included by scrollOverview.cpp: uses the same card geometry and drag owner.
#include <hyprland/src/config/lua/ConfigManager.hpp>
#include <hyprland/src/config/lua/LuaEventHandler.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>

namespace {
constexpr const char* INSERT_WORKSPACE_EVENT = "scrolloverview.insert-workspace";
SP<Event::CEventBus::CCustomEvent> workspaceInsertEvent;
}

void registerWorkspaceInsertEvent() {
    using EventType = Event::CEventBus::CCustomEvent;
    workspaceInsertEvent = makeShared<EventType>(
        INSERT_WORKSPACE_EVENT,
        std::vector<EventType::eType>{EventType::TYPE_WINDOW, EventType::TYPE_WORKSPACE});
    const auto registered = Event::bus()->addPluginEvent(workspaceInsertEvent);
    if (!registered)
        throw std::runtime_error("scrolloverview: " + registered.error());
}

void unregisterWorkspaceInsertEvent() {
    if (workspaceInsertEvent)
        (void)Event::bus()->removePluginEvent(INSERT_WORKSPACE_EVENT);
    workspaceInsertEvent.reset();
}

std::optional<std::pair<PHLWORKSPACE, CBox>>
CScrollOverview::workspaceInsertionTarget(const Vector2D& point) const {
    const auto monitor = pMonitor.lock();
    if (!monitor || closing ||
        !ScrollOverview::Config::getValue<bool>("plugin:scrolloverview:insert_workspaces", monitor))
        return std::nullopt;
    const auto active = activeWorkspaceIndex();
    const auto pitch = getWorkspaceRenderedPitch(monitor, scale->value(), layout);
    for (size_t i = 1; i < images.size(); ++i) {
        const auto before = images[i - 1] ? images[i - 1]->pWorkspace : PHLWORKSPACE{};
        const auto after = images[i] ? images[i]->pWorkspace : PHLWORKSPACE{};
        // Numbered, same-monitor insertion only; never renumber named/special cards.
        if (!before || !after || !before->numberedID() || !after->numberedID() ||
            before->m_monitor != monitor || after->m_monitor != monitor)
            continue;
        const auto a = getOverviewWorkspaceBox(monitor, scale->value(), viewOffset->value(),
                                              workspaceOverviewOffset(i - 1, active, pitch), layout);
        const auto b = getOverviewWorkspaceBox(monitor, scale->value(), viewOffset->value(),
                                              workspaceOverviewOffset(i, active, pitch), layout);
        CBox gap;
        if (layout == ScrollOverview::Config::ELayout::VERTICAL) {
            gap = CBox{std::max(a.x, b.x), a.y + a.height,
                       std::min(a.x + a.width, b.x + b.width) - std::max(a.x, b.x),
                       b.y - a.y - a.height};
        } else {
            gap = CBox{a.x + a.width, std::max(a.y, b.y), b.x - a.x - a.width,
                       std::min(a.y + a.height, b.y + b.height) - std::max(a.y, b.y)};
        }
        if (gap.width > 0 && gap.height > 0 && gap.containsPoint(point))
            return std::pair{after, gap};
    }
    return std::nullopt;
}

void CScrollOverview::renderWorkspaceInsertionTarget() {
    // Show the insertion marker only for our own window drag, not file DnD,
    // column panning, or resize gestures.
    if (!dragActiveWindow || !pMonitor ||
        !pMonitor->logicalBox().containsPoint(g_pInputManager->getMouseCoordsInternal()))
        return;
    const auto target = workspaceInsertionTarget(getOverviewMousePosLocal(pMonitor.lock()));
    if (!target)
        return;
    auto box = target->second;
    const auto thickness = 6.0 * pMonitor->m_scale;
    if (layout == ScrollOverview::Config::ELayout::VERTICAL) {
        box.y += (box.height - std::min(box.height, thickness)) / 2;
        box.height = std::min(box.height, thickness);
    } else {
        box.x += (box.width - std::min(box.width, thickness)) / 2;
        box.width = std::min(box.width, thickness);
    }
    auto* border = sc<Config::CGradientValueData*>(
        ScrollOverview::Config::valueRef<Config::IComplexConfigValue>("general:col.active_border").ptr());
    CRectPassElement::SRectData data;
    data.box = box;
    data.color = (border && !border->m_colors.empty() ? border->m_colors.front() : Colors::WHITE).modifyA(0.85F);
    data.round = 3;
    Render::IHyprRenderer::currentPass(g_pHyprRenderer->context()).add(makeUnique<CRectPassElement>(data));
}

bool CScrollOverview::tryInsertWorkspaceDrop() {
    const auto window = getOverviewWindowToShow(dragActiveWindow.lock());
    const auto monitor = pMonitor.lock();
    if (!window || !window->m_workspace || !window->m_workspace->numberedID() ||
        !monitor || window->m_workspace->m_monitor != monitor ||
        !monitor->logicalBox().containsPoint(g_pInputManager->getMouseCoordsInternal()))
        return false;
    const auto target = workspaceInsertionTarget(getOverviewMousePosLocal(monitor));
    if (!target || !workspaceInsertEvent)
        return false;
    const auto manager = Config::Lua::mgr();
    if (!manager || !manager->m_eventHandler)
        return false;
    // Reconnect after config reload (Hyprland 0.57 loses existing custom-event
    // bridges). Do this before releasing the drag, so failure preserves it.
    (void)manager->m_eventHandler->removeCustomEvent(INSERT_WORKSPACE_EVENT);
    if (!manager->m_eventHandler->addCustomEvent(workspaceInsertEvent))
        return false;
    const auto originalWorkspace = window->m_workspace;
    const auto floatSize = dragOriginalFloatSize;
    // The Lua transaction may now safely renumber IDs; positional ownership is
    // fully released before any workspace is created or any window is moved.
    finishWindowDragSession();
    const auto emitted = workspaceInsertEvent->emit({PHLWINDOWREF{window}, PHLWORKSPACEREF{target->first}});
    if (!emitted)
        LOG(Log::ERR, "scrolloverview: insertion event failed: {}", emitted.error());
    if (window->m_workspace != originalWorkspace) {
        if (const auto layoutTarget = window->layoutTarget())
            layoutTarget->rememberFloatingSize(floatSize);
        closeOnWindow = window;
        redrawAll();
        for (size_t i = 0; i < images.size(); ++i) {
            if (images[i]->pWorkspace == window->m_workspace) {
                selectOverviewWindow(window, i, true);
                break;
            }
        }
    }
    damage();
    return true;
}
