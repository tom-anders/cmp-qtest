local source = {}

source.new = function()
    return setmetatable({}, { __index = source })
end

source.is_available = function()
    return vim.bo.ft == 'cpp'
end

local utils = require("nvim-treesitter.ts_utils")

local find_surrounding_method = function()
    local parent = utils.get_node_at_cursor()
    while parent and parent:type() ~= 'function_definition' do
        parent = parent:parent()
    end

    return parent
end

local get_method_name = function(method_node)
    return vim.treesitter.query.get_node_text(method_node:field('declarator')[1]:field('declarator')[1]:field('name')[1], 0)
end

local find_data_method = function(node)
    local ok, test_method_name = pcall(get_method_name, node)
    if ok then
        local query = vim.treesitter.query.parse_query(vim.bo.filetype,
            string.format([[
            (function_definition declarator:
                (function_declarator declarator:
                    (qualified_identifier name: (identifier) @name (#eq? @name "%s")))) @def]], test_method_name .. '_data'))

        for _, node in query:iter_captures(vim.treesitter.get_parser():parse()[1]:root(), 0) do 
            if node:type() == 'function_definition' then
                return node
            end
        end
    end
end

source.complete = function(self, params, callback)
    local kind = require'cmp.types.lsp'.CompletionItemKind.Snippet

    local surrounding_method = find_surrounding_method()
    local data_method = find_data_method(surrounding_method)
    
    if data_method then
        local query_columns = vim.treesitter.query.parse_query(vim.bo.filetype, 
            [[
                (expression_statement 
                  (call_expression 
                    (qualified_identifier 
                      (namespace_identifier) @namespace (#eq? @namespace "QTest")
                      (template_function
                        (identifier) @name (#eq? @name "addColumn")
                        (template_argument_list
                          (type_descriptor) @type
                          )
                        )
                      )
                    (argument_list (string_literal) @variable)
                    )
                  ) @statement
            ]]
        )

        local matches = {}
        for id, node in query_columns:iter_captures(data_method, 0) do
            local name = query_columns.captures[id]
            if name == 'statement' then table.insert(matches, {detail = vim.treesitter.query.get_node_text(node, 0) })
            elseif name == 'variable' then matches[#matches].variable = vim.treesitter.query.get_node_text(node, 0)
            elseif name == 'type' then matches[#matches].type = vim.treesitter.query.get_node_text(node, 0)
            end
        end

        local items = {}
        for _, match in ipairs(matches) do
            local label = string.format("QFETCH(%s, %s);", match.type, match.variable:sub(2, -2))

            -- Filter out QFETCH statements we've already completed
            local lines = vim.fn.getline(surrounding_method:start() + 1, surrounding_method:end_() - 1)
            if vim.fn.match(lines, label) == -1 then
                table.insert(items, {
                    label = label,
                    detail = match.detail,
                    kind = kind,
                })
            end
        end

        callback{items = items, isIncomplete = false}
    end
end

return source
