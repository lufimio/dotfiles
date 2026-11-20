#include "Policy.hpp"
#include <chrono>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/lua/ConfigManager.hpp>
#include <hyprland/src/config/lua/LuaEventHandler.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/protocols/core/DataDevice.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/workspace/query/Query.hpp>
#include <limits>
#include <set>
#include <stdexcept>
#include <wayland-server-core.h>
extern "C" {
#include <lua.h>
}

static_assert(std::string_view{GIT_COMMIT_HASH} ==
              "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947");
namespace {
using namespace edge_navigation;
HANDLE handle = nullptr;
Settings settings;
std::set<std::string> monitors;
Dwell dwell;
wl_event_source *timer = nullptr;
bool armed = false, unloading = false, panning = false, eventOwned = false;
int64_t lastTick = 0;
WP<Layout::Tiled::SScrollingData> camera;
std::optional<double> previousCameraLock;
SP<Event::CEventBus::CCustomEvent> actionEvent;
CHyprSignalListener mouseMove, mouseButton, preReload;
constexpr const char *EVENT_NAME = "edge-navigation.action";
const std::array<const char *, 4> cornerNames{"top_left", "top_right",
                                              "bottom_left", "bottom_right"};

int64_t nowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
bool overview() {
  const auto &state = Config::Actions::state();
  return state && (state->m_currentSubmap == "scrolloverview" ||
                   state->m_currentSubmap == "hyprexpo");
}
bool externalDrag() { return PROTO::data && PROTO::data->dndActive(); }
bool windowDrag() {
  const auto &drag = g_layoutManager->dragController();
  return drag->target() && drag->mode() == MBIND_MOVE &&
         drag->dragThresholdReached();
}
bool eligibleDrag() {
  return (settings.externalDrags && externalDrag()) ||
         (settings.windowDrags && windowDrag());
}
bool locked() {
  return !g_pSessionLockManager || g_pSessionLockManager->isSessionLocked();
}
void finishPan() {
  if (auto data = camera.lock()) {
    data->lockedCameraOffset = previousCameraLock;
    data->recalculate();
  }
  camera.reset();
  previousCameraLock.reset();
  panning = false;
}
void stop() {
  finishPan();
  dwell.reset();
  lastTick = 0;
  if (timer && armed)
    wl_event_source_timer_update(timer, 0);
  armed = false;
}
void wake() {
  // Do not postpone an already armed timer on high-frequency pointer motion.
  if (!unloading && timer && !armed) {
    armed = true;
    wl_event_source_timer_update(timer, 16);
  }
}
Layout::Tiled::CScrollingAlgorithm *algorithm(PHLWORKSPACE workspace) {
  if (!workspace || !workspace->space() || !workspace->space()->algorithm())
    return nullptr;
  return dynamic_cast<Layout::Tiled::CScrollingAlgorithm *>(
      workspace->space()->algorithm()->tiledAlgo().get());
}
void emit(const std::string &action, PHLMONITOR monitor) {
  if (actionEvent)
    (void)actionEvent->emit({action, monitor->m_name});
}
bool scroll(PHLMONITOR monitor, Zone zone, double dt) {
  const auto workspace = monitor->m_activeSpecialWorkspace
                             ? monitor->m_activeSpecialWorkspace
                             : monitor->m_activeWorkspace;
  auto *algo = algorithm(workspace);
  if (!algo)
    return false;
  auto col = algo->currentColumn();
  if (!col)
    col = algo->getColumnAtViewportCenter();
  auto data = col ? col->scrollingData.lock() : nullptr;
  if (!data || !data->controller || !data->controller->isPrimaryHorizontal())
    return false;
  if (!settings.smooth) {
    auto next = zone == Zone::RIGHT ? data->next(col) : data->prev(col);
    if (next) {
      algo->focusColumn(next); // Unlike layoutmsg "focus", never warps pointer.
      data->centerOrFitCol(next);
      data->recalculate();
      g_pInputManager->refocusPointer();
    }
    return true;
  }
  if (camera.lock() != data) {
    finishPan();
    if (data->lockedCameraOffset)
      return true; // Another gesture/owner has this camera.
    camera = data;
    previousCameraLock = data->lockedCameraOffset;
  }
  const double offset = scrollOffset(
      data->controller->getOffset(), zone == Zone::RIGHT, settings.speed, dt,
      data->maxWidth() - algo->primaryViewportSize());
  data->lockedCameraOffset = offset;
  data->controller->setOffset(offset);
  data->recalculate(true);
  auto center = algo->getColumnAtViewportCenter();
  if (center && center != algo->currentColumn()) {
    algo->focusColumn(center);
    // Focus callbacks must not override continuous edge tracking.
    data->controller->setOffset(offset);
    data->recalculate(true);
  }
  g_pInputManager->refocusPointer(); // Refresh the DnD drop surface under a
                                     // stationary cursor.
  return true;
}
bool focusWithin(PHLMONITOR monitor, Zone zone) {
  const auto workspace = monitor->m_activeSpecialWorkspace
                             ? monitor->m_activeSpecialWorkspace
                             : monitor->m_activeWorkspace;
  if (!workspace || !workspace->space())
    return false;
  const auto current = Desktop::focusState()->window();
  const auto origin =
      current && current->m_workspace == workspace && current->layoutTarget()
          ? current->layoutTarget()->position().middle()
          : monitor->logicalBox().middle();
  PHLWINDOW best;
  double bestScore = std::numeric_limits<double>::max();
  for (const auto &ref : workspace->space()->targets()) {
    auto target = ref.lock();
    auto window = target ? target->window() : PHLWINDOW{};
    if (!Desktop::View::validMapped(window) || window == current ||
        window->isHidden() ||
        target == g_layoutManager->dragController()->target())
      continue;
    const auto delta = target->position().middle() - origin;
    if ((zone == Zone::LEFT && delta.x >= 0) ||
        (zone == Zone::RIGHT && delta.x <= 0) ||
        (zone == Zone::UP && delta.y >= 0) ||
        (zone == Zone::DOWN && delta.y <= 0))
      continue;
    const bool horizontal = zone == Zone::LEFT || zone == Zone::RIGHT;
    const double score = horizontal ? delta.x * delta.x + 4 * delta.y * delta.y
                                    : delta.y * delta.y + 4 * delta.x * delta.x;
    if (score < bestScore) {
      best = window;
      bestScore = score;
    }
  }
  if (best) {
    Desktop::focusState()->fullWindowFocus(
        best, Desktop::FOCUS_REASON_DESKTOP_STATE_CHANGE);
    g_pInputManager->refocusPointer();
  }
  return !!best;
}
void vertical(PHLMONITOR monitor, Zone zone) {
  const auto workspace = monitor->m_activeSpecialWorkspace
                             ? monitor->m_activeSpecialWorkspace
                             : monitor->m_activeWorkspace;
  const auto window = Desktop::focusState()->window();
  auto *algo = algorithm(workspace);
  if ((!algo || (window && window->isFloating())) && focusWithin(monitor, zone))
    return;
  if (algo && window && window->m_workspace == workspace &&
      !window->isFloating()) {
    auto data = algo->dataFor(window->layoutTarget());
    auto col = data ? data->column.lock() : nullptr;
    if (col) {
      auto next = zone == Zone::DOWN ? col->next(data) : col->prev(data);
      if (next && next->target &&
          Desktop::View::validMapped(next->target->window())) {
        Desktop::focusState()->fullWindowFocus(
            next->target->window(), Desktop::FOCUS_REASON_DESKTOP_STATE_CHANGE);
        g_pInputManager->refocusPointer();
        return;
      }
    }
  }
  // Lua keeps the existing monitor-local numbered workspace dictionary.
  emit(zone == Zone::DOWN ? "workspace_down" : "workspace_up", monitor);
}
void tick() {
  if (unloading || !settings.enabled || locked()) {
    stop();
    return;
  }
  const bool external = externalDrag();
  const bool moving = windowDrag();
  const bool dragging =
      external || !!g_layoutManager->dragController()->target();
  auto monitor = State::monitorState()
                     ->query()
                     .vec(g_pInputManager->getMouseCoordsInternal())
                     .run();
  if (!monitor || (!monitors.empty() && !monitors.contains(monitor->m_name))) {
    stop();
    return;
  }
  const auto point =
      g_pInputManager->getMouseCoordsInternal() - monitor->m_position;
  Zone zone = hit(point.x, point.y, monitor->m_size.x, monitor->m_size.y,
                  external, dragging, settings, moving);
  if (overview() && !corner(zone))
    zone = Zone::NONE; // Overview retains exclusive drag-edge ownership.
  const auto now = nowMs();
  const double dt =
      lastTick ? std::clamp((now - lastTick) / 1000.0, 0.0, 0.05) : 0.016;
  lastTick = now;
  const bool changed = zone != dwell.zone ||
                       dwell.identity != static_cast<uint64_t>(monitor->m_id);
  if (changed)
    finishPan();
  const bool ready = dwell.ready(zone, monitor->m_id, now, settings);
  const bool horizontal = zone == Zone::LEFT || zone == Zone::RIGHT;
  if (ready || (panning && horizontal && eligibleDrag())) {
    if (corner(zone)) {
      emit(cornerNames[static_cast<int>(zone) -
                       static_cast<int>(Zone::TOP_LEFT)],
           monitor);
    } else {
      Desktop::focusState()->rawMonitorFocus(monitor); // No cursor warp.
      if (horizontal) {
        if (!scroll(monitor, zone, dt))
          focusWithin(monitor, zone);
        else
          panning = settings.smooth;
      } else {
        finishPan();
        vertical(monitor, zone);
      }
    }
  }
  if (external || moving || (zone != Zone::NONE && !dwell.fired))
    wake();
}
int timerCallback(void *) {
  armed = false;
  try {
    tick();
  } catch (...) {
    stop();
  }
  return 0;
}

bool boolean(lua_State *L, int table, const char *key, bool fallback) {
  lua_getfield(L, table, key);
  if (!lua_isnil(L, -1) && !lua_isboolean(L, -1))
    throw std::runtime_error(std::string{key} + " must be boolean");
  const bool value = lua_isnil(L, -1) ? fallback : lua_toboolean(L, -1);
  lua_pop(L, 1);
  return value;
}
double number(lua_State *L, int table, const char *key, double fallback,
              double min, double max) {
  lua_getfield(L, table, key);
  if (!lua_isnil(L, -1) && lua_type(L, -1) != LUA_TNUMBER)
    throw std::runtime_error(std::string{key} + " must be a number");
  const double value = lua_isnil(L, -1) ? fallback : lua_tonumber(L, -1);
  lua_pop(L, 1);
  if (!std::isfinite(value) || value < min || value > max)
    throw std::runtime_error(std::string{key} + " is out of range");
  return value;
}
int configure(lua_State *L) {
  try {
    if (lua_gettop(L) != 1 || !lua_istable(L, 1))
      throw std::runtime_error("configure expects one table");
    Settings next;
    next.enabled = boolean(L, 1, "enabled", true);
    next.dragEdges = boolean(L, 1, "drag_edges", true);
    next.externalDrags = boolean(L, 1, "external_drags", true);
    next.windowDrags = boolean(L, 1, "window_drags", true);
    next.smooth = boolean(L, 1, "smooth_scroll", true);
    next.edgeSize = number(L, 1, "edge_size", 16, 1, 512);
    next.speed = number(L, 1, "scroll_speed", 900, 1, 10000);
    next.delay = number(L, 1, "edge_delay", 500, 0, 60000);
    next.repeat = number(L, 1, "repeat_delay", 700, 16, 60000);
    std::set<std::string> nextMonitors;
    lua_getfield(L, 1, "monitors");
    if (!lua_isnil(L, -1)) {
      if (!lua_istable(L, -1))
        throw std::runtime_error("monitors must be a connector-name array");
      for (size_t i = 1; i <= lua_rawlen(L, -1); ++i) {
        lua_rawgeti(L, -1, i);
        if (lua_type(L, -1) != LUA_TSTRING)
          throw std::runtime_error("invalid monitor name");
        nextMonitors.insert(lua_tostring(L, -1));
        lua_pop(L, 1);
      }
    }
    lua_pop(L, 1);
    lua_getfield(L, 1, "corners");
    if (!lua_isnil(L, -1)) {
      if (!lua_istable(L, -1))
        throw std::runtime_error("corners must be a table");
      for (size_t i = 0; i < cornerNames.size(); ++i) {
        lua_getfield(L, -1, cornerNames[i]);
        if (!lua_isnil(L, -1)) {
          if (!lua_istable(L, -1))
            throw std::runtime_error("corner must be a table");
          const int table = lua_gettop(L);
          next.corners[i] = {
              boolean(L, table, "enabled", false),
              number(L, table, "size", 4, 1, 512),
              static_cast<int>(number(L, table, "delay", 300, 0, 60000)),
              boolean(L, table, "during_drag", false),
          };
        }
        lua_pop(L, 1);
      }
    }
    stop();
    // Hyprland 0.57 rebuilds its Lua event handler on reload, but does not
    // subscribe that new handler to custom events from already loaded plugins.
    // Reconnect the bridge before the config registers hl.on callbacks.
    const auto manager = Config::Lua::CConfigManager::fromLuaState(L);
    if (!manager || !manager->m_eventHandler || !actionEvent)
      throw std::runtime_error("edge-navigation: Lua event bridge unavailable");
    (void)manager->m_eventHandler->removeCustomEvent(EVENT_NAME);
    const auto connected = manager->m_eventHandler->addCustomEvent(actionEvent);
    if (!connected)
      throw std::runtime_error("edge-navigation: " + connected.error());
    settings = next;
    monitors = std::move(nextMonitors);
    wake();
    lua_pushboolean(L, true);
    return 1;
  } catch (const std::exception &error) {
    lua_pushboolean(L, false);
    lua_pushstring(L, error.what());
    return 2;
  }
}
int focusWorkspace(lua_State *L) {
  if (lua_gettop(L) != 2 || !lua_isinteger(L, 1) ||
      lua_type(L, 2) != LUA_TSTRING || lua_tointeger(L, 1) < 1 ||
      lua_tointeger(L, 1) > INT32_MAX || !eligibleDrag() || locked() ||
      overview()) {
    lua_pushboolean(L, false);
    return 1;
  }
  auto monitor = State::monitorState()->query().name(lua_tostring(L, 2)).run();
  if (!monitor) {
    lua_pushboolean(L, false);
    return 1;
  }
  const auto id = ::Workspace::SWorkspaceNumberedID(
      static_cast<uint32_t>(lua_tointeger(L, 1)));
  PHLWORKSPACE target;
  for (const auto &ref : State::workspaceState()->workspaces()) {
    if (ref->numberedID() == id.value) {
      target = ref.lock();
      break;
    }
  }
  if (target && target->m_monitor != monitor) {
    lua_pushboolean(L, false);
    return 1;
  }
  if (!target)
    target = State::workspaceState()->createNumbered(id, monitor);
  if (target) {
    finishPan();
    const auto old = monitor->m_activeWorkspace;
    // internal=false releases all mouse buttons, even with noFocus/noMouseMove.
    // Never use that path while preserving an application's/native drag.
    monitor->changeWorkspace(target, true, true, true);
    if (old != target) {
      const bool next = old && old->numberedID() && target->numberedID() &&
                        target->numberedID() > old->numberedID();
      if (old)
        Animation::Workspace::startAnimation(
            old, Animation::Workspace::ANIMATION_TYPE_OUT, next, false,
            old->m_animationStyle);
      Animation::Workspace::startAnimation(
          target, Animation::Workspace::ANIMATION_TYPE_IN, next, false,
          target->m_animationStyle);
      for (const auto &window : Desktop::windowState()->windows()) {
        if (window->m_workspace == old &&
            (window->m_state & Desktop::View::WINDOW_STATE_PINNED) &&
            window->layoutTarget())
          window->layoutTarget()->assignToSpace(target->space());
      }
      g_layoutManager->recalculateMonitor(
          monitor,
          Layout::CLayoutManager::RECALCULATE_MONITOR_REASON_WORKSPACE_CHANGE);
      IPC::Socket2::sock()->postEvent({"workspace", target->displayName()});
      IPC::Socket2::sock()->postEvent(
          {"workspacev2", std::format("{},{}", ::Workspace::selector(*target),
                                      target->displayName())});
      Event::bus()->m_events.workspace.active.emit(target);
    }
    if (windowDrag()) {
      const auto dragging = g_layoutManager->dragController()->target();
      if (dragging && dragging->floating()) {
        // Match native mouseMove's workspace adoption, without requiring
        // pointer motion, ending the grab, or changing its drop behavior.
        const auto box = dragging->position();
        dragging->assignToSpace(target->space());
        dragging->setPositionGlobal(box);
        dragging->warpPositionSize();
      }
    }
    auto last = target->getLastFocusedWindow();
    if (!Desktop::View::validMapped(last))
      last = target->getFocusCandidate();
    Desktop::focusState()->fullWindowFocus(
        last, Desktop::FOCUS_REASON_DESKTOP_STATE_CHANGE);
    g_pInputManager->refocusPointer();
  }
  lua_pushboolean(L, !!target);
  return 1;
}
int status(lua_State *L) {
  lua_newtable(L);
  const auto boolean = [&](const char *name, bool value) {
    lua_pushboolean(L, value);
    lua_setfield(L, -2, name);
  };
  const auto integer = [&](const char *name, int64_t value) {
    lua_pushinteger(L, value);
    lua_setfield(L, -2, name);
  };
  boolean("enabled", settings.enabled);
  boolean("external_drags", settings.externalDrags);
  boolean("window_drags", settings.windowDrags);
  boolean("smooth_scroll", settings.smooth);
  boolean("external_drag_active", externalDrag());
  boolean("window_drag_active", windowDrag());
  boolean("camera_owned", !camera.expired());
  integer("edge_delay", settings.delay);
  integer("repeat_delay", settings.repeat);
  integer("scroll_speed", settings.speed);
  integer("edge_size", settings.edgeSize);
  return 1;
}
void cleanup() {
  unloading = true;
  mouseMove.reset();
  mouseButton.reset();
  preReload.reset();
  stop();
  if (timer) {
    wl_event_source_remove(timer);
    timer = nullptr;
  }
  if (eventOwned) {
    (void)Event::bus()->removePluginEvent(EVENT_NAME);
    eventOwned = false;
  }
  actionEvent.reset();
}
void requireABI() {
  const auto family = [](std::string_view v) {
    return std::string{v.substr(0, v.find_last_of('.'))};
  };
  const auto built =
      std::string{GIT_COMMIT_HASH} + "_aq_" + family(AQUAMARINE_VERSION) +
      "_hu_" + family(HYPRUTILS_VERSION) + "_hg_" +
      family(HYPRGRAPHICS_VERSION) + "_hc_" + family(HYPRCURSOR_VERSION) +
      "_hlg_" + family(HYPRLANG_VERSION);
  if (built != __hyprland_api_get_hash())
    throw std::runtime_error("edge-navigation: ABI mismatch");
}
} // namespace
APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE pluginHandle) {
  requireABI();
  handle = pluginHandle;
  unloading = false;
  settings.enabled = false; // Opt in only when configured; safe during reload.
  try {
    if (!HyprlandAPI::addLuaFunction(handle, "edge_navigation", "configure",
                                     configure) ||
        !HyprlandAPI::addLuaFunction(handle, "edge_navigation",
                                     "focus_workspace", focusWorkspace) ||
        !HyprlandAPI::addLuaFunction(handle, "edge_navigation", "status",
                                     status))
      throw std::runtime_error("edge-navigation: Lua registration failed");
    actionEvent = makeShared<Event::CEventBus::CCustomEvent>(
        EVENT_NAME, std::vector<Event::CEventBus::CCustomEvent::eType>{
                        Event::CEventBus::CCustomEvent::TYPE_STRING,
                        Event::CEventBus::CCustomEvent::TYPE_STRING});
    if (!Event::bus()->addPluginEvent(actionEvent))
      throw std::runtime_error("edge-navigation: event registration failed");
    eventOwned = true;
    timer = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, timerCallback,
                                    nullptr);
    if (!timer)
      throw std::runtime_error("edge-navigation: timer allocation failed");
    mouseMove = Event::bus()->m_events.input.mouse.move.listen(
        [](Vector2D, Event::SCallbackInfo &) {
          if (unloading || !settings.enabled || locked()) {
            return;
          }

          auto monitor = State::monitorState()
                             ->query()
                             .vec(g_pInputManager->getMouseCoordsInternal())
                             .run();

          if (!monitor ||
              (!monitors.empty() && !monitors.contains(monitor->m_name))) {
            wake();
            return;
          }

          const auto point =
              g_pInputManager->getMouseCoordsInternal() - monitor->m_position;

          const bool external = externalDrag();
          const bool moving = windowDrag();
          const bool dragging =
              external || !!g_layoutManager->dragController()->target();

          const Zone zone =
              hit(point.x, point.y, monitor->m_size.x, monitor->m_size.y,
                  external, dragging, settings, moving);

          // Handle corner entry and exit immediately.
          if (corner(zone) || corner(dwell.zone)) {
            tick();
          } else {
            // Preserve timer-driven edge scrolling.
            wake();
          }
        });
    mouseButton = Event::bus()->m_events.input.mouse.button.listen(
        [](IPointer::SButtonEvent, Event::SCallbackInfo &) { wake(); });
    preReload = Event::bus()->m_events.config.preReload.listen([] {
      stop();
      settings.enabled = false;
    });
    return {"edge-navigation",
            "Window/file drag edge navigation and configurable hot corners",
            "local", EDGE_NAVIGATION_VERSION};
  } catch (...) {
    cleanup();
    throw;
  }
}
APICALL EXPORT void PLUGIN_EXIT() { cleanup(); }
