require "/scripts/messageutil.lua"
function init()

    self.deedUuid = config.getParameter("deedId")
    self.playerUuid = config.getParameter("playerUuid")
    self.shutdownTimer = 10
    self.state = "init"
    if self.deedUuid == "" or self.playerUuid == "" then
        sb.logError("colonyManager:  init deedUuid or playerUuid was not provided: \n deedUuid: %s\nplayerUuid: %s", self.deedUuid, self.playerUuid)
        die()
    end
    message.setHandler("setPaneState", simpleHandler(setPaneState))
    message.setHandler("getTenants", simpleHandler(getTenants))
    message.setHandler("addTenants", simpleHandler(addTenants))
end

function update(dt)
    if self.state == "main" then
        mainUpdate(dt)
    elseif self.state == "init" then
        promises:update()
        if promises:empty() then
            local tenants = getTenants()
            promises:add(world.sendEntityMessage(self.playerUuid, "npcinjector.onStagehandSuccess", tenants), 
            function()
                self.state = "main"
            end,
            function()
                return die()
            end)
        end
    end
    if self.shutdownTimer < 1 then
        return die()
    end
    self.shutdownTimer = self.shutdownTimer - 1
end

function mainUpdate(dt)
    if not isDeedAlive() or not isPlayerAlive() then
        die()
    end
    promises:update()
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