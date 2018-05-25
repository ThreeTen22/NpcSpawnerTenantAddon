require "/objects/spawner/colonydeed/timer.lua"
require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/messageutil.lua"
storage = storage or {}

listManager = {}
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

comp.eq = function(v1, v2) return comp.resolve(v1) == comp.resolve(v2) end
comp.ne = function(v1, v2) return comp.resolve(v1) ~= comp.resolve(v2) end
comp.gt = function(v1, v2) return comp.resolve(v1) >  comp.resolve(v2) end
comp.ge = function(v1, v2) return comp.resolve(v1) >= comp.resolve(v2) end
comp.lt = function(v1, v2) return comp.resolve(v1) <  comp.resolve(v2) end
comp.le = function(v1, v2) return comp.resolve(v1) <= comp.resolve(v2) end
comp.set = function(_, v2) return comp.resolve(v2) end

comp.contains = function(v1, v2) 
    v1 = comp.resolve(v1)
    v2 = comp.resolve(v2)
    if type(v1) == "table" then
        return contains(v1, v2)
    end
end


comp.drawText = function(canvas, text, args) args = comp.resolve(args); return canvas:drawText(comp.resolve(text), args.textPositioning, args.fontSize, args.fontColor) end 

function comp.result(fullPath, state, key) 

    
    local comparison = config.getParameter(string.format("%s.%s.%s", fullPath, state, key), config.getParameter(fullPath.."."..state))
    
    if type(comparison) == "string" then 
        comparison = config.getParameter(string.format("%s.%s", comparison, key)) 
    end
   
    
    if type(comparison) ~= "table" then
        return false
    end
    local output = false
    local compareType = "compare"
    local successes = util.filter(comparison, function(args)
        compareType = args[1]
        return comp[args[3]](args[2], args[4])
    end)

    if #successes == #comparison then
        output = true
    elseif #successes > 0 and compareType == "anyof" then
        output = true
    end
    return output
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
    self.config = root.npcConfig(self.type)
end

function Tenant:getPortrait(type)
    if self.dataSource == "config" then
        local path = string.format("tenantPortraits.%s.%s", self.jsonIndex, type)
        return config.getParameter(path)
    end
end

function Tenant:instanceValue(jsonPath, default)
    return self[jsonPath] or sb.jsonQuery(self.overrides, jsonPath) or sb.jsonQuery(self.config, jsonPath) or default
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
    self.listPath = "tenantScrollArea.list"
    self.template = {}
    self.template.canvas = "portraitCanvas"
    self.template.portraitSlot = "portraitSlot"
    self.template.toggleButton = "background"
    widget.registerMemberCallback(self.listPath, "onListItemPressed", onListItemPressed)
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
            tenant = Tenant.fromConfig(math.max(i-1, 0)),
            isCreateNewItem = false
        }
        
        items.checked = widget.getChecked(items.toggleButton)
        if not items.tenant then
            items.isCreateNewItem = true
        end
        self.items[itemId] = items
        widget.setData(items.toggleButton, {itemId = items.itemId})
        
       -- sb.logInfo("listManagerInit isCreateNewItem- %s", self.items[itemId].isCreateNewItem )
        table.insert(self.itemIdByIndex, itemId)

    end

    --local firstItem = self.items[self.itemIdByIndex[1]]
    

    local itemPortraitPosition = {15, 5}
    local itemSize = {100, 20}
    local itemTextPosition = {30, 9} 


    util.each(self.itemIdByIndex, 
    function(i, k)
        local v = self.items[k]
        local iconItem = config.getParameter("npcItem")
        v.canvas:clear()

        if v.isCreateNewItem then
            v.canvas:drawText("Add Tenant", {position = itemTextPosition, horizontalAnchor="left", verticalAnchor="mid"}, 8)
            widget.setItemSlotItem(v.portraitSlot, iconItem)
            return
        end

        v.canvas:drawText(v.tenant.overrides.identity.name, {position = itemTextPosition, horizontalAnchor="left", verticalAnchor="mid"}, 8)
        iconItem.parameters.inventoryIcon = v.tenant:getPortrait("head")
        widget.setItemSlotItem(v.portraitSlot, iconItem)
    end)
end

function listManager:setSelectedItem(id)
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

