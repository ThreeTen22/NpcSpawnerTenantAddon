require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/util.lua"

NpcInject = WeaponAbility:new()

function NpcInject:init()
  self.weapon:setStance(self.stances.idle)

  self.cooldownTimer = 0 
  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end

  storage.grabbedParam = storage.grabbedParam or jarray()
  animator.setGlobalTag("absorbed", string.format("%s", #storage.grabbedParam))
end


function NpcInject:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(self.cooldownTimer - dt, 0.0)

  if self.fireMode == "alt"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0 then

    if #storage.grabbedParam < self.maxStorage then
      self:setState(self.scan)
    else
      animator.playSound("error")
      self.cooldownTimer = self.cooldownTime
    end
  end

  local mag = world.magnitude(mcontroller.position(), activeItem.ownerAimPosition())
  if self.fireMode == "primary"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and #storage.grabbedParam > 0
    and mag > vec2.mag(self.weapon.muzzleOffset) and mag < self.maxRange
    and not world.lineTileCollision(self:firePosition(), activeItem.ownerAimPosition()) then

    self:setState(self.fire)
  end
end


function spawnerFound(spawnerId)
  if #storage.grabbedParam < self.maxStorage and (self.weapon.currentState == nil or self.weapon.currentState == self.scan) then
    petInfo.parameters = petInfo.parameters or {}
    petInfo.parameters.persistent = true
    petInfo.parameters.wasRelocated = true
    table.insert(storage.grabbedParam, petInfo)

    self:setState(self.absorb, monsterId, petInfo)
    return true
  else
    return false
  end
end

function NpcInject:scan()
  animator.playSound("scan")
  animator.playSound("scanning", -1)

  local promises = {}
  local scanCount = 1
  while self.fireMode == "alt" do
    local objects = world.objectQuery(activeItem.ownerAimPosition(), 2, {order = "nearest" })
    sb.setLogMap("scan.objects - before util", "%s %s", sb.printJson(objects), #objects)
    objects = util.filter(objects, function(objectId)

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
    sb.setLogMap("scan.objects - after", "%s", sb.printJson(objects))
    if #objects > 0 then
      sb.setLogMap("scan.ScanCount", "%s", scanCount)
      scanCount = scanCount - 1
      spawnerFound()
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

function NpcInject:absorb(entityId, monster)
  animator.stopAllSounds("scanning")
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)
  animator.setGlobalTag("absorbed", string.format("%s", #storage.grabbedParam))

  local monsterPosition = {0, 0}

  local timer = 0
  while timer < self.beamReturnTime do
    if world.entityExists(entityId) then
      monsterPosition = vec2.add(world.entityPosition(entityId), monster.attachPoint)
    end
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, monsterPosition)
    local offset = self:beamPosition(monsterPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer + script.updateDt()
    coroutine.yield()
  end

  local stoppedBeam = false
  local scanTimer = 10
  while world.entityExists(entityId) or scanTimer > 0 do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, monsterPosition)
    monsterPosition = vec2.add(world.entityPosition(entityId), monster.attachPoint)
    
    local offset = self:beamPosition(monsterPosition)
    self:drawBeam(vec2.add(self:firePosition(), offset), false)
    scanTimer = scanTimer - 1
    coroutine.yield()
  end

  animator.stopAllSounds("loop")
  animator.playSound("stop")

  timer = self.beamReturnTime
  while timer > 0 do
    local offset = self:beamPosition(monsterPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer - script.updateDt()

    coroutine.yield()
  end

  self.cooldownTimer = self.cooldownTime
end

function NpcInject:fire()
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)

  local spawnPosition = activeItem.ownerAimPosition()

  local last = #storage.grabbedParam
  local monster = storage.grabbedParam[last]

  local timer = 0
  while timer < self.beamReturnTime do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnPosition)

    local offset = self:beamPosition(spawnPosition)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)
    timer = timer + script.updateDt()

    coroutine.yield()
  end

  if not world.polyCollision(poly.translate(monster.collisionPoly, spawnPosition)) then
    world.spawnMonster(monster.monsterType, vec2.sub(spawnPosition, monster.attachPoint), monster.parameters)
    storage.grabbedParam[last] = nil
    animator.setGlobalTag("absorbed", string.format("%s", #storage.grabbedParam))

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
  local offset = vec2.mul(vec2.withAngle(self.weapon.aimAngle, math.max(0, world.magnitude(aimPosition, self:firePosition()))), {self.weapon.aimDirection, 1})
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
