require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/util.lua"

NpcInject = WeaponAbility:new()

function NpcInject:init()
  
  self.debug = true
  util.setDebug(true)
  util.debugLog("Ininit")
  
  self.weapon:setStance(self.stances.idle)
  self.cooldownTimer = 0
  self.tenants = nil
  self.tenantPortraits = nil
  storage.stagehandId = storage.stagehandId and world.entityExists(storage.stagehandId) or nil
  storage.paneAlive = storage.paneAlive or false
  self.typeConfig = nil
  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end

  storage.spawner = storage.spawner  or jarray()
  if storage.spawner then
    local id = storage.spawner.objectId or -1
    if not (world.entityExists(id)
    and world.entityName(id) == "colonydeed"
    and world.magnitude(mcontroller.position(),world.entityPosition(id)) < 20) then
      storage.spawner = nil
    end
  end
  animator.setGlobalTag("absorbed", string.format("%s", 3))
  message.setHandler("npcinjector.onStagehandSuccess", function(_,_,id, tenants, tenantPortraits, typeConfig)
    util.debugLog("npcinjector.onStagehandSuccess ")
    self.tenants = tenants
    self.tenantPortraits = tenantPortraits
    self.typeConfig = typeConfig
    storage.stagehandId = id
    return true
  end)
  message.setHandler("npcinjector.onStagehandFailed", function(_,_,args)
    util.debugLog("npcinjector.onStagehandFailed")
    self.tenants = nil
    self.tenantPortraits = nil
    storage.stagehandId = nil
    storage.paneAlive = false
    self.typeConfig = nil
    storage.spawner = nil
    self.cooldownTimer = self.cooldownTime
  end)

  message.setHandler("npcinjector.paneAlive", function(_,_,stagehandId, deedId)
    util.debugLog("npcinjector.paneAlive")
    if not self.weapon.currentAbility and not storage.paneAlive
      and path(storage.spawner, "objectId") == deedId then
    
    storage.stagehandId = stagehandId
    storage.paneAlive = true
    self:setState(self.absorb, storage.spawner.objectId, storage.spawner)
    end
  end)

  message.setHandler("npcinjector.onPaneDismissed", function(_,_,...)
    sb.logInfo("npcinjector.onPaneDismissed")
    storage.spawner = nil
    self.tenants = nil
    self.tenantPortraits = nil
    storage.stagehandId = nil
    storage.paneAlive = false
    self.typeConfig = nil
    self.cooldownTimer = self.cooldownTime
  end)

end


function NpcInject:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(self.cooldownTimer - dt, 0.0)

  if self.fireMode == "primary"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0 then

    if not storage.spawner then
      self:setState(self.scan)
    elseif storage.paneAlive and world.entityExists(storage.stagehandId or -1) then
      self:setState(self.absorb, storage.spawner.objectId, copy(storage.spawner))
    else
      animator.playSound("error")
      self.cooldownTimer = self.cooldownTime
    end
  end
  if self.fireMode == "alt" then
    --DEBUG:  DONT KEEP
    storage.spawner = nil
    self.weapon:setStance(self.stances.idle)
    self.cooldownTimer = 0
    self.tenants = nil
    self.tenantPortraits = nil
    storage.stagehandId = nil
    storage.paneAlive = false
    self.typeConfig = nil
  end

  --[[
  local mag = world.magnitude(mcontroller.position(), activeItem.ownerAimPosition())
  if self.fireMode == "alt"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and #storage.spawner > 0
    and mag > vec2.mag(self.weapon.muzzleOffset) and mag < self.maxRange
    and not world.lineTileCollision(self:firePosition(), activeItem.ownerAimPosition()) then

    self:setState(self.fire)
  end
  --]]
end

function NpcInject:scan()
  animator.playSound("scan")
  animator.playSound("scanning", -1)

  local promises = {}
  local scanCount = 1
  while self.fireMode == "primary" do
    local objects = world.objectQuery(activeItem.ownerAimPosition(), 2, {order = "nearest" })
    objects = util.filter(objects, 
    function(objectId)
      local position = world.entityPosition(objectId)
      if world.lineTileCollision(self:firePosition(), position) then
        return false
      end
      local mag = world.magnitude(mcontroller.position(), position)
      if mag > self.maxRange or mag < vec2.mag(self.weapon.muzzleOffset) then
        return false
      end
      if world.getObjectParameter(objectId, "category") ~= "spawner" then
        return false
      end
      return true
    end)
    if #objects > 0 then
      local spawner = {}
      local objectId = objects[1]
      if not storage.spawner and 
      (self.weapon.currentState == nil or self.weapon.currentState == self.scan) then
        local position = world.entityPosition(objectId)
        spawner = world.getObjectParameter(objectId, "deed") or {}
        spawner.attachPoint = {0,0}
        spawner.objectId = objectId
        storage.spawner = spawner

        local dUuid = world.entityUniqueId(objectId)
        local pUuid = player.uniqueId()
      
        world.spawnStagehand(position, "colonymanager", {deedId = objectId, deedUuid=dUuid, playerUuid=pUuid})

        self:setState(self.absorb, objectId, spawner)

        return true
      else
        return false
      end
    end
    coroutine.yield()
  end

  animator.stopAllSounds("scanning")
  animator.playSound("scanend")
