-- Sensitive-operation permissions, not an app sandbox. Relog after editing:
-- Hyprland 0.57.2 reads permission rules only during compositor startup.
local function exact(value)
	return "^" .. value:gsub("([\\.^$|?*+()%[%]{}])", "\\%1") .. "$"
end
local function allow(binary, permission)
	hl.permission({ binary = exact(binary), type = permission, mode = "allow" })
end

for _, binary in ipairs({
	"/usr/bin/grim",
	"/usr/bin/hyprpicker",
	"/usr/bin/obs",
	"/usr/lib/xdg-desktop-portal-hyprland",
	"/usr/bin/dms",
}) do
	allow(binary, "screencopy")
end

allow("/usr/lib/xdg-desktop-portal-hyprland", "cursorpos")
allow("/usr/bin/obs", "cursorpos")

for _, plugin in ipairs(require("hyprland.plugins").required) do
	allow(plugin.path, "plugin")
end

-- Keyboard permissions match device names, not general app key injection.
for _, keyboard in ipairs({
	"video-bus",
	"intel-hid-events",
	"intel-hid-5-button-array",
	"power-button",
	"power-button-1",
	"at-translated-set-2-keyboard",
	"hp-wmi-hotkeys",
	"xremap",
	"vicinae-snippet-virtual-keyboard",
	"wh-ch720n-(avrcp)",
}) do
	allow(keyboard, "keyboard")
end

hl.permission({ binary = ".*", type = "keyboard", mode = "ask" })

-- Do not enable halfway through an existing session without its startup rules.
-- The instance-specific environment marker survives config reloads.
local instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
local ready = instance and os.getenv("HYPR_PERMISSIONS_READY") == instance
hl.config({ ecosystem = { enforce_permissions = ready == true } })
hl.on("hyprland.start", function()
	local dialog = io.open("/usr/bin/hyprland-dialog", "rb")
	assert(dialog, "Install hyprland-guiutils before enabling permission prompts")
	dialog:close()
	hl.env("HYPR_PERMISSIONS_READY", assert(instance))
	hl.config({ ecosystem = { enforce_permissions = true } })
end)
