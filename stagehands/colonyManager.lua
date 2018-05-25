require "/scripts/messageutil.lua"
function init()

    self.deedUuid = config.getParameter("deedUuid")
    self.deedId = config.getParameter("deedId")
    self.playerUuid = config.getParameter("playerUuid")
    self.state = "init"

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



    message.setHandler("delayDeath", function(...) self.deathTimer:reset() return true end)
    message.setHandler("onPaneDismissed", function(...) die() end)
    message.setHandler("getTenants", simpleHandler(getTenants))
    message.setHandler("addTenants", simpleHandler(addTenants))
    message.setHandler("replaceTenants", simpleHandler(replaceTenants))
    message.setHandler("removeTenant", simpleHandler(removeTenant))
end

function update(dt)
    promises:update()
    self.timers:update(dt)
    if self.state == "main" then
        mainUpdate(dt)
    elseif self.state == "init" then
        if promises:empty() then
            if self.deedId == "" 
            or self.playerUuid == "" then
                sb.logError("colonyManager:  init deedUuid or playerUuid was not provided: \n or deed does not belong to player")
                return die()
            end
            if world.getObjectParameter(self.deedId, "owner") ~= self.playerUuid then
                world.callScriptedEntity(self.deedId, "object.say", "This deed does not belong to you.")
                world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandFailed", {reason="notOwner"})
                return die()
            end

            if world.callScriptedEntity(self.deedId, "isOccupied") then
                world.callScriptedEntity(self.deedId, "respawnTenants")
            else
                world.callScriptedEntity(self.deedId, "scanVacantArea")
            end
            local tenants = getTenants()
            local id = entity.id()

            if #tenants == 0 then
                world.callScriptedEntity(self.deedId, "object.say", "This deed requires a valid house with at least one tenant before modification can occur.")
                world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandFailed", {reason="notOccupied"})
                return die()
            end
            local entityId = nil
            local tenantPortraits = {}
            for i,v in ipairs(tenants) do
                entityId = world.loadUniqueEntity(tenants[i].uniqueId)
                --sb.logInfo("entityID: %s",entityId)
                tenantPortraits[i] = {}
                
                tenantPortraits[i].full = world.entityPortrait(entityId, "full")
                tenantPortraits[i].head = world.entityPortrait(entityId, "head")
            end
            --sb.logInfo(sb.printJson(tenants, 1))
            promises:add(world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandSuccess",id, tenants, tenantPortraits), 
            function()
                self.state = "main"
                update = mainUpdate
            end,
            function()
                sb.logError("npcinjector.onStagehandSuccess failed")
                return die()
            end)
        end
    end
end

function mainUpdate(dt)
    if not isDeedAlive() then
        sb.logInfo("colonyManager.mainUpdate:  dying")
        die()
    end
    promises:update()
    self.timers:update(dt)
end

function die()
    stagehand.die()
end

function uninit()
    die()
end

function isDeedAlive()
    if world.entityExists(self.deedId or -1) and world.entityName(self.deedId) == "colonydeed" then
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

function removeTenant(tenantUuid, spawn)
    local entityId = world.loadUniqueEntity(tenantUuid)
    if entityId ~= 0 then
        world.callScriptedEntity(entityId, "tenant.detachFromSpawner")
        world.callScriptedEntity(entityId, "tenant.evictTenant")
    end
end

function getTenants()
    if isDeedAlive() then
        local deedId = self.deedId
        local tenants = world.callScriptedEntity(deedId, "getTenants")
        return tenants
    end
    return {}
end

function addTenants(tenantArray)
    if self.state == "main" and isDeedAlive() then
        local deedId = self.deedId
        for i,v in ipairs(tenantArray) do
            local copiedV = copy(v)
            if copiedV then
            --sb.logInfo("colonyManager %s", sb.printJson(copiedV, 1))
                world.callScriptedEntity(deedId, "addTenant", v)
            end
        end
    end
end

function replaceTenants(tenant)
    local uniqueId = tenant.uniqueId

end

function copy(v)
    if type(v) ~= "table" then
      return v
    else
      local c = {}
      for k,v in pairs(v) do
        c[k] = copy(v)
      end
      setmetatable(c, getmetatable(v))
      return c
    end
end