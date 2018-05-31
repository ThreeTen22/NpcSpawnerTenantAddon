require "/scripts/messageutil.lua"

function init()
    --if not storage then storage = {} end
    self.debug = false
    self.deedUuid = config.getParameter("deedUuid")
    self.deedId = config.getParameter("deedId")
    self.playerUuid = config.getParameter("playerUuid")
    self.playerId = config.getParameter("playerId")
   
    self.timers = TimerManager:new()


    self.deedCheckup = Timer:new("deedCheckup", {
        delay = 0.2,
        completeCallback = updateSelf,
        loop = true
    })
    self.deedCheckup:start()
    self.timers:manage(self.deedCheckup)
    
    --message.setHandler("delayDeath", function(...) self.deathTimer:reset() return true end)
    message.setHandler("onPaneDismissed", function(...) stagehand.die() end)
    message.setHandler("colonyManager.die", function(...) stagehand.die() end)
    message.setHandler("getTenants", simpleHandler(getTenants))
    message.setHandler("addTenants", simpleHandler(addTenants))
    message.setHandler("replaceTenants", simpleHandler(replaceTenants))
    message.setHandler("removeTenant", simpleHandler(removeTenant))
    message.setHandler("setDeedConfig", simpleHandler(setDeedConfig))
    
end

function update(dt)
    promises:update()
    self.timers:update(dt)
    if promises:empty() then
        if self.deedId == ""
        or self.playerUuid == "" then
            sb.logError("colonyManager:  init deedUuid or playerUuid was not provided: \n or deed does not belong to player")
            return stagehand.die()
        end
        if world.getObjectParameter(self.deedId, "owner") ~= self.playerUuid then
            world.callScriptedEntity(self.deedId, "object.say", "This deed does not belong to you.")
            world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandFailed", {reason="notOwner"})
            return stagehand.die()
        end
        
        local tenants = getTenants()

        if #tenants == 0 then
            world.callScriptedEntity(self.deedId, "object.say", "This deed requires a valid house with at least one tenant before modification can occur.")
            world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandFailed", {reason="notOccupied"})
            return stagehand.die()
        end
        local entityId = nil
        local tenantPortraits = {}
        local typeConfig = {}
        for i,v in ipairs(tenants) do
            entityId = world.loadUniqueEntity(tenants[i].uniqueId)
            --sb.logInfo("entityID: %s",entityId)
            tenantPortraits[i] = {}
            
            tenantPortraits[i].full = world.entityPortrait(entityId, "full")
            tenantPortraits[i].head = world.entityPortrait(entityId, "head")
            tenantPortraits[i].bust = world.entityPortrait(entityId, "bust")

            if v.spawn == "npc" then
                if not typeConfig[v.type] then
                    typeConfig[v.type] = root.npcConfig(v.type)
                end
            else
                if not typeConfig[v.type] then
                    typeConfig[v.type] = root.monsterParameters(v.type)
                end
            end

        end
        sb.logInfo(sb.printJson(tenants, 1))

        promises:add(world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandSuccess",entity.id(), tenants, tenantPortraits, typeConfig), 
        function()
            self.state = "main"
        end,
        function()
            sb.logError("npcinjector.onStagehandSuccess failed")
            stagehand.die()
        end)
    end
    update = mainUpdate
end

function mainUpdate(dt)
    promises:update()
    self.timers:update(dt)
end

function uninit()
    stagehand.die()
end

function updateSelf()
    util.debugLog("updateSelf..init")
    local live = false
    local playerPos = world.entityPosition(self.playerId)

    if isDeedAlive() and playerPos then
        if world.magnitude(playerPos, config.getParameter("deedPosition")) < 20 then
            live = true
        end
    end
    if live then 
        stagehand.setPosition(playerPos)
    else
        stagehand.die()
    end
    util.debugLog("updateSelf Result:  %s  %s", live, playerPos)
end

function isDeedAlive()
    if world.entityExists(self.deedId or -1) then
        return true
    end
    return false
end
--Need to set the deed config to a value so it will be changeable again...for some reason setting parameters on tables is having issues
function setDeedConfig(configItem)
    if world.entityExists(self.deedId or -1) then
        world.callScriptedEntity(self.deedId, "object.setConfigParameter", "deed", configItem)
        world.callScriptedEntity(self.deedId, "init")
    end
end

function isPlayerAlive()
    if world.findUniqueEntity(self.playerUuid):result() then
        return true
    end
    return false
end

--WARNING:  THIS DIRECTLY MODFIES THE STORAGE TABLE ON THE COLONY DEED. DONT FUCK WITH THIS! (who knew you could directly reference other entity's enviroment tables...)

function removeTenant(tenantUuid, spawn, shouldDie)

    local tenants =  getTenants()

    table.sort(tenants, function(i,j) 
        return i.spawn > j.spawn
    end)

    local entityId = world.loadUniqueEntity(tenantUuid)
    --util.debugLog(sb.printJson(v or "nil"))
    if entityId ~= 0 then
        --world.callScriptedEntity(self.deedId, "detachTenant", v)
        world.callScriptedEntity(entityId, "tenant.detachFromSpawner")
        world.callScriptedEntity(entityId, "tenant.evictTenant")
        
    end

    if shouldDie then
        stagehand.die()
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

function addTenants(tenantArray, shouldDie)
    tenantArray = tenantArray or {}
    if self.state == "main" and isDeedAlive() then
        local deedId = self.deedId
        for i,v in ipairs(tenantArray) do
                world.callScriptedEntity(deedId, "addTenant", v)
        end
    end
    if shouldDie then
        stagehand.die()
    end
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