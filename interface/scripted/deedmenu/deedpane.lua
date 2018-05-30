require "/objects/spawner/colonydeed/timer.lua"
require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/messageutil.lua"
storage = storage or {}

listManager = {
    template = {
        canvas = "portraitCanvas",
        portraitSlot = "portraitSlot",
        toggleButton = "background"
    }
}
listManager.__index = listManager

Tenant = {}
Tenant.__index = Tenant

comp = {}

comp.resolve = function(v) 
    local vType = type(v)
    if vType == "table" and v.func then
        for i,item in pairs(v.args) do
            v.args[i] = comp.resolve(item)
        end
        return self[v.func](table.unpack(v.args))
    end
    return v
end

comp.eq = function(v1, v2) return compare(comp.resolve(v1), comp.resolve(v2)) end
comp.ne = function(v1, v2) return not compare(comp.resolve(v1, comp.resolve(v2))) end
comp.gt = function(v1, v2) return comp.resolve(v1) >  comp.resolve(v2) end
comp.ge = function(v1, v2) return comp.resolve(v1) >= comp.resolve(v2) end
comp.lt = function(v1, v2) return comp.resolve(v1) <  comp.resolve(v2) end
comp.le = function(v1, v2) return comp.resolve(v1) <= comp.resolve(v2) end
comp.set = function(v1, v2) 
    v1, v2 = comp.resolve(v1), comp.resolve(v2)
    if type(v1) ~= "nil" then
        return v1
    end
    return v2
end

comp.contains = function(v1, v2) 
    v1 = comp.resolve(v1)
    v2 = comp.resolve(v2)
    if type(v1) == "table" then
        return contains(v1, v2)
    end
end

comp.compare = function(v1, v2) end

comp.drawText = function(canvas, text, args) args = comp.resolve(args); return canvas:drawText(comp.resolve(text), args.textPositioning, args.fontSize, args.fontColor) end 

function comp.result(fullPath, state, key) 

end

function Tenant.new(...)
    local self = {}
    setmetatable(self, Tenant)
    self:init(...)
    return self
end

function Tenant.fromConfig(jsonIndex)
    
    local self = config.getParameter("tenants."..tostring(jsonIndex), {})
    
    if isEmpty(self) then
        return nil
    end
    setmetatable(self, Tenant)
    self:init(
        {jsonIndex = jsonIndex, 
        dataSource = "config"}
    )
    return self
end

function Tenant:init(args)
    for k,v in pairs(args) do
        self[k] = v
    end
    if self.dataSource ~= "config" then
        self.config = root.npcConfig(self.type)
    else 
        self.config = "configs."..self.type.."."
    end
end

function Tenant:getPortrait(type)
    if self.dataSource == "config" then
        local path = string.format("tenantPortraits.%s.%s", self.jsonIndex, type)
        return config.getParameter(path)
    end
end

function Tenant:getConfig(jsonPath, default)
    if type(self.config) == "string" then
        return config.getParameter(self.config..jsonPath, default)
    end
    return sb.jsonQuery(self.config, jsonPath) or default
end

function Tenant:instanceValue(jsonPath, default)
    return self[jsonPath] or sb.jsonQuery(self.overrides, jsonPath) or self:getConfig(jsonPath, default)
end


function Tenant:setInstanceValue(jsonPath, value)
    if value then
        if self[jsonPath] then
            self[jsonPath] = value
            return
        end
        jsonSetPath(self.overrides, jsonPath, value)
    end
end

function listManager.new(...)
    local self = {}
    setmetatable(self, listManager)
    self:init(...)
    return self
end

