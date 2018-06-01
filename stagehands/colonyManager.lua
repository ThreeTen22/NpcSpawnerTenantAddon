require "/scripts/messageutil.lua"
require "/interface/scripted/deedmenu/tenantclass.lua"

function init()
    --if not storage then storage = {} end
    self.debug = false
    --logENV()
    --self.deedUuid = config.getParameter("deedUuid") or world
    self.deedId = config.getParameter("deedId")
    self.playerUuid = config.getParameter("playerUuid")
    self.playerId = config.getParameter("playerId")
   
    self.timers = TimerManager:new()


    self.deedCheckup = Timer:new("deedCheckup", {
        delay = script.updateDt(),
        completeCallback = updateSelf,
        loop = true
    })
    self.deedCheckup:start()
    self.timers:manage(self.deedCheckup)

    self.respawnTenantsDelay = Timer:new("respawnTenants", {
        delay = 1.5,
        completeCallback = respawnTenants,
        loop = false
    })
    self.timers:manage(self.respawnTenantsDelay)
    
    message.setHandler("colonyManager.die", function(...) stagehand.die() end)
    message.setHandler("getTenants", simpleHandler(getTenants))
    message.setHandler("addTenant", simpleHandler(addTenant))
    message.setHandler("removeTenant", simpleHandler(removeTenant))
    message.setHandler("setDeedConfig", simpleHandler(setDeedConfig))
    message.setHandler("setTenantInstanceValue", simpleHandler(setTenantInstanceValue))
    self.hasScanned = false
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
        --check to see if the tenant has been scanned, if not, scan it to ensure its a grumble
        if #tenants == 0 and not self.hasScanned then
            world.callScriptedEntity(self.deedId, "scan")
            self.hasScanned = true
            return
        end
        
        local entityId = nil
        local tenantPortraits = {}
        local typeConfig = {}
  
        for i,v in ipairs(tenants) do
            entityId = world.loadUniqueEntity(tenants[i].uniqueId)
            if type(entityId) == "nil" or entityId == 0 then
                world.callScriptedEntity(self.deedId, "respawnTenants")
                return
            end
            --sb.logInfo("entityID: %s",entityId)
            tenantPortraits[i] = {}
            
            tenantPortraits[i].full = world.entityPortrait(entityId, "full")

            if isEmpty(tenantPortraits[i].full or {}) then
                return
            end
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
        --sb.logInfo(sb.printJson(tenants, 1))

        promises:add(world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandSuccess",entity.id(), tenants or {}, tenantPortraits or {}, typeConfig), 
        function()
            self.state = "main"
        end,
        function()
            sb.logError("npcinjector.onStagehandSuccess failed")
            stagehand.die()
        end)
        update = mainUpdate
    end
    
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
    stagehand.setPosition(playerPos)
    
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

function setTenantInstanceValue(index, tenant, jsonPath, value)
    local tenants = getTenants()
    local merged = sb.jsonMerge(tenants[index] or {}, tenant)
    tenants[index] = merged
    if value == "jarray" then value = jarray() end
    jsonSetPath(tenants[index].overrides, jsonPath, value) 
    local tenantId = world.loadUniqueEntity(tenants[index].uniqueId)
    if tenantId ~= 0 then
        world.callScriptedEntity(tenantId, "status.addEphemeralEffect", "beamoutanddie")
    end
    self.respawnTenantsDelay:start()
end

function respawnTenants()
    if world.entityExists(self.deedId) then
        world.callScriptedEntity(self.deedId, "respawnTenants")
    end
end

function isPlayerAlive()
    if world.findUniqueEntity(self.playerUuid):result() then
        return true
    end
    return false
end

--WARNING:  THIS DIRECTLY MODFIES THE STORAGE TABLE ON THE COLONY DEED. DONT FUCK WITH THIS! (who knew you could directly reference other entity's enviroment tables if passed to you...)

function removeTenant(tenantUuid, spawn, shouldDie)
    if isDeedAlive() then 
        local tenants = getTenants()

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
    end
    if shouldDie then
        stagehand.die()
    end
end

function getTenants()
    if isDeedAlive() then
        local tenants = world.callScriptedEntity(self.deedId, "getTenants")
        return tenants
    end
    return {}
end

function createVariant(tenant, useOverrides)
    if tenant.spawn == "npc" then
        if useOverrides == true then
            return pcall(root.npcVariant, tenant.species, tenant.type, 1, 1, tenant.overrides or {})
        else
            return pcall(root.npcVariant, tenant.species, tenant.type, 1)
        end
    end
end

function validateTenant(tenantJson)
    local spawning, tenant, species, crew
    --if new class isnt created then there is a problem with type

    spawning, tenant = pcall(Tenant.new, copy(tenantJson))
    if not spawning then
        return false, config.getParameter("spawningErrors.type")
    end
    spawning = true
    if tenant.spawn == "npc" then
        spawning, _ = createVariant(tenantJson)
        if not spawning then 
            return false, config.getParameter("spawningErrors.species")
        end

        --now check to see if there is proper dialogue, if not, add defaults.
        
    end
    
   
    return true, tenant:toJson()
end

function addTenant(tenantJson, shouldDie)
    if self.state == "main" and isDeedAlive() then

        local spawning, output = validateTenant(tenantJson)
        if spawning then 
            world.callScriptedEntity(self.deedId, "addTenant", output)
        else
            world.callScriptedEntity(self.deedId, "object.sayPortrait", output[1], output[2], {spawn=tenantJson.spawn,type=tenantJson.type, species=tenantJson.species})
            world.callScriptedEntity(self.deedId, "animator.setAnimationState", "deedState", "error")
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

function logENV()
    local indx = 1
    local tbl = {}
    for i,v in pairs(_ENV) do
      if type(v) == "function" then
        indx, tbl[indx] = indx+1, sb.print(i)
      elseif type(v) == "table" then
        for j,k in pairs(v) do
          indx, tbl[indx] = indx+1, string.format("%s.%s (%s)", sb.print(i), sb.print(j), type(k))
        end
      end
    end
    table.sort(tbl)
    sb.logInfo(table.concat(tbl, "\n"))
end

function debugFunction(func, ...)
    util.setDebug(true)
    func(...)
    util.setDebug(false)
end
--overwrites util.lua as this will actually null out and fully replace tables and values.
function jsonSetPath(t, jsonPath, value)

    local argList = util.filter(util.split(jsonPath, "."), function(v) return v ~= "" end)

    local key = table.remove(argList)
    
    for i,child in ipairs(argList) do
        if type(t[child]) ~= "nil" then
            t = t[child]
        else
            t[child] = {}
            t = t[child]
        end
    end
    t[key] = value
end