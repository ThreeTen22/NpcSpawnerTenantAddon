require "/objects/spawner/colonydeed/timer.lua"
require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/scripts/messageutil.lua"
require "/interface/scripted/deedmenu/tenantclass.lua"
require "/interface/scripted/deedmenu/listmanager.lua"
storage = storage or {}

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
--[[
comp.list -
if v2 = null, return true if 
    v1: nil --- v2: null
    v1: not a table --- v2: null
(same as using "ne", so use that).  
if v2 = boolean, return true if  
    v1: exists--- v2: true
if v2 = number, return true if
    v1 exists, is a table, and #v1 == v2
--]]
comp.table = function(v1, v2, v3)

    v2 = comp.resolve(v2)
    v3 = comp.resolve(v3)
    local v2Type = type(v2)
    local v3Type = type(v3)

    if v3Type == "number" then
        if v2Type == "table" then
            return comp[v1](#v2, v3)
        end
    elseif v3Type == "boolean" then
        if v2Type == "table" then
            return comp[v1](not v2,not v3)
        end
    elseif v3Type == "nil" then
        if v2Type == "table" then
            return comp[v1](v2,v3)
        end
    end
    return false
end
comp.set = function(v1, v2) 
    v1, v2 = comp.resolve(v1), comp.resolve(v2)
    if type(v1) ~= "nil" then
        return v1
    end
    return v2
end

comp["and"] = function(v1, v2)
    local key1 = table.remove(v1, 1)
    local key2 = table.remove(v2, 1)
    return comp[key1](table.unpack(v1)) and comp[key2](table.unpack(v2))
end

comp["or"] = function(v1, v2)
    local key1, key2 = table.remove(v1, 1), table.remove(v2)
    return comp[key1](table.unpack(v1)) and comp[key2](table.unpack(v2))
end

comp.contains = function(v1, v2) 
    v1 = comp.resolve(v1)
    v2 = comp.resolve(v2)
    if type(v1) == "table" then
        return contains(v1, v2)
    end
end

comp.compare = function(v1, v2) end

comp.drawText = function(canvas, text, args) 
    args = comp.resolve(args)
    return canvas:drawText(comp.resolve(text), args.textPositioning, args.fontSize, args.fontColor) 
end 

function comp.result(fullPath, state, key) 

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

    self.paneAliveCooldown = Timer:new("paneAliveCooldown", {
        delay = 0.5,
        completeCallback = checkIfAlive,
        loop = false
    })
    self.timers:manage(self.paneAliveCooldown)

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
        return updateWidgets(state)
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

    self.selectedTenant = function()
        local item = listManager:getSelectedItem()
        if not item then return nil end
        return item.tenant
    end
    self.selectedTenantInstanceValue = function(jsonPath, default)
        local item = listManager:getSelectedItem()
        if not item then return default end
        return item.tenant:instanceValue(jsonPath)
    end
    self.selectedTenantOverrideValue = function(jsonPath, default)
        local item = listManager:getSelectedItem()
        if not item then return default end
        return sb.jsonQuery(item.tenant.overrides, jsonPath)
    end
    self.selectedTenantConfigValue = function(jsonPath, default)
        local item = listManager:getSelectedItem()
        if not item then return default end
        return item.tenant:getConfig(jsonPath)
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
        local actions = config.getParameter("detailCanvas.actions."..self.getState(), {})

        util.each(actions, function(i,v) 
            return comp[v[1]](self.detailCanvas, v[2], v[3])
        end)
    end

    self.clearPortrait = function()
        self.portraitCanvas:clear()
    end

    self.listManagerInit = function()
        return listManager:init(config.getParameter("tenants"))
    end

    widget.setItemSlotItem("detailArea.importItemSlot", config.getParameter("npcItem"))

    self.setState("selectNone")

    widget.setChecked("detailArea.requireFilledBackgroundButton",
    world.getObjectParameter(
        config.getParameter("deedId"), 
        widget.getData("detailArea.requireFilledBackgroundButton")
    ))
    self.tenantFromNpcCard = tenantFromNpcCard
    self.tenantFromCapturePod = tenantFromCapturePod

    --DEBUG:
end

function update(dt)
    promises:update(dt)
    self.timers:update(dt)
end

function dismissed()
    world.sendEntityMessage(pane.sourceEntity() or -1, "colonyManager.die")
end

function uninit()

end


function SetDeedConfig(id, data)
    id = config.getParameter(id..".fullPath")
    local checked = widget.getChecked(id)
    local path = util.split(data, ".")
    local changes = {
        [path[1]] = world.getObjectParameter(pane.sourceEntity(), path[1])
    }

    jsonSetPath(changes, data, checked)
    
    world.sendEntityMessage(pane.sourceEntity(), "setDeedConfig", copy(changes[path[1]]))

end

function onModifyTenantButtomPressed(id, data)
    if self.getState() == "modifyTenant" then
        return self.setState("selectTenant")
    end

    return self.setState("modifyTenant")
end

function onImportItemSlotInteraction(id, data)

    local fullPath = "detailArea."..id
    local item = player.swapSlotItem() or {}
    local stagehandId = pane.sourceEntity()
    local tenant
    if hasPath(item, data.verifyPath) then
        
        widget.setItemSlotItem(fullPath, item)
        tenant = self[data.extractFunc](player.swapSlotItem())
        --util.debugLog("tenantInfo %s", sb.printJson(tenant, 1))

        world.sendEntityMessage(stagehandId, "addTenant", tenant, true)
        --pane.dismiss()
        return
    end
end

function tenantFromCapturePod(item)
    if type(item) == "string" then
        item = widget.itemSlotItem(item)
    end
    local pet = item.parameters.pets[1]
    return {
        spawn = "monster",
        type = pet.config.type,
        overrides = copy(pet.config.parameters)
    }
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
    if hasPath(npcArgs, {"npcParam","scriptConfig", "uniqueId"}) then
        item.parameters.npcArgs.npcParam.scriptConfig.uniqueId = nil
    end

    return {
        spawn = "npc",
        species = npcArgs.npcSpecies or npcArgs.npcParam.identity.species,
        type = npcArgs.npcType,
        seed = npcArgs.npcSeed,
        overrides = copy(npcArgs.npcParam)
    }
end


function ExportNpcCard(id, data)
    local item = config.getParameter("templateCard")
    local tenant = self.getSelectedItem().tenant
    local args = tenant:toJson()


    item.parameters.shortdescription = args.overrides.identity.name
    item.parameters.inventoryIcon = tenant:getPortrait("bust")
    item.parameters.description = ""
    item.parameters.tooltipFields.collarNameLabel = "Created By:  "..world.entityName(player.id())
    item.parameters.tooltipFields.objectImage = tenant:getPortrait("full")
    item.parameters.tooltipFields.subtitle = args.type
    
    item.parameters.npcArgs = {
        npcSpecies = args.species,
        npcSeed = args.seed,
        npcType = args.type,
        npcLevel = args.level,
        npcParam = args.overrides
    }
    if player.swapSlotItem() then 
        player.giveItem(player.swapSlotItem()) 
    end
    player.setSwapSlotItem(item)
end

function SetTenantInstanceValue(id, data)
    id = config.getParameter(id..".fullPath")
    local tenant = listManager:getSelectedItem().tenant
    if not tenant then return end

    local checked = widget.getChecked(id) and "checkedValue" or "unCheckedValue"
    local value = data[checked]

    if value == "jarray" then
        tenant:setInstanceValue(data.path, jarray())
    else
        tenant:setInstanceValue(data.path, value)
    end

    widget.setButtonEnabled(id, false)
    promises:add(world.sendEntityMessage(pane.sourceEntity(), "setTenantInstanceValue", tenant.jsonIndex+1, tenant.overrides, data.path, value),
    function()
        widget.setButtonEnabled(id, true)
    end)

    util.debugLog("checked and value:  %s   %s", checked, value)
    --util.debugJson(data, true, "data:\n %s" )
    --util.debugJson(tenant.overrides.scriptConfig, true, "jsonValue:\n %s")
end


function RemoveTenant(id, data)
    local npcUuid = self.selectedInstanceValue("tenant.uniqueId")
    local spawn = self.selectedInstanceValue("tenant.spawn")

    world.sendEntityMessage(pane.sourceEntity(), "removeTenant", npcUuid, spawn, true)
end


function onTenantListItemPressed(id, data)
    id = data.itemId
    if data.clickSound then 
        widget.playSound(data.clickSound)
    end
    local item = listManager.items[id]
    local checkstatus = widget.getChecked(item.toggleButton)
    if data.clickSound then
        checkstatus = not checkstatus
    end
    
    util.each(listManager.items, function(iId, v)
        v.checked = false
    end)
    item.checked = checkstatus
    
    util.each(listManager.items, function(iId, v)
        widget.setChecked(v.toggleButton, v.checked)
    end)

    local checkCount = util.filter(listManager.itemIdByIndex, function(itemId)
        return listManager.items[itemId].checked == true
    end)

    listManager:setSelectedItem(checkCount[1])

    if not listManager:getSelectedItem() then
        self.setState("selectNone")
    elseif item.isCreateNewItem then
        self.setState("selectNew")
    else
        self.setState("selectTenant")
    end
end

function updateWidgets(state)
    state = state or self.getState()

    util.each(self.configParam("widgetsToCheck"),  function(widgetName, dataPath)
                    
        local queue = applyDefaults(self.configParam(widgetName.."."..state, {}), self.configParam(widgetName..".default", {}))
        
        for k,v in pairs(queue) do
            local key = table.remove(v, 1)
            local args = comp[key](table.unpack(v))
            if widget[k] then
                --util.debugJson(v, "v:  %s", 1)
                if type(args) == "table" then
                    --util.debugLog("\ndatapath/args: %s %s %s",k, dataPath, args)
                    widget[k](dataPath, table.unpack(args))
                else
                    --util.debugLog("\ndatapath/args: %s %s %s",k, dataPath, args)
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

function util.debugJson(luaValue, spacing, format)
    return self.debug and sb.logInfo(format or "%s", sb.printJson(luaValue, spacing and 1 or 0))
end
