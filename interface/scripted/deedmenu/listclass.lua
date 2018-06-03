require "/scripts/util.lua"
require "/interface/scripted/deedmenu/tenantclass.lua"

List = {
    template = {
        canvas = "canvas",
        portraitSlot = "portraitSlot",
        toggleButton = "toggleItem"
    }
}
List.__index = List

function List.new(...)
    local self = {}
    --util.debugLog("list new %s", {...})
    setmetatable(self, List)
    self:init(...)
    return self
end

function List:init(listid, listPath)
    self.items = {}
    self.itemIdByIndex = {}
    self.selectedItemId = -1
    self.listId = lisdId
    self.listPath = listPath
end

function List:selectedItem()
    return self.items[self.selectedItemId]
end

function List:setSelectedItem(id)
    if not id then id = -1 end
    self.selectedItemId = id
end

function List:itemInstanceValue(id, jsonPath, default)

end

function List:Each(func)
    for k,v in pairs(self.item) do
        if func(k,v) then
            return v,k
        end
    end
end
TenantList = setmetatable({}, List)
TenantList.__index = TenantList

function TenantList.new(...)
    local self = {}
    --util.debugLog("list new %s", {...})
    setmetatable(self, TenantList)
    self:init(...)
    return self
end

function TenantList:init(tenants)
    self.items = {}
    self.itemIdByIndex = {}
    self.selectedItemId = -1
    self.listSize = math.min(#tenants+1, 5) 
    self.listId = "tenantList"
    self.listPath = "listLayout.tenantList"
    self.listLayout = "layouts.listItemTitle"
    if #tenants == 0 then
        widget.setVisible(self.listPath, false)
        return
    end
    util.setDebug(true)
    --util.debugLog("list init:  %s", self.HandItemName)
    widget.registerMemberCallback(self.listPath, "onTenantListItemPressed", onTenantListItemPressed)
    local itemId = nil
    widget.clearListItems(self.listPath)

    for i = 1, math.min(#tenants+1, 5) do
        itemId = widget.addListItem(self.listPath)
        
        local tenant = tenants[i] or {}
        local items = {
            canvas = widget.bindCanvas(string.format("%s.%s.%s",self.listPath, itemId, self.template.canvas)),
            toggleButton = string.format("%s.%s.%s", self.listPath, itemId, self.template.toggleButton),
            portraitSlot = string.format("%s.%s.%s",self.listPath, itemId, self.template.portraitSlot),
            listItemPath = string.format("%s.%s", self.listPath, itemId),
            listItemIndex = i,
            itemId = itemId,
            tenant = Tenant.fromConfig(i-1),
            isCreateNewItem = false
        }
        
        items.checked = widget.getChecked(items.toggleButton)
        if not items.tenant then
            items.isCreateNewItem = true
        end
        self.items[itemId] = items
        widget.setData(items.toggleButton, {id = items.itemId})
        widget.setData(items.portraitSlot, {id = items.itemId, clickSound="/sfx/interface/clickon_success.ogg"})

        self.itemIdByIndex[i] = itemId
    end
 
    
    local canvasParams = config.getParameter(self.listLayout)
    util.each(self.itemIdByIndex, 
    function(i, k)
        local v = self.items[k]
        local iconItem = config.getParameter("npcItem")
        v.canvas:clear()
        if v.isCreateNewItem then
            v.canvas:drawText("Add Tenant",canvasParams.textPositioning, canvasParams.fontSize)
            widget.setItemSlotItem(v.portraitSlot, iconItem)
            return
        end
        if v.tenant.spawn == "npc" then
            v.canvas:drawText(v.tenant.overrides.identity.name, canvasParams.textPositioning, canvasParams.fontSize)
            iconItem.parameters.inventoryIcon = v.tenant:getPortrait("bust")
        else
            v.canvas:drawText(v.tenant.type, canvasParams.textPositioning, canvasParams.fontSize)
            iconItem.parameters.inventoryIcon = v.tenant:getPortrait("full")
        end
        widget.setItemSlotItem(v.portraitSlot, iconItem)
    end)
end


function TenantList:itemInstanceValue(id, jsonPath, default)
    local item = self.items[id]

    if not item then return default end
    if type(item[jsonPath]) ~= "nil" then
        return item[jsonPath]
    end
    
    local path = util.filter(util.split(jsonPath, "."), function(v) return v ~= "" end)
    if path[1] == "tenant" then
        table.remove(path, 1)
        if item and item.tenant then 
            return item.tenant:instanceValue(table.concat(path, "."), default)
        end
    end
    
    return default
end