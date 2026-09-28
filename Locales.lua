-- Keystance translations. Text is written in English and used as its own key, so a
-- missing translation shows the English. Other languages fill ns.L in their own files.
local ADDON, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })
