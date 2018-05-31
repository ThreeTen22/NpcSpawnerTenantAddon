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
    end
end

function Tenant:getConfig(jsonPath, default)
    if type(self.config) == "string" then
        return config.getParameter(self.config..jsonPath, default)
    end
    return sb.jsonQuery(self.config, jsonPath) or default
end

function Tenant:instanceValue(jsonPath, default)
    return self[jsonPath] or sb.jsonQuery(self.overrides, jsonPath) or self:getConfig(jsonPath, default)
end


function Tenant:setInstanceValue(jsonPath, value)
    if value then
        if self[jsonPath] then
            self[jsonPath] = value
            return
        end
        jsonSetPath(self.overrides, jsonPath, value)
    end
end