---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by Cochiko.
--- DateTime: 11/18/2022 1:56 PM
---

------------------------------
-- GENERATED DOCS AMENDMENT --
------------------------------

--- Returns info for an item.
--- [https://wowpedia.fandom.com/wiki/API_GetItemInfo]
--- @param item number | string Item ID, Link or Name.
--- @return string, string, number, number, number, string, string, any @ itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice
function GetItemInfo(itemNameOrID)
end


---------------
-- NEW TYPES --
---------------
---@class ItemInfoFull
---@field name string Display name of the item
---@field id number ID of the item
---@field iconId number Icon ID of the item
local ItemInfoFull = {};