function init()
    self.timers = TimerManager:new()
    self.HandItemName = "npcinjector"
    self.debug = true

    self.delayStagehandDeath = Timer:new("delayStagehandDeath", {
        delay = 2,
        completeCallback = delayStagehandDeath,
        loop = true
      })

    self.paneAliveCooldown = Timer:new("paneAliveCooldown", {
        delay = 0.5,
        completeCallback = doNothing,
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
        if type(name) ~= "table" and widget[name] then
            table.remove(args[1], 1)
            return widget[name](table.unpack(args))
        end
    end
    
    self.getState = function()
        return self.state
    end

    self.setState = function(state)
        self.state = state
        return self.onStateChange(state)
    end

    self.onStateChange = function(state)
        updateWidgets(state)
    end

    self.hasSelectedListItem = function()
        if listManager.selectedItemId then
            return true
        end
        return false
    end

    self.selectedInstanceValue = function(jsonPath, default)
        local itemId = listManager.selectedItemId
        if itemId then
            return listManager:itemInstanceValue(itemId, jsonPath, default)
        end
        return default
    end

    self.configParam = function(configPath, default)
        return config.getParameter(configPath, default)
    end

    self.selectedOption = function(widgetPath)
        return widget.getSelectedOption(widgetPath)
    end
    
    self.detailCanvas = widget.bindCanvas("detailArea.detailCanvas")
    self.portraitCanvas = widget.bindCanvas("detailArea.portraitCanvas")

    self.drawPortrait = function()
        self.portraitCanvas:clear()
        local center = config.getParameter("portraitCanvas.center")
        local item = self.getSelectedItem()
        local drawParam
        if item then
            if item.tenant then
                local portrait = item.tenant:getPortrait("full")
                drawParam = config.getParameter("portraitCanvas.drawImage."..item.tenant:instanceValue("spawn"))
                for i,drawable in ipairs(portrait) do
                    self.portraitCanvas:drawImage(drawable.image, vec2.add(center, drawable.position), drawParam.scale, drawable.color, drawParam.centered)
                end
                return true
            end
            --drawParam = config.getParameter("portraitCanvas.drawImage.newTenant")
            --self.portraitCanvas:drawImage(drawParam.image, center, drawParam.scale, drawParam.color, drawParam.centered)
        end
    end

    self.drawDetails = function()
        self.detailCanvas:clear()
        local item = self.getSelectedItem()
        if not item then
            return
        end
        local actions = config.getParameter("detailCanvas.actions."..self.getState())
        --[[
        if item.isCreateNewItem and not item.tenant then
            actions = config.getParameter("detailCanvas.actions.newTenant")
        else
            actions = config.getParameter("detailCanvas.actions.modify"..item.tenant:instanceValue("spawn"))
        end
        --]]
        util.each(actions, function(i,v) 
            return comp[v[1]](self.detailCanvas, v[2], v[3])
        end)
    end

    self.clearPortrait = function()
        self.portraitCanvas:clear()
    end
    widget.setItemSlotItem("detailArea.importItemSlot", config.getParameter("npcItem"))
    self.oneRun = false
end


function update(dt)
    self.timers:update(dt)
    local currentPosition = world.entityPosition(player.id())
    local distance = world.distance(currentPosition, config.getParameter("stagehandPosition"))
    if not self.oneRun then
        --onSelectTenantListItem()
        self.oneRun = true
    end

    if vec2.mag(distance) > 20 then
        pane.dismiss()
    end
    local currentHandItem = player.primaryHandItem().name
    if self.prevHandItemName ~= "npcinjector" and currentHandItem == "npcinjector" and not self.paneAliveCooldown:active() then
        paneAliveReminder()
        self.paneAliveCooldown:start()
    end
    self.prevHandItemName = currentHandItem
end

function dismissed()
    world.sendEntityMessage(config.getParameter("stagehandId", -1), "paneDismissed")
    world.sendEntityMessage(player.id(), "npcinjector.onPaneDismissed")
end

function uninit()
    --dismissed()
end

function onImportItemSlotInteraction(id, data)
    local fullPath = "detailArea."..id
    local item = player.swapSlotItem()
    
    if item and item.parameters and item.parameters.npcArgs then
        if data == "npc" then
            widget.setItemSlotItem(fullPath, player.swapSlotItem())
            local tenant = tenantFromNpcCard(fullPath)
            util.debugLog("tenantInfo %s", sb.printJson(tenant, 1))
            world.sendEntityMessage(config.getParameter("stagehandId", -1), "addTenants", {tenant})
        end
        pane.dismiss()
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

function RemoveTenant(id, data)
    local npcUuid = self.selectedInstanceValue("tenant.uniqueId")
    local spawn = self.selectedInstanceValue("tenant.spawn")

    world.sendEntityMessage(config.getParameter("stagehandId", -1), "removeTenant", npcUuid, spawn)
    pane.dismiss()
end


function onListItemPressed(id, data)
    id = data.itemId
    local item = listManager.items[id]
    local checked = widget.getChecked(item.toggleButton)
    if checked == true and item.checked ~= true then
        util.each(listManager.items, function(iId, v)
            if iId ~= id then
                v.checked = false
            end
        end)
        item.checked = checked

        util.each(listManager.items, function(iId, v)
            widget.setChecked(v.toggleButton, v.checked)
            widget.setButtonEnabled(v.toggleButton, not v.checked)
        end)
        listManager:setSelectedItem(id)
    end
    if item.isCreateNewItem then
        self.setState("selectNew")
    else
        self.setState("selectTenant")
    end
end


function updateWidgets(state)

    state = state or self.getState()
    local widgetsToCheck = config.getParameter("widgetsToCheck")

    local checks = {}
    util.each(widgetsToCheck, function(key,tableKeys)
        widgetsToCheck[key].fullPath = config.getParameter(key..".fullPath")
    end)

    util.each(widgetsToCheck, function(key, tableKeys)
       for i,v in ipairs(tableKeys) do
        local compareResult = comp.result(key, state, v)
        widget[v](tableKeys.fullPath, compareResult)
       end
    end)
    self.drawDetails()
    self.drawPortrait()
end

function paneAliveReminder()
    local stagehandId = config.getParameter("stagehandId")
    local deedId = config.getParameter("deedId")
    world.sendEntityMessage(player.id(), "npcinjector.paneAlive", stagehandId, deedId)
end

function delayStagehandDeath()
    local stagehandId = config.getParameter("stagehandId")
    promises:add(world.sendEntityMessage(stagehandId, "delayDeath"), nil, function() pane.dismiss() end)
end

function doNothing()
end

function hasPath(data, keyList, index, total)
    if not index then
        index = 1
        total = math.max(#keyList, 1)
    end
    if index >= total then
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