require "/scripts/messageutil.lua"
function init()

    self.deedUuid = config.getParameter("deedUuid")
    self.playerUuid = config.getParameter("playerUuid")
    self.state = "init"
    if self.deedUuid == "" or self.playerUuid == "" then
        sb.logError("colonyManager:  init deedUuid or playerUuid was not provided: \n deedUuid: %s\nplayerUuid: %s", self.deedUuid, self.playerUuid)
        die()
    end

    self.timers = TimerManager:new()

    self.deathTimer = Timer:new("deathTimer", {
        delay = 5.0,
        completeCallback = die,
        loop = false
      })
    if not self.deathTimer:active() then
      self.deathTimer:start()
    end

    self.timers:manage(self.deathTimer)



    message.setHandler("delayDeath", function(...) self.deathTimer:reset() end)
    message.setHandler("getTenants", simpleHandler(getTenants))
    message.setHandler("addTenants", simpleHandler(addTenants))
    message.setHandler("replaceTenants", simpleHandler(replaceTenants))
end

function update(dt)
    promises:update()
    self.timers:update(dt)
    if self.state == "main" then
        mainUpdate(dt)
    elseif self.state == "init" then
        if promises:empty() then
            local tenants = getTenants()
            local id = entity.id()
            promises:add(world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandSuccess",id, tenants), 
            function()
                self.state = "main"
                update = mainUpdate
            end,
            function()
                return die()
            end)
        end
    end
end

function mainUpdate(dt)
    if not isDeedAlive() then
        die()
    end
    promises:update()
    self.timers:update(dt)
end

function die()
    stagehand.die()
end

function uninit()
end

function isDeedAlive()
    if world.findUniqueEntity(self.deedUuid):result() then
        return true
    end
    return false
end

function isPlayerAlive()
    if world.findUniqueEntity(self.playerUuid):result() then
        return true
    end
    return false
end

function getTenants()
    if isDeedAlive() then
        local deedId = world.loadUniqueEntity(self.deedUuid)
        local tenants = world.callScriptedEntity(deedId, "getTenants")
        return tenants
    end
    return {}
end

function addTenants(tenantArray)
    if isDeedAlive() then
        local deedId = world.loadUniqueEntity(self.deedUuid)
        for i,v in ipairs(tenantArray) do
            world.callScriptedEntity(deedId, "addTenant", v)
        end
    end
end

function replaceTenants(tenant)
    local uniqueId = tenant.uniqueId

end