require "/objects/spawner/colonydeed/timer.lua"
require "/scripts/vec2.lua"
require "/scripts/messageutil.lua"
storage = storage or {}

listManager = {}
listManager.__index = listManager

Tenant = {}
Tenant.__index = Tenant

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
end

function Tenant:getPortrait(type)
    sb.logInfo("tenant.getPortrait tenantPortraits.%s.%s",self.jsonIndex, type)
    if self.dataSource == "config" then
        local path = string.format("tenantPortraits.%s.%s", self.jsonIndex, type)
        return config.getParameter(path)
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
    self.listPath = "tenantScrollArea.list"
    self.template = {}
    self.template.canvas = "portraitCanvas"
    self.template.portraitSlot = "portraitSlot"


    local itemId = nil

    for i = 1, math.min(#tenants+1, 5) do
        itemId = widget.addListItem(self.listPath)
      
        local tenant = tenants[i] or {}
        
        self.items[itemId] = {
            canvas = widget.bindCanvas(string.format("%s.%s.%s",self.listPath, itemId, self.template.canvas)),
            portraitSlot = string.format("%s.%s.%s",self.listPath, itemId, self.template.portraitSlot),
            listItemPath = string.format("%s.%s", self.listPath, itemId),
            listItemIndex = i,
            tenant = Tenant.fromConfig(math.max(i-1, 0)),
            isCreateNewItem = false
        }
        self.items[itemId].isCreateNewItem = not (self.items[itemId].tenant and true)
        sb.logInfo("listManagerInit isCreateNewItem- %s", self.items[itemId].isCreateNewItem )
        table.insert(self.itemIdByIndex, itemId)
    end

    --local firstItem = self.items[self.itemIdByIndex[1]]
    

    local itemPortraitPosition = {15, 5}
    local itemSize = {100, 20}
    local itemTextPosition = {30, 9} 


    util.each(self.itemIdByIndex, 
    function(i, k)
        local v = self.items[k]
        local iconItem = config.getParameter("iconItem")
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


--[[
    imageSize   =   20
    1.0              y
]]

function init()
    self.timers = TimerManager:new()
    self.prevHandItemName = "npcinjector"

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
end

function update(dt)
    self.timers:update(dt)
    local currentPosition = world.entityPosition(player.id())
    local distance = world.distance(currentPosition, config.getParameter("stagehandPosition"))

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