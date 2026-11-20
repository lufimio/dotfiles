#pragma once
#include "IndicatorSettings.hpp"
#include <string>
struct lua_State;

namespace dynamic_share {
// On error, settings is unchanged and the Lua stack is balanced.
__attribute__((visibility("hidden"))) bool readIndicator(lua_State*, int index, IndicatorSettings&, std::string& error);
}
