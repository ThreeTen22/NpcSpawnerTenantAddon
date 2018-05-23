require "/objects/spawner/colonydeed/timer.lua"
require "/scripts/vec2.lua"
require "/scripts/messageutil.lua"
storage = storage or {}

listManager = {}
listManager.__index = listManager

function listManager.new(...)
    local self = {}
    setmetatable(self, listManager)
    self:init(...)
    return self
end

function listManager:init(tenants)
    self.items = {}
    self.itemNameByIndex = {}
    self.listPath = "tenantScrollArea.list"
    self.template = {}
    self.template.canvas = "portraitCanvas"
    
    local item = nil

    for i = 1, 5 do
        item = widget.addListItem(self.listPath)
      
        local tenant = tenants[i] or {}
        
        self.items[item] = {
            canvas = widget.bindCanvas(string.format("%s.%s.%s",self.listPath, item, self.template.canvas)),
            tenant = tenant
        }
        table.insert(self.itemNameByIndex, item)
    end

    local itemPortraitPosition = {10, 5}
    local itemSize = {100, 20}
    local itemTextPosition = {30, 9} 

    --using filter due to ipair, don't need new list
    util.each(self.itemNameByIndex, 
    function(i, v)
        local v = self.items[v]
        v.canvas:clear()
        v.canvas:drawRect({0,0,itemSize[1], itemSize[2]}, "black")
        if isEmpty(v.tenant) then
            v.canvas:drawText("-- Empty -- ", {position = itemTextPosition, horizontalAnchor="left", verticalAnchor="mid"}, 8)
            return
        end
        --DEBUG: REPLACE WITH IMAGE
        
        v.canvas:drawText(v.tenant.overrides.identity.name, {position = itemTextPosition, horizontalAnchor="left", verticalAnchor="mid"}, 8)

        local imageSize = root.imageSize(v.tenant.npcinjector.portraits.bust[1].image)
        for _,portrait in ipairs(v.tenant.npcinjector.portraits.bust) do
            v.canvas:drawImageDrawable(portrait.image, vec2.add(itemPortraitPosition, portrait.position), 1.0, portrait.color)
        end 
        
    end)
end


--[[
    imageSize   =   20
    1.0              y
]]

function init()
    self.timers = TimerManager:new()

    self.delayStagehandDeath = Timer:new("delayStagehandDeath", {
        delay = 2,
        completeCallback = delayStagehandDeath,
        loop = true
      })

    self.delayPaneDeath = Timer:new("delayPaneDeath", {
        delay = 0.5,
        completeCallback = delayPaneDeath,
        loop = true
    })
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
end

function dismissed()
    world.sendEntityMessage(config.getParameter("stagehandId", -1), "paneDismissed")
    world.sendEntityMessage(player.id(), "npcinjector.onPaneDismissed")
end

function uninit()
    --dismissed()
end

function delayPaneDeath()

end

function delayStagehandDeath()
    local stagehandId = config.getParameter("stagehandId")
    promises:add(world.sendEntityMessage(stagehandId, "delayDeath"), nil, function() pane.dismiss() end)
end