function listManager:init(tenants)
    self.items = {}
    self.itemIdByIndex = {}
    self.selectedItemId = nil
    self.listPath = "listLayout.tenantList"

    widget.registerMemberCallback(self.listPath, "onTenantListItemPressed", onTenantListItemPressed)
    local itemId = nil
    widget.clearListItems(self.listPath)
    for i = 1, math.min(#tenants+1, 5) do
        sb.logInfo("listPath: %s", self.listPath)
        
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
        widget.setData(items.toggleButton, {itemId = items.itemId})
        widget.setData(items.portraitSlot, {itemId = items.itemId, clickSound="/sfx/interface/clickon_success.ogg"})
        
       -- sb.logInfo("listManagerInit isCreateNewItem- %s", self.items[itemId].isCreateNewItem )
        table.insert(self.itemIdByIndex, itemId)

    end

    --local firstItem = self.items[self.itemIdByIndex[1]]
    

    local itemPortraitPosition = {15, 5}
    local itemSize = {100, 20}
    local itemTextPosition = {30, 9} 
    local textParams = {position = itemTextPosition, horizontalAnchor="left", verticalAnchor="mid"}

    util.each(self.itemIdByIndex, 
    function(i, k)
        local v = self.items[k]
        local iconItem = config.getParameter("npcItem")
        v.canvas:clear()
        if v.isCreateNewItem then
            v.canvas:drawText("Add Tenant",textParams , 8)
            widget.setItemSlotItem(v.portraitSlot, iconItem)
            return
        end
        v.canvas:drawText(v.tenant.overrides.identity.name, textParams, 8)
        iconItem.parameters.inventoryIcon = v.tenant:getPortrait("head")
        widget.setItemSlotItem(v.portraitSlot, iconItem)
    end)
end

function listManager:setSelectedItem(id)
    if not id then id = -1 end
    self.selectedItemId = id
end

function listManager:getSelectedItem()
    return self.items[self.selectedItemId]
end

function listManager:itemInstanceValue(id, jsonPath, default)
    
    local item = self.items[id]

    sb.logInfo("listmanger: iteminstancevalue %s %s %s", id, jsonPath, default)
    if not item then return default end
    if type(item[jsonPath]) ~= "nil" then
        return item[jsonPath]
    end
    --sb.logInfo("listmanger: jsonpath - forced item %s",item[jsonPath])
    local path = util.filter(util.split(jsonPath, "."), function(v) return v ~= "" end)
    if path[1] == "tenant" then
        table.remove(path, 1)
        if item and item.tenant then 
            return item.tenant:instanceValue(table.concat(path, "."), default)
        end
    end
    
    return default
end
--[[
    imageSize   =   20
    1.0              y
]]

function debugFunction(func, ...)
    util.setDebug(true)
    func(...)
    util.setDebug(false)
end

function init()
    self.timers = TimerManager:new()
    self.HandItemName = "npcinjector"
    self.debug = false

    self.delayStagehandDeath = Timer:new("delayStagehandDeath", {
        delay = 2,
        completeCallback = delayStagehandDeath,
        loop = true
      })

    self.paneAliveCooldown = Timer:new("paneAliveCooldown", {
        delay = 0.5,
        completeCallback = checkIfAlive,
        loop = false
    })
    self.timers:manage(self.paneAliveCooldown)

    if not self.delayStagehandDeath:active() then
      self.delayStagehandDeath:start()
    end

    self.timers:manage(self.delayStagehandDeath)
    listManager:init(config.getParameter("tenants"))

    self.getSelectedItem = function()
        return listManager:getSelectedItem()
    end

    self.widgetFunc = function(...)
        local args = {...}
        local name = args[1]
        if type(name) == "string" and widget[name] then
            table.remove(args[1], 1)
            return widget[name](table.unpack(args))
        end
    end

    self.configParam = config.getParameter

    self.selectedOption = widget.getSelectedOption
    self.tenantFromNpcCard = tenantFromNpcCard
    self.tenantFromCapturePod = tenantFromCapturePod

    self.detailCanvas = widget.bindCanvas("detailArea.detailCanvas")
    self.portraitCanvas = widget.bindCanvas("detailArea.portraitCanvas")

    
    self.getState = function()
        return self.state
    end

    self.setState = function(state)
        self.state = state
        return self.onStateChange(state)
    end

    self.onStateChange = function(state)
        debugFunction(updateWidgets)
    end

    self.hasSelectedListItem = function()
        return listManager.selectedItemId and true or false
    end

    self.selectedInstanceValue = function(jsonPath, default)
        local itemId = listManager.selectedItemId
        if itemId then
            return listManager:itemInstanceValue(itemId, jsonPath, default)
        end
        return default
    end

    self.drawPortrait = function()
        self.portraitCanvas:clear()
        local center = config.getParameter("portraitCanvas.center")
        local item = self.getSelectedItem()
        local drawParam
        if item then
            if item.tenant then
                
                local portrait = item.tenant:getPortrait("full")
                drawParam = config.getParameter("portraitCanvas.drawImage.stand")

                self.portraitCanvas:drawImage(drawParam.image, vec2.add(center, drawParam.position), drawParam.scale, drawParam.color, drawParam.centered)

                drawParam = config.getParameter("portraitCanvas.drawImage."..item.tenant:instanceValue("spawn"))

                for i,drawable in ipairs(portrait) do
                    self.portraitCanvas:drawImage(drawable.image, vec2.add(center, drawable.position), drawParam.scale, drawable.color, drawParam.centered)
                end
                return true
            end
        end
    end

    self.drawDetails = function()
        self.detailCanvas:clear()
        local item = self.getSelectedItem()
        if not item then
            return
        end
        local actions = config.getParameter("detailCanvas.actions."..self.getState())

        util.each(actions, function(i,v) 
            return comp[v[1]](self.detailCanvas, v[2], v[3])
        end)
    end

    self.clearPortrait = function()
        self.portraitCanvas:clear()
    end
    widget.setItemSlotItem("detailArea.importItemSlot", config.getParameter("npcItem"))
end


function update(dt)
    self.timers:update(dt)
end

function dismissed()
    world.sendEntityMessage(pane.sourceEntity() or -1, "colonyManager.die")
    world.sendEntityMessage(player.id(), "npcinjector.onPaneDismissed")
end

function uninit()

end

function onImportItemSlotInteraction(id, data)

    local fullPath = "detailArea."..id
    local item = player.swapSlotItem() or {}
    local stagehandId = config.getParameter("stagehandId", -1)
    local tenant
    if hasPath(item, data.verifyPath) then

        widget.setItemSlotItem(fullPath, item)
        tenant = self[data.extractDataFunc](fullPath)

        util.debugLog("tenantInfo %s", sb.printJson(tenant, 1))

        world.sendEntityMessage(stagehandId, "addTenants", {tenant})
        pane.dismiss()
        return
    end
end

function tenantFromNpcCard(item)
    if type(item) == "string" then
        item = widget.itemSlotItem(item)
    end
    --local npcArgs = item.parameters.npcArgs
    if hasPath(item.parameters.npcArgs, {"npcParam", "scriptConfig", "personality","storedOverrides"}) then
        item.parameters.npcArgs.npcParam.scriptConfig.personality.storedOverrides = nil
    end
    local npcArgs = item.parameters.npcArgs
    return {
        spawn = "npc",
        species = npcArgs.npcSpecies or npcArgs.npcParam.identity.species,
        type = npcArgs.npcType,
        seed = npcArgs.npcSeed,
        overrides = copy(npcArgs.npcParam)
    }
end

function tenantFromCapturePod(item)
    if type(item) == "string" then
        item = widget.itemSlotItem(item)
    end
    local pet = item.paramets.pets[1]
    return {
        spawn = "monster",
        type = pet.config.type,
        overrides = copy(pet.config.parameters)
    }
end

function RemoveTenant(id, data)
    local npcUuid = self.selectedInstanceValue("tenant.uniqueId")
    local spawn = self.selectedInstanceValue("tenant.spawn")

    world.sendEntityMessage(config.getParameter("stagehandId", -1), "removeTenant", npcUuid, spawn)
    pane.dismiss()
end


function onTenantListItemPressed(id, data)
    id = data.itemId
    local item = listManager.items[id]
    if data.clickSound then
        widget.playSound(data.clickSound)
    end
    util.each(listManager.items, function(iId, v)
        v.checked = false
    end)
    item.checked = true
    
    util.each(listManager.items, function(iId, v)
        widget.setChecked(v.toggleButton, v.checked)
        widget.setButtonEnabled(v.toggleButton, not v.checked)
    end)

    listManager:setSelectedItem(id)
    if item.isCreateNewItem then
        self.setState("selectNew")
    else
        self.setState("selectTenant")
    end
end


function updateWidgets(state)
    state = state or self.getState()

    util.each(self.configParam("widgetsToCheck"),  function(widgetName, dataPath)
                    
        local queue = applyDefaults(self.configParam(widgetName.."."..state, {}), self.configParam(widgetName..".default", {}))
        util.debugJson(queue, "onStageChangeQueue:  %s", 1)
        for k,v in pairs(queue) do
            local args = comp[v[1]](v[2], v[3])
            if widget[k] then
                --util.debugJson(v, "v:  %s", 1)
                if type(args) == "table" then
                    util.debugLog("\ndatapath/args: %s %s %s",k, dataPath, args)
                    widget[k](dataPath, table.unpack(args))
                else
                    util.debugLog("\ndatapath/args: %s %s %s",k, dataPath, args)
                    --return false
                    widget[k](dataPath, args)
                end
            end
        end
    end)
    self.drawDetails()
    self.drawPortrait()
end

function paneAliveReminder()
    
end

function delayStagehandDeath()
 
end

function checkIfAlive()
    if not world.entityExists(config.getParameter("stagehandId", -1)) then
        pane.dismiss()
    end
end

function hasPath(data, keyList, index, total)
    if not index then
        index = 1
        total = math.max(#keyList, 1)
    end
    if index > total then
      return true
    else
      local firstKey = keyList[index]
      if data[firstKey] ~= nil then
        return hasPath(data[firstKey], keyList, index+1, total)
      else
        return false
      end
    end
  end

if not util then util = {} end

function util.debugJson(luaValue, format, spacing)
    return self.debug and sb.logInfo(format or "%s", sb.printJson(luaValue, spacing and 1 or 0))
end
