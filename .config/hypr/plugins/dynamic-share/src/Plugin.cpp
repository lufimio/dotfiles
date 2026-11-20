#include "CaptureBridge.hpp"
#include "SourcePolicy.hpp"
#include "Selection.hpp"
#include "Placeholder.hpp"
#include "IndicatorConfig.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>

#include <array>
#include <limits>
#include <stdexcept>
#include <string_view>

extern "C" {
#include <lua.h>
}

static_assert(std::string_view{GIT_COMMIT_HASH} == "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947",
              "Review this scaffold against the new Hyprland version before building.");

namespace {

HANDLE pluginHandle = nullptr;
dynamic_share::SourcePolicy policy;
std::unique_ptr<dynamic_share::Selection> selection;
std::unique_ptr<dynamic_share::CaptureBridge> bridge;
CHyprSignalListener windowOpened;

void clearSelection() {
    if (selection)
        selection->clear();
}

void refreshSelection() {
    if (selection)
        selection->current();
}

int reply(lua_State* state, bool ok, const char* message) {
    lua_pushboolean(state, ok);
    lua_pushstring(state, message);
    return 2;
}

std::string_view string(lua_State* state, int index) {
    size_t size = 0;
    const auto* value = lua_tolstring(state, index, &size);
    return value ? std::string_view{value, size} : std::string_view{};
}

int selectFocused(lua_State* state) {
    if (lua_gettop(state) != 0)
        return reply(state, false, "select_focused expects no arguments");
    const auto [ok, message] = selection->focusedWindow();
    return reply(state, ok, message.c_str());
}

int selectWindow(lua_State* state) {
    if (lua_gettop(state) == 0)
        return selectFocused(state);
    if (lua_gettop(state) < 1 || lua_gettop(state) > 2 || !lua_isinteger(state, 1) || lua_tointeger(state, 1) <= 0)
        return reply(state, false, "select_window expects a positive ID from sources_json()");
    if (lua_gettop(state) == 2 && (lua_type(state, 2) != LUA_TSTRING || selection->instance() != string(state, 2)))
        return reply(state, false, "selector instance changed; reopen the picker");
    const auto [ok, message] = selection->window(lua_tointeger(state, 1));
    return reply(state, ok, message.c_str());
}

int selectMonitor(lua_State* state) {
    if (lua_gettop(state) == 0) {
        const auto [ok, message] = selection->focusedMonitor();
        return reply(state, ok, message.c_str());
    }
    if (lua_gettop(state) < 1 || lua_gettop(state) > 2)
        return reply(state, false, "select_monitor expects an ID or connector name, or no argument for the focused monitor");
    if (lua_gettop(state) == 2 && (lua_type(state, 2) != LUA_TSTRING || selection->instance() != string(state, 2)))
        return reply(state, false, "selector instance changed; reopen the picker");
    if (lua_isinteger(state, 1) && lua_tointeger(state, 1) > 0) {
        const auto [ok, message] = selection->monitor(lua_tointeger(state, 1));
        return reply(state, ok, message.c_str());
    }
    if (lua_type(state, 1) == LUA_TSTRING) {
        const auto [ok, message] = selection->monitor(std::string{string(state, 1)});
        return reply(state, ok, message.c_str());
    }
    return reply(state, false, "invalid monitor identity");
}

int sourcesJson(lua_State* state) {
    if (lua_gettop(state) != 0)
        return reply(state, false, "sources_json expects no arguments");
    const auto json = selection->sourcesJson();
    lua_pushlstring(state, json.data(), json.size());
    return 1;
}

int selectWorkspace(lua_State* state) {
    if (lua_gettop(state) == 0) {
        const auto [ok, message] = selection->focusedWorkspace();
        return reply(state, ok, message.c_str());
    }
    if (lua_gettop(state) < 1 || lua_gettop(state) > 2 || !lua_isinteger(state, 1) || lua_tointeger(state, 1) <= 0)
        return reply(state, false, "select_workspace expects an ID from sources_json(), or no arguments for the focused workspace");
    if (lua_gettop(state) == 2 && (lua_type(state, 2) != LUA_TSTRING || selection->instance() != string(state, 2)))
        return reply(state, false, "selector instance changed; reopen the picker");
    const auto [ok, message] = selection->workspace(lua_tointeger(state, 1));
    return reply(state, ok, message.c_str());
}

int sizing(lua_State* state) {
    if (lua_gettop(state) != 1 || lua_type(state, 1) != LUA_TSTRING)
        return reply(state, false, "set_sizing expects 'source' or 'fixed'");
    const auto mode = string(state, 1);
    if (mode != "source" && mode != "fixed")
        return reply(state, false, "set_sizing expects 'source' or 'fixed'");
    bridge->sourceSizing(mode == "source");
    return reply(state, true, mode == "source" ? "source-sized stream enabled" : "fixed helper-sized canvas enabled");
}

int configure(lua_State* state) {
    if (lua_gettop(state) != 1 || !lua_istable(state, 1))
        return reply(state, false, "configure expects a settings table");
    auto text = bridge->placeholderText();
    int fontSize = bridge->placeholderFontSize();
    bool sourceSized = bridge->sourceSizing();
    auto indicator = bridge->indicatorSettings();
    lua_getfield(state, 1, "empty_text");
    if (!lua_isnil(state, -1)) {
        if (lua_type(state, -1) != LUA_TSTRING) {
            lua_pop(state, 1);
            return reply(state, false, "empty_text must be a string");
        }
        size_t length = 0;
        const auto* value = lua_tolstring(state, -1, &length);
        text.assign(value, length);
    }
    lua_pop(state, 1);
    lua_getfield(state, 1, "empty_font_size");
    if (!lua_isnil(state, -1)) {
        if (!lua_isinteger(state, -1) || lua_tointeger(state, -1) < 8 || lua_tointeger(state, -1) > 128) {
            lua_pop(state, 1);
            return reply(state, false, "empty_font_size must be an integer from 8 to 128");
        }
        fontSize = static_cast<int>(lua_tointeger(state, -1));
    }
    lua_pop(state, 1);
    lua_getfield(state, 1, "sizing");
    if (!lua_isnil(state, -1)) {
        const auto value = lua_type(state, -1) == LUA_TSTRING ? string(state, -1) : std::string_view{};
        if (value != "source" && value != "fixed") {
            lua_pop(state, 1);
            return reply(state, false, "sizing must be 'source' or 'fixed'");
        }
        sourceSized = value == "source";
    }
    lua_pop(state, 1);
    lua_getfield(state, 1, "indicator");
    if (!lua_isnil(state, -1)) {
        std::string error;
        if (!dynamic_share::readIndicator(state, -1, indicator, error)) {
            lua_pop(state, 1);
            return reply(state, false, error.empty() ? "indicator must be a settings table" : error.c_str());
        }
    }
    lua_pop(state, 1);
    if (!dynamic_share::Placeholder::valid(text, fontSize))
        return reply(state, false, "empty_text must be valid UTF-8 without NUL, at most 4096 bytes");
    const auto [configured, reason] = bridge->indicator(indicator);
    if (!configured)
        return reply(state, false, reason.c_str());
    if (!bridge->placeholder(std::move(text), fontSize))
        return reply(state, false, "empty_text must be valid UTF-8 without NUL, at most 4096 bytes");
    bridge->sourceSizing(sourceSized);
    return reply(state, true, "Dynamic Share settings updated");
}

int isWindowCastTarget(lua_State* state) {
    if (lua_gettop(state) != 1 || !lua_isinteger(state, 1) || lua_tointeger(state, 1) <= 0)
        return reply(state, false, "is_window_cast_target expects a window ID");
    refreshSelection();
    const bool active = bridge->active() && policy.source() && !policy.locked() && !policy.source()->privateContent &&
        policy.source()->kind == dynamic_share::SourceKind::Window &&
        selection->windowId() == static_cast<std::uint64_t>(lua_tointeger(state, 1));
    lua_pushboolean(state, active);
    return 1;
}

int clearSource(lua_State* state) {
    if (lua_gettop(state) > 1)
        return reply(state, false, "clear expects no arguments, or a selector instance");
    if (lua_gettop(state) == 1 && (lua_type(state, 1) != LUA_TSTRING || selection->instance() != string(state, 1)))
        return reply(state, false, "selector instance changed; reopen the picker");
    clearSelection();
    return reply(state, true, "source cleared; Dynamic Share streams will be empty");
}

int reset(lua_State* state) {
    clearSelection();
    policy.reset();
    refreshSelection();
    return reply(state, true, "dynamic source reset; other portal shares were not changed");
}

int start(lua_State* state) {
    if (lua_gettop(state) != 0)
        return reply(state, false, "start expects no arguments");
    const auto [ok, message] = bridge->start(pluginHandle);
    return reply(state, ok, message.c_str());
}

int stop(lua_State* state) {
    bridge->stop();
    clearSelection();
    policy.reset();
    refreshSelection();
    return reply(state, true, "Dynamic Share disabled; its picker entry will disappear");
}

void field(lua_State* state, const char* name, bool value) {
    lua_pushboolean(state, value);
    lua_setfield(state, -2, name);
}

int status(lua_State* state) {
    refreshSelection();
    lua_newtable(state);
    field(state, "transport_ready", bridge && bridge->available());
    field(state, "capture_hook_installed", bridge && bridge->hookInstalled());
    field(state, "capture_active", bridge && bridge->active());
    field(state, "helper_running", bridge && bridge->helperRunning());
    field(state, "dynamic_peer_attached", policy.session().has_value());
    field(state, "lock_manager_available", static_cast<bool>(g_pSessionLockManager));
    field(state, "locked", policy.locked());
    field(state, "source_selected", policy.source().has_value());
    field(state, "source_private", policy.source() && policy.source()->privateContent);
    field(state, "source_sized", bridge && bridge->sourceSizing());
    field(state, "indicator_enabled", bridge && bridge->indicatorSettings().enabled);
    field(state, "indicator_per_target", true);
    const char* kind = !policy.source() ? "none" :
        (policy.source()->kind == dynamic_share::SourceKind::Window ? "window" :
         (policy.source()->kind == dynamic_share::SourceKind::Monitor ? "monitor" : "workspace"));
    lua_pushstring(state, kind);
    lua_setfield(state, -2, "source_kind");
    const auto name = selection->name();
    lua_pushlstring(state, name.data(), name.size());
    lua_setfield(state, -2, "source_name");
    if (policy.source()) {
        const auto id = policy.source()->kind == dynamic_share::SourceKind::Window ? selection->windowId() :
            (policy.source()->kind == dynamic_share::SourceKind::Monitor ? selection->monitorId() : selection->workspaceId());
        lua_pushinteger(state, static_cast<lua_Integer>(id));
        lua_setfield(state, -2, "target_id");
    }
    lua_pushinteger(state, static_cast<lua_Integer>(policy.generation()));
    lua_setfield(state, -2, "generation");
    if (policy.source()) {
        lua_pushinteger(state, static_cast<lua_Integer>(policy.source()->id));
        lua_setfield(state, -2, "source_cookie");
    }
    lua_pushliteral(state, "experimental native Dynamic Share; select its dedicated window in the portal picker");
    lua_setfield(state, -2, "mode");
    lua_pushliteral(state, DYNAMIC_SHARE_VERSION);
    lua_setfield(state, -2, "version");
    const auto text = bridge->placeholderText();
    lua_pushlstring(state, text.data(), text.size());
    lua_setfield(state, -2, "empty_text");
    return 1;
}

constexpr std::array<std::pair<const char*, PLUGIN_LUA_FN>, 16> functions{{
    {"select_focused", selectFocused}, {"clear", clearSource},
    {"reset", reset}, {"status", status}, {"start", start}, {"stop", stop},
    {"select_window", selectWindow}, {"select_monitor", selectMonitor}, {"sources_json", sourcesJson},
    {"set_sizing", sizing}, {"is_window_cast_target", isWindowCastTarget},
    {"set_dynamic_cast_window", selectWindow}, {"set_dynamic_cast_monitor", selectMonitor},
    {"clear_dynamic_cast_target", clearSource},
    {"configure", configure},
    {"select_workspace", selectWorkspace},
}};

bool registerFunctions() {
    const auto& manager = Config::mgr();
    if (!manager || manager->type() != Config::CONFIG_LUA)
        return false;
    for (const auto& [name, function] : functions) {
        if (!HyprlandAPI::addLuaFunction(pluginHandle, "dynamic_share", name, function))
            return false;
    }
    // Hyprland retains plugin-owned registrations across Lua-state reloads and
    // removes them on unload (including failed init). Do not register twice.
    return true;
}

void resetObservers() {
    windowOpened.reset();
    clearSelection();
}

void requireMatchingABI() {
    // Construct our own value; an inline client-hash symbol from another plugin
    // must not mask the ABI this library was actually built against.
    const auto family = [](std::string_view version) { return std::string{version.substr(0, version.find_last_of('.'))}; };
    const auto built = std::string{GIT_COMMIT_HASH} + "_aq_" + family(AQUAMARINE_VERSION) +
        "_hu_" + family(HYPRUTILS_VERSION) + "_hg_" + family(HYPRGRAPHICS_VERSION) +
        "_hc_" + family(HYPRCURSOR_VERSION) + "_hlg_" + family(HYPRLANG_VERSION);
    if (built != __hyprland_api_get_hash())
        throw std::runtime_error("dynamic-share: header/runtime ABI mismatch");
}

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    requireMatchingABI();
    pluginHandle = handle;
    if (!registerFunctions())
        throw std::runtime_error("dynamic-share: could not register Lua functions");
    try {
        selection = std::make_unique<dynamic_share::Selection>(policy);
        bridge = std::make_unique<dynamic_share::CaptureBridge>(policy, [] { return selection->current(); });
        selection->startObservers([](PHLWINDOW window) { return bridge && bridge->isAnchor(window); });
        refreshSelection();
        windowOpened = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) {
            bridge->observe(window);
        });
        return {"dynamic-share", "Experimental request-driven window/monitor/workspace source switching", "local", DYNAMIC_SHARE_VERSION};
    } catch (...) {
        // Hyprland skips PLUGIN_EXIT when init throws. Drop our direct signal
        // listeners here, even if dlclose cannot unmap the library immediately.
        resetObservers();
        bridge.reset();
        selection.reset();
        policy.reset();
        throw;
    }
}

APICALL EXPORT void PLUGIN_EXIT() {
    bridge.reset();
    resetObservers();
    selection.reset();
    policy.reset();
    // PluginSystem calls the config manager's onPluginUnload after this returns,
    // removing our Lua callbacks and making retained Lua closures fail safely.
    pluginHandle = nullptr;
}
