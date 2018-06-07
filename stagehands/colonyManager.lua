require "/scripts/messageutil.lua"
require "/interface/scripted/deedmenu/tenantclass.lua"

function init()
    configParam = config.getParameter
    entityFunc =  world.callScriptedEntity
    self.debug = true
    self.deedId = configParam("deedId")
    --self.deedUuid = deedFunc("deedUniqueId")
    
    self.playerUuid = configParam("playerUuid")
    self.playerId = configParam("playerId")

    self.timers = TimerManager:new()

    self.deedCheckup = Timer:new("deedCheckup", {
        delay = script.updateDt(),
        completeCallback = updateSelf,
        loop = true
    })
    self.deedCheckup:start()
    self.timers:manage(self.deedCheckup)

    self.respawnTenantsDelay = Timer:new("respawnTenants", {
        delay = 0.9,
        completeCallback = respawnTenants,
        loop = false
    })

    self.timers:manage(self.respawnTenantsDelay)

    self.delayUpdate = Timer:new("delayUpdate", {
        delay = 0.5,
        loop = false
    })
    self.timers:manage(self.delayUpdate)


    message.setHandler("colonyManager.die", simpleHandler(killStagehand))
    message.setHandler("colonyManager.getTenants", simpleHandler(getTenants))
    message.setHandler("colonyManager.addTenant", simpleHandler(addTenant))
    message.setHandler("colonyManager.removeTenant", simpleHandler(removeTenant))
    message.setHandler("colonyManager.setDeedConfig", simpleHandler(setDeedConfig))
    message.setHandler("colonyManager.setTenantInstanceValue", simpleHandler(setTenantInstanceValue))
    self.hasScanned = false
    self.die = false

    if self.deedId == ""
    or self.playerUuid == "" then
        sb.logError("colonyManager:  init deedUuid or playerUuid was not provided: \n or deed does not belong to player")
        return stagehand.die()
    end

    self.init = coroutine.create(initCoroutine)
    --coroutine.resume(self.init)
end

function maxBeamoutTime(entityUuIds)
    if not entityUuIds then
        entityUuIds = {}
        for i,v in ipairs(getTenants()) do
            entityUuIds[i] = v.uniqueId
        end
    end
    local beamout = 0
    for i,v in ipairs(entityUuIds) do
        local id = world.loadUniqueEntity(v)
        if id > 0 then
            local list = entityFunc(id, "status.activeUniqueStatusEffectSummary")
            for li, lv in ipairs(list) do 
                if lv[1]:find("beamout", 1, true) then
                    beamout = math.max(beamout, lv[2])
                    break
                end
            end
        end
    end
    return beamout
end
function initCoroutine()
    if world.getObjectParameter(self.deedId, "owner") ~= self.playerUuid then

        sayError(table.unpack(configParam("errors.notOwner")))
        world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandFailed", {reason="notOwner"})
        return stagehand.die()
    end
    local timer = 1
    local primaryTenant, deedState, particleState
    repeat 
        primaryTenant = deedFunc("primaryTenant")
        deedState = deedFunc("animator.animationState", "deedState")
        particleState = deedFunc("animator.animationState", "particles")
        if (not primaryTenant) and
        (deedState == "scanning" or deedState == "beacon") 
        then
            timer = timer - script.updateDt()
            coroutine.yield()
        else
            timer = -1
        end 
    until timer < 0

    --primaryTenant = deedFunc("primaryTenant")
    deedState = deedFunc("animator.animationState", "deedState")
    particleState = deedFunc("animator.animationState", "particles")

    if deedState == "error" then
        return true
    end
    if particleState == "newArrival" then
        timer = 0.5
        while timer > 0 do
            timer = timer - script.updateDt()
            coroutine.yield()
        end
    end

    timer = 0.1
    repeat 
        primaryTenant = deedFunc("primaryTenant") or -1
        if #(world.entityPortrait(primaryTenant, "full") or {}) > 0 then
            timer = -1
        else
            timer = timer - script.updateDt()
            coroutine.yield()
        end
    until timer < 0


    local entityUuIds = {}
    for i,v in ipairs(getTenants()) do
        entityUuIds[i] = v.uniqueId
    end
    local beamout = 0
    for i,v in ipairs(entityUuIds) do
        local id = world.findUniqueEntity(v):result() and world.loadUniqueEntity(v)
        if id and id > 0 then
            local list = entityFunc(id, "status.activeUniqueStatusEffectSummary")
            for li, lv in ipairs(list) do 
                if lv[1]:find("beamout", 1, true) then
                    beamout = math.max(beamout, lv[2])
                    break
                end
            end
        end
    end
    while beamout > 0 do
        beamout = beamout - script.updateDt()
        coroutine.yield()
    end
    
    --[[
    if deedFunc("isOccupied") and deedFunc("anyTenantsDead") == true then
        deedFunc("respawnTenants")
        coroutine.yield()
    end
    ]]
end

function killStagehand()
    stagehand.die()
end