end

--[[
for _,objectId in ipairs(objects) do
      if not promises[objectId] then
        promises[objectId] = true
        local promise = world.sendEntityMessage(objectId, "pet.attemptRelocate", activeItem.ownerEntityId())

        while not promise:finished() do
          coroutine.yield()
        end

        break
      end
    end
----]]

function NpcInject:absorb(entityId, object)
  animator.stopAllSounds("scanning")
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)
  animator.setGlobalTag("absorbed", string.format("%s", 3))

  local objectPosition = {0, 0}

  local timer = 0
  while timer < self.beamReturnTime do
    if world.entityExists(entityId) then
      objectPosition = vec2.add(world.entityPosition(entityId), object.attachPoint)
    end
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, objectPosition)
    local offset = self:beamPosition(objectPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer + script.updateDt()
    coroutine.yield()
  end

  local stoppedBeam = false
  local scanTimer = 1
  animator.stopAllSounds("loop")
  
  local dUuid = world.entityUniqueId(entityId)
  local pUuid = player.uniqueId()

  while not world.entityExists(storage.stagehandId or -1) and storage.spawner do
    coroutine.yield()
  end
  if storage.spawner and storage.paneAlive == false then
    local deedpane = root.assetJson("/interface/scripted/deedmenu/deedpane.config")
    deedpane.deedUuid = dUuid
    deedpane.playerUuid = pUuid
    deedpane.stagehandId = storage.stagehandId
    deedpane.deedId = entityId
    deedpane.stagehandPosition = objectPosition
    deedpane.tenants = self.tenants
    deedpane.tenantPortraits = self.tenantPortraits
    deedpane.configs = self.typeConfig
    player.interact("ScriptPane", deedpane)
  end

  while world.entityExists(entityId) and #storage.spawner > 0 
  and  world.magnitude(mcontroller.position(),objectPosition) < 20
  do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, objectPosition)
    objectPosition = vec2.add(world.entityPosition(entityId), object.attachPoint)
    local offset = self:beamPosition(objectPosition)
    self:drawBeam(vec2.add(self:firePosition(), offset), false)
    --[[
    scanTimer = scanTimer - script.updateDt()
    if scanTimer == 0 then
      break
    end
    --]]
    coroutine.yield()
  end

  animator.stopAllSounds("loop")
  animator.playSound("stop")

  timer = self.beamReturnTime
  while timer > 0 do
    local offset = self:beamPosition(objectPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer - script.updateDt()

    coroutine.yield()
  end
  animator.setGlobalTag("absorbed", string.format("%s", 0))
  self.cooldownTimer = self.cooldownTime
end

function NpcInject:fire()
  --[[
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)

  local spawnPosition = activeItem.ownerAimPosition()

  local last = #storage.spawner
  local spawner = storage.spawnerst]

  local timer = 0
  while timer < self.beamReturnTime do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnPosition)

    local offset = self:beamPosition(spawnPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)
    timer = timer + script.updateDt()

    coroutine.yield()
  end

  if not world.polyCollision(poly.translate(spawner.collisionPoly, spawnPosition)) then
    --world.spawnMonster(monster.monsterType, vec2.sub(spawnPosition, monster.attachPoint), monster.parameters)
    storage.spawnerst] = nil
    animator.setGlobalTag("absorbed", string.format("%s", #storage.spawner*3))

    util.wait(0.3, function()
      self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnPosition)

      local offset = self:beamPosition(spawnPosition)
      self:drawBeam(vec2.add(self:firePosition(), offset), false)
    end)
  else
    animator.playSound("error")
  end

  animator.stopAllSounds("loop")
  animator.playSound("stop")

  timer = self.beamReturnTime
  while timer > 0 do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnPosition)

    local offset = self:beamPosition(spawnPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)
    timer = timer - script.updateDt()

    coroutine.yield()
  end

  self.cooldownTimer = self.cooldownTime

  --]]
end

function NpcInject:drawBeam(endPos, didCollide)
  local newChain = copy(self.chain)
  newChain.startOffset = self.weapon.muzzleOffset
  newChain.endPosition = endPos

  if didCollide then
    newChain.endSegmentImage = nil
  end

  activeItem.setScriptedAnimationParameter("chains", {newChain})
end

function NpcInject:beamPosition(aimPosition)
  local offset = vec2.mul(
    vec2.withAngle(
      self.weapon.aimAngle, 
      math.max(
        0, 
        world.magnitude(
          aimPosition, 
          self:firePosition()))
    ), {self.weapon.aimDirection, 1}
  )
  if vec2.dot(offset, world.distance(aimPosition, self:firePosition())) < 0 then
    -- don't draw the beam backwards
    offset = {0,0}
  end
  return offset
end

function NpcInject:firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
end

function NpcInject:aimVector(inaccuracy)
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()
  return aimVector
end

function NpcInject:uninit()
  util.debugLog("npcinject: unint")
  self:reset()
end

function NpcInject:reset()
  animator.stopAllSounds("loop")
  self.weapon:setDamage()
  activeItem.setScriptedAnimationParameter("chains", {})
end
