--[[
    file: Link-Tools-Module
    summary: Functions useful for grabbing link information from a file or buffer
    internal: true
    ---

This module provides an easy interface for querying information about the links in a buffer
or file.
--]]

local neorg = require("neorg.core")
local modules = neorg.modules

local module = modules.create("core.link-tools")

module.setup = function()
    return {
        success = true,
        requires = { "core.integrations.treesitter", "core.dirman", "core.dirman.utils", "core.queries.native" },
    }
end

local dirman, dirman_utils, treesitter
module.load = function()
    treesitter = module.required["core.integrations.treesitter"]
    dirman = module.required["core.dirman"]
    dirman_utils = module.required["core.dirman.utils"]
end

module.public = {
    ---fetch all the links in the given buffer
    ---@param bufnr number
    ---@return table
    get_file_links_from_buf = function(bufnr)
        if bufnr == 0 then
            bufnr = vim.api.nvim_get_current_buf()
        end
        -- local query_node = with_heading and "link_location" or "link_file_text"
        -- local link_query_string = [[
        --     (link (link_location) @link)
        -- ]]
        local link_query_string = [[
            (link
             (link_location
               file: (_)* @file
               type: (_)* @type
               text: (_)* @text))
        ]]

        local norg_parser = vim.treesitter.get_parser(bufnr, "norg")
        if not norg_parser then
            return {}
        end
        local result = {}

        local norg_tree = P(norg_parser:parse())[1]
        local query = vim.treesitter.query.parse("norg", link_query_string)

        local links = {}

        ---@diagnostic disable-next-line: missing-parameter
        for pattern, match, metadata in query:iter_matches(norg_tree:root(), bufnr) do
            local link = {}
            for id, node in pairs(match) do
                link[node:type()] = {
                    text = treesitter.get_node_text(node, bufnr),
                    range = node:range(),
                }
            end
            table.insert(links, link)
        end

        P(links)

        return {}
    end,

    ---fetch all the file links in the given file
    ---@param file_path string
    ---@param with_heading boolean? headings or just the file the link points at
    ---@return table
    get_file_links_from_file = function(file_path, with_heading)
        file_path = vim.fs.normalize(file_path)
        local query_node = with_heading and "link_location" or "link_file_text"

        local nodes = treesitter.get_all_nodes_in_file(query_node, file_path)
        local res = {}

        for _, node in ipairs(nodes) do
            local file = treesitter.get_node_text(node:field("file")[1], file_path)
            local heading_type = treesitter.get_node_text(node:field("type")[1], file_path)
            local heading_text = treesitter.get_node_text(node:field("text")[1], file_path)
            table.insert(res, {
                file = file,
                heading_type = heading_type,
                heading_text = heading_text,
                range = node:range(),
            })
        end

        return res
    end,

    ---Return the full path and header (if applicable) that this link points at. Accounting for
    -- workspace relative and file relative paths.
    -- NOTE: currently only handles norg links (like: `{::}`)
    ---@param host_file string
    ---@param link_text string like {:file:} or {:$/tools/git:}
    ---@return string?, string? #full file path, heading
    where_does_this_link_point = function(host_file, link_text)
        if not link_text:match("^{:.*:.*}$") then
            return nil, nil
        end

        local match = { link_text:match("{:(.*):(.*)}") }
        local file_path = match[1]
        local heading = match[2]

        if file_path:match("^[^%w]") then
            file_path = dirman_utils.expand_path(file_path)
        else -- it's a relative path
            local host_dir = host_file:gsub("/[^/]*$", "")
            file_path = host_dir .. "/" .. file_path
            file_path = string.gsub(file_path, "/[^/]+/%.%./", "/")
        end

        return file_path, heading
    end,
}

module.private = {}

return module
