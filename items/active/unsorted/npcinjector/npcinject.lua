require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/util.lua"

NpcInject = WeaponAbility:new()

function NpcInject:init()
  --if not storage then storage = {} end

  --debugFunction(util.debugLog, sb.printJson(player.inventoryTags()))
  util.setDebug(false)
  --util.debugLog("Ininit")
  --debugFunction(util.debugLog, sb.printJson(player.inventoryTags()))
  self.weapon:setStance(self.stances.idle)
  self.cooldownTimer = 0
  self.tenants = nil
  self.tenantPortraits = nil
  self.typeConfig = nil
  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end

  storage.stagehandId = storage.stagehandId

  message.setHandler("npcinjector.onStagehandSuccess", function(_,_,id, tenants, tenantPortraits, typeConfig)
    --util.debugLog("npcinjector.onStagehandSuccess")

    storage.stagehandId = id

    local dUuid = world.entityUniqueId(storage.spawner.deedId)
    local pUuid = player.uniqueId()

    local deedpane = root.assetJson("/interface/scripted/deedmenu/deedpane.config")

    deedpane.deedUuid = dUuid
    deedpane.playerUuid = pUuid
    deedpane.stagehandId = stagehandId or storage.stagehandId
    deedpane.deedId = storage.spawner.deedId
    deedpane.deedPosition = storage.spawner.position
    deedpane.tenants = tenants
    deedpane.tenantPortraits = tenantPortraits
    deedpane.configs = typeConfig
    deedpane.tenantCount = #tenants
    player.interact("ScriptPane", deedpane, id)
   
    return true
  end)
  message.setHandler("npcinjector.onStagehandFailed", function(_,_,args)
    --util.debugLog("npcinjector.onStagehandFailed")
    storage.stagehandId = nil
    storage.spawner = nil

    self.cooldownTimer = self.cooldownTime
  end)

  message.setHandler("npcinjector.onPaneDismissed", function(_,_,...)
    --util.debugLog("npcinjector.")
    storage.spawner = nil
    storage.stagehandId = nil
    self:reset()
  end)

  animator.setGlobalTag("absorbed", string.format("%s", 0))
end


function NpcInject:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(self.cooldownTimer - dt, 0.0)

  if self.fireMode == "primary"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0 then

    if not storage.spawner then
      self:setState(self.scan)
    elseif world.entityExists(storage.stagehandId or -1) then
      self:setState(self.absorb, storage.spawner.deedId, storage.stagehandId, storage.spawner)
    else
      --animator.playSound("error")
      --util.debugLog("inside firemode - else statement - storage.spawner cleared")
      self.cooldownTimer = 0
      storage.spawner = nil
      storage.stagehandId = nil
    end
  end
  if self.fireMode == "alt" then
    --DEBUG:  DONT KEEP
    --util.debugLog("inside firemode - alt - storage.spawner cleared")
    --self.weapon:setStance(self.stances.idle)
    self.cooldownTimer = 0
    storage.spawner = nil
    storage.stagehandId = nil
    
  end
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
        if objectId == 0 or world.lineTileCollision(self:firePosition(), position) then
          return false
        end
        local mag = world.magnitude(mcontroller.position(), position)
        if mag > self.maxRange or mag < vec2.mag(self.weapon.muzzleOffset) then
          return false
        end
        if world.getObjectParameter(objectId, "category") ~= "spawner" then
          return false
        end
        if world.getObjectParameter(objectId, "npcArgs") ~= nil
        then
          return false
        end
        return true
    end)
    if #objects > 0 then
      local spawner = {}
      local deedId = objects[1]
      local dUuid = world.entityUniqueId(deedId)
      local pUuid = player.uniqueId()
      local position = world.entityPosition(deedId)
      local returnValue = false
      
      if not storage.spawner then
        
        world.sendEntityMessage((storage.stagehandId or -1), "colonyManager.die")
        storage.stagehandId = nil
       
        spawner = world.getObjectParameter(deedId, "deed") or {}
        spawner.position = position
        spawner.attachPoint = {0,0}
        spawner.deedId = deedId
        storage.spawner = spawner
        returnValue = true
      end
      if not (storage.stagehandId and world.entityExists(storage.stagehandId)) then
      storage.stagehandId = world.spawnStagehand(mcontroller.position(), "colonymanager", 
        { deedId = deedId,
          deedPosition = position,
          deedUuid=dUuid, 
          playerUuid=pUuid,
          playerId=player.id()
        })
        returnValue = true
      end
      if returnValue == true then
        self:setState(self.absorb, deedId, storage.stagehandId, storage.spawner)
      end
      return returnValue
    end
    coroutine.yield()
  end

  animator.stopAllSounds("scanning")
  animator.playSound("scanend")
end


function NpcInject:absorb(deedId, stagehandId, spawner)
  animator.stopAllSounds("scanning")
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)
  animator.setGlobalTag("absorbed", string.format("%s", 1))

  local spawnerPos = {0, 0}

  --util.debugLog("ABSORB: BEGIN")
  local timer = 0
  while timer < self.beamReturnTime do
    if world.entityExists(deedId) then
      spawnerPos = vec2.add(world.entityPosition(deedId), spawner.attachPoint)
    end
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnerPos)
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer + script.updateDt()
    coroutine.yield()
  end

  local stoppedBeam = false
  local scanTimer = 1
  animator.stopAllSounds("loop")
  

  --util.debugLog("ABSORB: BEFORE CHECKING storage.stagehandId")
  while not world.entityExists(storage.stagehandId or -1) and storage.spawner do
    --util.debugLog("ABSORB: WAIT FOR storage.stagehandId")
    coroutine.yield()
  end
  --util.debugLog("ABSORB: storage.stagehandId FOUND")
  --util.debugLog("ABSORB: BEFORE CHECKING storage.stagehandId is dead")
  while world.entityExists(storage.stagehandId or -1)
  do
    --util.debugLog("ABSORB: CHECKING storage.stagehandId IS ALIVE")
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnerPos)
    spawnerPos = vec2.add(world.entityPosition(deedId), spawner.attachPoint)
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), offset), false)

    coroutine.yield()
  end
  --util.debugLog("ABSORB: storage.stagehandId is DEAD, ABOUT TO CLEAR spawner")
  storage.stagehandId = nil
  storage.spawner = nil
  animator.stopAllSounds("loop")
  animator.playSound("stop")
  --util.debugLog("ABSORB: storage.spawner CLEARED")
  timer = self.beamReturnTime
  while timer > 0 do
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer - script.updateDt()

    coroutine.yield()
  end
  animator.setGlobalTag("absorbed", string.format("%s", 0))
  self.cooldownTimer = self.cooldownTime
end

function NpcInject:fire()

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
  self:reset()
end

function NpcInject:reset()
  animator.stopAllSounds("loop")
  self.weapon:setDamage()
  activeItem.setScriptedAnimationParameter("chains", {})
end


function debugFunction(func, ...)
  util.setDebug(true)
  func(...)
  util.setDebug(false)
end