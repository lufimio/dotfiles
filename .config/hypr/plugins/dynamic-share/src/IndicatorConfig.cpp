#include "IndicatorConfig.hpp"
#include <utility>
extern "C" {
#include <lua.h>
}

namespace dynamic_share {
namespace {
std::string_view string(lua_State* state, int index) {
    size_t size = 0;
    const auto* value = lua_tolstring(state, index, &size);
    return value ? std::string_view{value, size} : std::string_view{};
}
bool flag(lua_State* state, int index, const char* name, bool& value, std::string& error) {
    lua_getfield(state, index, name);
    const bool ok = lua_isnil(state, -1) || lua_isboolean(state, -1);
    if (lua_isboolean(state, -1))
        value = lua_toboolean(state, -1);
    lua_pop(state, 1);
    if (!ok)
        error = std::string("indicator.") + name + " must be a boolean";
    return ok;
}
bool readStyle(lua_State* state, int index, IndicatorStyle& style, const std::string& path, std::string& error) {
    const auto integer = [&](const char* name, int& value, int maximum) {
        lua_getfield(state, index, name);
        const bool ok = lua_isnil(state, -1) || (lua_isinteger(state, -1) && lua_tointeger(state, -1) >= 0 && lua_tointeger(state, -1) <= maximum);
        if (ok && !lua_isnil(state, -1))
            value = static_cast<int>(lua_tointeger(state, -1));
        lua_pop(state, 1);
        if (!ok) error = path + "." + name + " is outside its supported integer range";
        return ok;
    };
    const auto color = [&](const char* name, std::uint32_t& value) {
        lua_getfield(state, index, name);
        bool ok = lua_isnil(state, -1);
        if (lua_type(state, -1) == LUA_TSTRING) {
            const auto parsed = indicatorColor(string(state, -1));
            ok = parsed.has_value();
            if (parsed) value = *parsed;
        }
        lua_pop(state, 1);
        if (!ok) error = path + "." + name + " must be #RRGGBB or #RRGGBBAA";
        return ok;
    };
    if (!integer("border_width", style.borderWidth, 32) || !integer("glow_size", style.glowSize, 128) ||
        !integer("radius", style.radius, 128) || !color("border_color", style.borderColor) || !color("glow_color", style.glowColor))
        return false;
    lua_getfield(state, index, "glow_opacity");
    const bool valid = lua_isnil(state, -1) || lua_type(state, -1) == LUA_TNUMBER;
    if (valid && !lua_isnil(state, -1))
        style.glowOpacity = lua_tonumber(state, -1);
    lua_pop(state, 1);
    if (!valid || !style.valid()) {
        error = path + ".glow_opacity must be a finite number between 0 and 1";
        return false;
    }
    return true;
}
}
bool readIndicator(lua_State* state, int index, IndicatorSettings& settings, std::string& error) {
    index = lua_absindex(state, index);
    if (!lua_istable(state, index)) {
        error = "indicator must be a settings table";
        return false;
    }
    auto candidate = settings;
    if (!flag(state, index, "enabled", candidate.enabled, error) || !flag(state, index, "windows", candidate.windows, error) ||
        !flag(state, index, "workspaces", candidate.workspaces, error) || !flag(state, index, "monitors", candidate.monitors, error))
        return false;
    for (auto [name, style] : {std::pair{"window", &candidate.window}, {"workspace", &candidate.workspace}, {"monitor", &candidate.monitor}}) {
        // Legacy flat fields still update all three kinds. Nested fields win,
        // while omitted fields retain that kind's current value.
        if (!readStyle(state, index, *style, "indicator", error))
            return false;
        lua_getfield(state, index, name);
        bool ok = true;
        if (!lua_isnil(state, -1)) {
            if (!lua_istable(state, -1)) {
                error = std::string("indicator.") + name + " must be a style table";
                ok = false;
            } else
                ok = readStyle(state, lua_absindex(state, -1), *style, std::string("indicator.") + name, error);
        }
        lua_pop(state, 1);
        if (!ok)
            return false;
    }
    settings = candidate;
    return true;
}
} // namespace dynamic_share
