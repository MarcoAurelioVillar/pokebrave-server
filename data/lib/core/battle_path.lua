-- Adds data/scripts to package.path so battle modules can use require("battle.X").
-- TFS runs with CWD = server binary directory; paths are relative to that.
local sep = package.config:sub(1,1) == '\\' and '\\' or '/'
local function addPath(p)
    if not package.path:find(p, 1, true) then
        package.path = p .. ';' .. package.path
    end
end
addPath('data' .. sep .. 'scripts' .. sep .. '?' .. sep .. 'init.lua')
addPath('data' .. sep .. 'scripts' .. sep .. '?.lua')
