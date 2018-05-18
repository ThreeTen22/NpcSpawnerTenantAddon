require "/objects/spawner/colonydeed/timer.lua"

storage = storage or {}
function init()
    self.timers = TimerManager:new()

    self.delayStagehandDeath = Timer:new("delayStagehandDeath", {
        delay = 2,
        completeCallback = delayStagehandDeath,
        loop = true
      })
    if not self.delayStagehandDeath:active() then
      self.delayStagehandDeath:start()
    end

    self.timers:manage(self.delayStagehandDeath)

end

function update(dt)
    self.timers:update(dt)
end

function dismissed()
end

function uninit()
end

function delayStagehandDeath()
    local stagehandId = config.getParameter("stagehandId")
    world.sendEntityMessage(stagehandId, "delayDeath")
end