--- @brief [[
--- Defines the configuration table for use throughout Neorg.
--- @brief ]]

-- TODO(vhyrro): Make `norg_version` and `version` a `Version` class.

--- @alias OperatingSystem
--- | "windows"
--- | "wsl"
--- | "wsl2"
--- | "mac"
--- | "linux"

--- @alias neorg.configuration.module { config?: table }

--- @class (exact) neorg.configuration.user
--- @field lazy_loading boolean                              Whether to defer loading the Neorg core until after the user has entered a `.norg` file.
--- @field load table<string, neorg.configuration.module>    A list of modules to load, alongside their configurations.

--- @class (exact) neorg.configuration
--- @field user_config neorg.configuration.user              Stores the configuration provided by the user.
--- @field modules table<string, neorg.configuration.module> Acts as a copy of the user's configuration that may be modified at runtime.
--- @field manual boolean?                                   Used if Neorg was manually loaded via `:NeorgStart`. Only applicable when `user_config.lazy_loading` is `true`.
--- @field arguments table<string, string>                   A list of arguments provided to the `:NeorgStart` function in the form of `key=value` pairs. Only applicable when `user_config.lazy_loading` is `true`.
--- @field norg_version string                               The version of the file format to be used throughout Neorg. Used internally.
--- @field version string                                    The version of Neorg that is currently active. Automatically updated by CI on every release.
--- @field os_info OperatingSystem                           The operating system that Neorg is currently running under.
--- @field pathsep "\\"|"/"                                  The operating system that Neorg is currently running under.

--- Gets the current operating system.
--- @return OperatingSystem
local function get_os_info()
    local os = vim.loop.os_uname().sysname:lower()

    if os:find("windows_nt") then
        return "windows"
    elseif os == "darwin" then
        return "mac"
    elseif os == "linux" then
        local f = io.open("/proc/version", "r")
        if f ~= nil then
            local version = f:read("*all")
            f:close()
            if version:find("WSL2") then
                return "wsl2"
            elseif version:find("microsoft") then
                return "wsl"
            end
        end
        return "linux"
    end

    error("[neorg]: Unable to determine the currently active operating system!")
end

local os_info = get_os_info()

--- Stores the configuration for the entirety of Neorg.
--- This includes not only the user configuration (passed to `setup()`), but also internal
--- variables that describe something specific about the user's hardware.
--- @see neorg.setup
---
--- @type neorg.configuration
local config = {
    user_config = {
        lazy_loading = false,
        load = {
            --[[
                ["name"] = { config = { ... } }
            --]]
        },
    },

    modules = {},
    manual = nil,
    arguments = {},

    norg_version = "1.1.1",
    version = "7.0.0",

    os_info = os_info,
    pathsep = os_info == "windows" and "\\" or "/",
}

return config