function update(dt)
    promises:update()
    self.timers:update(dt)
    if promises:empty() and not self.delayUpdate:active() then

        if coroutine.status(self.init) ~= "dead" then
            local success, err = coroutine.resume(self.init)
            if success or assert(false, err) then
                return
            end
        end
        --check to see if the tenant has been scanned, if not, scan it to ensure its a grumble
        local entityId = nil
        local tenantPortraits = {}
        local typeConfig = {}
        local tenants = getTenants()
        for i,v in ipairs(tenants) do
            entityId = world.loadUniqueEntity(v.uniqueId)
            
            --sb.logInfo("entityID: %s",entityId)
            tenantPortraits[i] = {}
            
            if v.spawn == "npc" then
                tenantPortraits[i].bust = world.entityPortrait(entityId, "bust")
            end
            tenantPortraits[i].full = world.entityPortrait(entityId, "full")
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
            self.init = nil
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

function deedFunc(name, ...)
    return world.callScriptedEntity(self.deedId, name, ...)
end

function updateSelf()
    --util.debugLog("updateSelf..init")
    local live = false
    local playerPos = world.entityPosition(self.playerId)
    stagehand.setPosition(playerPos)
    
    if isDeedAlive() and playerPos then
        if world.magnitude(playerPos, configParam("deedPosition")) < 20 then
            live = true
        end
    end
    if live then 
        stagehand.setPosition(playerPos)
    else
        stagehand.die()
    end
    --util.debugLog("updateSelf Result:  %s  %s", live, playerPos)
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
        deedFunc("object.setConfigParameter", "deed", configItem)
        deedFunc("init")
    end
    stagehand.die()
end

function setTenantInstanceValue(index, tenant, jsonPath, value)
    local tenants = getTenants()
    local merged = sb.jsonMerge(tenants[index] or {}, tenant)
    tenants[index] = merged
    if value == "jarray" then 
        value = jarray() 
    end
    jsonSetPathExplicit(tenants[index].overrides, jsonPath, value) 
    local tenantId = (tenants[index].uniqueId and world.findUniqueEntity(tenants[index].uniqueId):result() and world.loadUniqueEntity(tenants[index].uniqueId)) or 0
    if tenantId ~= 0 then
        entityFunc(tenantId, "recruitable.beamOut")
        tenants[index].uniqueId = nil
    end
    self.respawnTenantsDelay:start(maxBeamoutTime()+0.8)
end

function respawnTenants()
    if world.entityExists(self.deedId) then
        entityFunc(self.deedId, "respawnTenants")
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
            --entityFunc(self.deedId, "detachTenant", v)
            entityFunc(entityId, "tenant.detachFromSpawner")
            if spawn == "monster" then
                entityFunc(entityId, "tenant.evictTenant")
            else
                entityFunc(entityId, "recruitable.beamOut")
            end
        end
    end
    if shouldDie then
        stagehand.die()
    end
end

function getTenants()
    if isDeedAlive() then
        local tenants = deedFunc("getTenants")
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

function getDialogs(t)
    local t2 = {}
    for k,v in pairs(t) do
        if type(v) == "table" then 
            t2[k] = getDialogs(v)
        else
            t2[k] = root.assetJson(v)
        end
    end
    return t2
end


function dialogInjection(tenant)
    local configDialog, defaultDialog = {}, {}
    configDialog.dialog = tenant:instanceValue("scriptConfig.dialog")
    defaultDialog.dialog = configParam("defaultDialog")
    local newValue = sb.jsonMerge(configDialog, defaultDialog).dialog
    return newValue
end

function validateTenant(tenantJson)
    local spawning, tenant, species, crew, dialog
    --if new class isnt created then there is a problem with type

    spawning, tenant = pcall(Tenant.new, copy(tenantJson))
    if not spawning then
        return false, configParam("errors.type")
    end
    spawning = true
    if tenant.spawn == "npc" then
        spawning, _ = createVariant(tenantJson)
        if not spawning then 
            return false, configParam("errors.species")
        end
        tenant:setInstanceValue("dropPools", jarray())
        tenant:setInstanceValue("damageTeam", nil)
        tenant:setInstanceValue("damageTeamType", nil)
    else
        tenant:setInstanceValue("wasRelocated", true)
    end
    return true, tenant
end


function addTenant(tenantJson, shouldDie)
    if self.state == "main" and isDeedAlive() then

        local spawning, output = validateTenant(tenantJson)
        if spawning then 
            deedFunc("addTenant", output:toJson())
        else
            sayError(table.unpack(output))
        end
        --debugFunction(util.debugLog, "tenant to add: \n%s", sb.printJson(output, 1))
    end
    if shouldDie then
        stagehand.die()
    end
end

function sayError(message, state)
    deedFunc("object.say",message)
    deedFunc("animator.setAnimationState", "deedState", state)
end

function debugFunction(func, ...)
    util.setDebug(true)
    func(...)
    util.setDebug(false)
end
--overwrites util.lua as this will actually null out and fully replace tables and values.
function jsonSetPathExplicit(t, jsonPath, value)

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