require "/scripts/util.lua"

Tenant = {}
Tenant.__index = Tenant


function Tenant.new(...)
    local self = {}
    setmetatable(self, Tenant)
    self:init(...)
    return self
end

function Tenant.fromConfig(jsonIndex)
    
    local self = config.getParameter("tenants."..tostring(jsonIndex), {})
    
    if isEmpty(self) then
        return nil
    end
    setmetatable(self, Tenant)
    self:init(
        {jsonIndex = jsonIndex, 
        dataSource = "config"}
    )
    return self
end

function Tenant:init(args)
    for k,v in pairs(args) do
        self[k] = v
    end
    if self.dataSource ~= "config" then
        self.config = root.npcConfig(self.type)
    else 
        self.config = "configs."..self.type.."."
    end
end

function Tenant:getPortrait(type)
    if self.dataSource == "config" then
        local path = string.format("tenantPortraits.%s.%s", self.jsonIndex, type)
        return config.getParameter(path)
    else
        if self.spawn == "npc" then
            return root.npcPortrait(type, self.species, self.type, 1, self.overrides or {})
        else
            return root.monsterPortrait(self.type, self.overrides or {})
        end
    end
end

function Tenant:getConfig(jsonPath, default)
    if type(self.config) == "string" then
        return config.getParameter(self.config..jsonPath, default)
    end
    return sb.jsonQuery(self.config, jsonPath, default)
end

function Tenant:instanceValue(jsonPath, default)
    return self[jsonPath] or sb.jsonQuery(self.overrides, jsonPath) or self:getConfig(jsonPath, default)
end


function Tenant:setInstanceValue(jsonPath, value)
    if type(self[jsonPath]) ~= "nil" then
        self[jsonPath] = value
        return
    end
    jsonSetPath(self.overrides, jsonPath, value)
end

function Tenant:toJson()
    return {
        spawn = self.spawn,
        type = self.type,
        species = self.species,
        seed = self.seed,
        level = self.level,
        overrides = copy(self.overrides)
    }
end

function Tenant:getVariant(useOverrides)
    if spawn == "npc" then
        if useOverrides == true then
            return root.npcVariant(self.species, self.type, 1, 1, overrides)
        else
            return root.npcVariant(self.species, self.type, 1)
        end
    end
end

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

--[[
/eval guard={scriptConfig=root.assetJson("/npcs/hiredguard.npctype:scriptConfig")};newGuard= {scriptConfig={questGenerator=root.assetJson("/npcs/friendlyguard.npctype:scriptConfig.questGenerator")}}; return sb.printJson(sb.jsonMerge(guard,newGuard), 1)
]]