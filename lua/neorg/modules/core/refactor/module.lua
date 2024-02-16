--[[
    file: Refactor-Module
    title: Move Files Fearlessly
    summary: A module that allows for moving files around without breaking links to or from the file
    internal: false
    ---

This module will provide a way to move files around without breaking existing links to or from the
file.

The aim is to provide a command to move them, but also to hook nvim's lsp handlers in order to
support moving files via something like Oil, which fires the correct events when files are moved.
--]]

local neorg = require("neorg.core")
local modules = neorg.modules

local module = modules.create("core.refactor")

module.setup = function()
    return {
        success = true,
        requires = {
            "core.integrations.treesitter",
            "core.dirman",
            "core.neorgcmd",
            "core.link-tools",
        },
    }
end

local link_tools, dirman
module.load = function()
    module.required["core.neorgcmd"].add_commands_from_table({
        -- TODO: we should probably make a few different commands
        refactor = {
            min_args = 0, -- Tells neorgcmd that we want at least one argument for this command
            max_args = 1, -- Tells neorgcmd we want no more than one argument
            -- args = 0, -- Setting this variable instead would be the equivalent of min_args = 1 and max_args = 1
            name = "refactor",
        },
    })
    link_tools = module.required["core.link-tools"]
    dirman = module.required["core.dirman"]
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["refactor"] = true,
    },
}

module.on_event = function(event)
    if event.split_type[2] == "refactor" then
        module.private.test(event.content[1])
    end
end

---@class lsp.TextEdit
---@field range lsp.Range
---@field newText string

---@class lsp.WorkspaceEdit
---@field changes table<string, lsp.TextEdit[]>

module.public = {
    ---move the current file from one location to another, and update all the links to/from the file
    ---in the current workspace
    ---@param current_path any
    ---@param new_path any
    rename_file = function(current_path, new_path)
        new_path = vim.fs.normalize(new_path)
        current_path = vim.fs.normalize(current_path)

        ---@type lsp.WorkspaceEdit
        local wsEdit = { changes = {} }
        local current_file_changes = module.public.fix_out_links(current_path, new_path)
        if #current_file_changes > 0 then
            local current_path_uri = vim.uri_from_fname(new_path)
            wsEdit.changes[current_path_uri] = current_file_changes
        end

        local ws_name = dirman.get_current_workspace()[1]
        local ws_path = dirman.get_current_workspace()[2]

        local files = dirman.get_norg_files(ws_name)
        local new_ws_path = "$" .. string.gsub(new_path, "^" .. ws_path, "")
        new_ws_path = string.gsub(new_ws_path, "%.norg$", "")
        for _, file in ipairs(files) do
            local file_changes = module.public.fix_in_links_in_file(current_path, file, new_ws_path)
            if #file_changes > 0 then
                local file_uri = vim.uri_from_fname(file)
                wsEdit.changes[file_uri] = file_changes
            end
        end
        P(wsEdit)

        os.rename(current_path, new_path)
        vim.cmd.e(new_path)
        vim.lsp.util.apply_workspace_edit(wsEdit, "utf-8")
    end,

    -- NOTE: I want to use LSP text changes to update all the files in one go via a call
    -- to `vim.lsp.util.apply_workspace_edit()` where a WorkspaceEdit is in the form:
    -- `{ changes = { [fileuri]: TextEdit[] }[] }`

    ---fixes the links _in_ the file being moved
    ---@param current_path string
    ---@param new_path string
    ---@return lsp.TextEdit[]
    fix_out_links = function(current_path, new_path)
        current_path = vim.fs.normalize(current_path)
        new_path = vim.fs.normalize(new_path)
        local current_dir = vim.fs.dirname(current_path)
        local current_ws = dirman.get_current_workspace()[2]
        -- current buffer links
        local links = link_tools.get_file_links_from_buf(0)
        local document_edits = {}
        for _, link in ipairs(links) do
            local path_text = link[1]
            if not string.match(path_text, "^%$") then
                -- NOTE: this link transform could probably go into the dirman utils module or fs

                -- transform relative paths into a workspace relative path
                local ws_path = "$" .. string.gsub(current_dir .. "/" .. path_text, "^" .. current_ws, "")

                -- TODO: test that this works for paths with multiple "dir/../dir2/../"'s in it
                ws_path = string.gsub(ws_path, "/[^/]+/%.%./", "/")

                ---@type lsp.TextEdit
                local text_edit = {
                    newText = ws_path,
                    range = {
                        start = {
                            line = link[2],
                            character = link[3],
                        },
                        ["end"] = {
                            line = link[4],
                            character = link[5],
                        }
                    }
                }
                table.insert(document_edits, text_edit)
            end
        end
        return document_edits
    end,

    ---generate text edits to fix links in `file_path` to `current_path` so that they point to
    ---`new_path`
    ---@param current_path string full path to norg file before it's moved
    ---@param file_path string full path to the file we're checking for links to the current_path
    ---@param new_ws_path string ws relative path to the new norg file. In form: `$/tools/git`
    ---@return lsp.TextEdit[]
    fix_in_links_in_file = function(current_path, file_path, new_ws_path)
        local file_dir = vim.fs.dirname(file_path)
        local current_ws = dirman.get_current_workspace()[2]
        local current_path_wsr = current_path:gsub("^" .. current_ws, "")
        current_path_wsr = "$" .. current_path_wsr:gsub("%.norg$", "")

        local links = link_tools.get_file_links_from_file(file_path)
        local document_edits = {}
        for _, link in ipairs(links) do
            local path_text = link[1]
            -- figure out where the link is pointing, and compare it to the `current_path`
            -- if it's equal, the we change it to the new workspace path`
            if not string.match(path_text, "^%$") then
                -- this is a relative path, and we'll want to see where it's pointing
                local ws_rel_link_text = module.private.path_rel_to_ws(current_ws, file_dir, path_text)
                if ws_rel_link_text == current_path_wsr then
                    print("this relative link points to the refactored file", path_text)
                    ---@type lsp.TextEdit
                    local text_edit = {
                        newText = new_ws_path,
                        range = {
                            start = {
                                line = link[2],
                                character = link[3],
                            },
                            ["end"] = {
                                line = link[4],
                                character = link[5],
                            }
                        }
                    }
                    table.insert(document_edits, text_edit)
                end
            else
                -- handle existing ws relative links too
                if path_text == current_path_wsr then
                    print("this wsr link points to the refactored file", path_text)
                    ---@type lsp.TextEdit
                    local text_edit = {
                        newText = new_ws_path,
                        range = {
                            start = {
                                line = link[2],
                                character = link[3],
                            },
                            ["end"] = {
                                line = link[4],
                                character = link[5],
                            }
                        }
                    }
                    table.insert(document_edits, text_edit)
                end
            end
        end
        return document_edits
    end
}

module.private = {
    ---just a function that's used to test whatever I'm working on
    test = function(file)
        local current = vim.api.nvim_buf_get_name(0)
        module.public.rename_file(current, file)
    end,

    path_rel_to_ws = function(ws, current_dir, path)
        local ws_path = "$" .. string.gsub(current_dir .. "/" .. path, "^" .. ws, "")

        -- TODO: test that this works for paths with multiple "dir/../dir2/../"'s in it
        ws_path = string.gsub(ws_path, "/[^/]+/%.%./", "/")

        return ws_path
    end
}

return module
