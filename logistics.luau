local partdata = require("partdata"::any)
local _repr = require("repr"::any)
local resources: {[string|number]: string|number} = {"Power"}
local partEntries = {{ClassName="Power", ClassType="Present"}}
local allocations, currentResources, queuedOutputs, queuedInputs = {}, {}, {}, {}
type craft = ({Name: string}, any) -> (boolean)
type recipe = {
    Machine: string;
    Discrete: boolean;
    Void: boolean;
    Input: {[number]: number};
    Output: {[number]: number};
    Craft: craft;
    Name: string;
}
type node = {
    recipe
}

local function newResource(self, str, data: any?)
    if type(str) == "string" then
        local newIndex = #self + 1
        self[newIndex] = str
        self[str] = newIndex
        partEntries[newIndex] = data or {
            ClassName = str;
            ClassType = "Natural";
            ClassState = "Solid";
            Craftable = false;
            Spawnable = true;
        }
        allocations[newIndex] = 0
        currentResources[newIndex] = 0
        queuedOutputs[newIndex] = 0
        queuedInputs[newIndex] = 0
        return newIndex
    end
    print("nonexistent resource", str)
    return
end
setmetatable(resources,{
    __index = newResource
})
-- Initialize resource table
for obj, data in partdata.Parts do
    newResource(resources, obj, data)
end
local function encodeRecipe(recipe: {[string]: number}): {[number]: number}
    local output = {}
    for k, v in recipe do
        output[resources[k]] = v
    end
    return output
end

-- Methods for machines
local Produce: {[string]: craft} = {}
function Produce.Assembler(recipe, object)
    return object:Craft(recipe.Name)
end

-- Initialize crafting tree
local craftingTree: {node} = table.create(#partEntries)
for index, entry in partEntries do
    if not entry.Craftable or not entry.Recipe then continue end
    local node = {}
    local partName = entry.ClassName
    local recipe = {}
    recipe.Machine = "Assembler"
    recipe.Discrete = true
    recipe.Void = false
    recipe.Input = encodeRecipe(entry.Recipe)
    recipe.Output = {[resources[partName]] = 1}
    recipe.Craft = Produce.Assembler
    recipe.Name = partName
    node[1] = recipe
    craftingTree[index] = node
end

-- Utilities
local Utils = {}
function Utils.Compose<a, b, c>(f: {[b]: c}, g: {[a]: b}): {[a]: c}
    local output = {}
    for k, v in g do
        output[k] = f[v]
    end
    return output
end
function Utils.AddTo(src, dest, amount)
    for k, v in src do
        dest[k] += v * amount
    end
end
-- Initialize network
local ContainerNetwork = Network:GetSubnet(110)
local Containers = {}
local Capacities = {
    Bin = 1000;
    Tank = 10000;
    PowerCell = 200000;
}
local Classes = {
    Bin = 1;
    Tank = 2;
    PowerCell = 3;
}
local StorageTypes: {[string]: string} = {
    Solid = "Bin";
    Liquid = "Tank";
    Fluid = "Tank";
    Gas = "Tank";
    Power = "PowerCell";
}
local AllocationCapacity = Utils.Compose(Capacities, StorageTypes)
local EmptyContainerClass: {{[any]: true}} = {{}, {}, {}}
local function Allocate(resource, amount: number, storageType, allocation)
    if not storageType then
        local state = partEntries[resource].ClassState
        storageType = StorageTypes[state]
    end
    local capacity = Capacities[storageType]
    allocation = allocation or allocations[resource]
    local toAllocate = math.ceil(amount/capacity) - allocation
    if toAllocate < 1 then
        return allocation
    end
    local EmptyContainers = EmptyContainerClass[Classes[storageType]]
    local resourceName = resources[resource]
    for container, _ in EmptyContainers do
        container.Resource = resourceName
        toAllocate -= 1
        allocation += 1
        EmptyContainers[container] = nil
        if toAllocate == 0 then
            break
        end
    end
    allocations[resource] = allocation
    return toAllocate
end
for _, part in ContainerNetwork:GetParts("Bin") do
    Containers[part] = true
end
for _, part in ContainerNetwork:GetParts("Tank") do
    Containers[part] = true
end

local function fixResource(a) return if a=="nil" then nil else a end -- bug

local ContainerConnections: {[any]: RBXScriptConnection} = {}
local function AddContainer(part)
    local class = part.ClassName
    local containerClass = Classes[class]
    local capacity = Capacities[class]
    local prevAmount: number? = part:GetResourceAmount()
    local prevResource: string? = fixResource(part:GetResource())
    local EmptyContainers = EmptyContainerClass[containerClass]
    if prevResource then
        currentResources[resources[prevResource]] += prevAmount
        allocations[resources[prevResource]] += 1
    else
        EmptyContainers[part] = true
    end
    local function callback(_, amount)
        local resourceClass = fixResource(part:GetResource())
        local resourceIndex = resourceClass and resources[resourceClass]
        local prevResourceIndex = prevResource and resources[prevResource]
        local prevAllocation = prevResource and allocations[prevResourceIndex]
        local prevTotalAmount = currentResources[prevResourceIndex or resourceIndex]
        if prevTotalAmount then
            currentResources[prevResourceIndex or resourceIndex] = prevTotalAmount + amount - prevAmount
        end
        -- TODO fix floating point error find queued bin (with overhead) or align every X changes
        -- requirement: queued/antiqueued and current resources be fixed precision (sufficient if delta time precision is low enough)
        -- if precision loss then recalculate based on total (both queued resource and regular)

        --TODO: make this work and automatically reallocate
        -- requires Graph Pebbling algorithm to maximize output in the case of limited bins
        if amount == 0 and prevResourceIndex and prevTotalAmount + queuedOutputs[prevResourceIndex] <= capacity * (prevAllocation - 1) then
            part.Resource = "None"
            allocations[prevResourceIndex] -= 1
            EmptyContainers[part] = true
        end
        prevResource = resourceClass
        prevAmount = amount
    end
    if ContainerConnections[part] then ContainerConnections[part]:Disconnect() end
    local connection = part.ContainerChanged:Connect(callback)
    Containers[part] = callback
    ContainerConnections[part] = connection
    part.Destroying:Connect(function()
        ContainerConnections[part] = nil
        Containers[part] = nil
        EmptyContainers[part] = nil
        if prevResource then
            --DONE: delegate resource to new bin
            local prevResourceIndex = resources[prevResource]
            local allocation = allocations[prevResourceIndex]
            allocations[prevResourceIndex] = allocation - 1
            currentResources[prevResourceIndex] -= prevAmount
            Allocate(prevResourceIndex, allocation, nil, allocation - 1)
        end
    end)
end
local function UpdateContainers()
    for resource, _ in currentResources do
        currentResources[resource] = 0
    end
    for part, _ in Containers do
        AddContainer(part)
    end
end
local CraftingTree = {}

-- check if resource can be output
function CraftingTree.Check(recipe: recipe, machine: string?)
    if recipe.Machine ~= machine then return false end
    local toAllocate = {}
    for resource, amount in recipe.Input do
        local currentAmount = currentResources[resource]
        if amount > currentAmount - queuedInputs[resource] then return false end
        -- TODO: count queued antiresource
    end
    for resource, amount in recipe.Output do
        local currentAmount = currentResources[resource]
        local classState = partEntries[resource].ClassState
        local unitCapacity = AllocationCapacity[classState]
        local capacity = allocations[resource] * unitCapacity
        if capacity < amount then
            toAllocate[#toAllocate + 1] = {resource, amount, StorageTypes[classState]}
            capacity = unitCapacity
        end
        if not recipe.Void and currentAmount + queuedOutputs[resource] + amount > capacity then return false end
    end
    return toAllocate
end

-- terminates traversal, recipe to traverse
function CraftingTree.TraversalCondition(resource: number, node: node, requiredAmount: number, machine: string?): (false|{{number|string}}, recipe?)
    if machine and requiredAmount <= 0 then
        return false, nil
    end
    local recipe = node[1]
    if not recipe then return false, nil end
    return CraftingTree.Check(recipe, machine), recipe
end

-- BFS guarentees root uplink amounts are allocated first
function CraftingTree.Traverse<a...>(objectiveResources, objectiveAmounts, condition: (number, node, number, string?) -> (false|{{number|string}}, recipe?), machine)
    local queue = table.clone(objectiveResources)
    local amounts = table.clone(objectiveAmounts)
    local uplinkAmounts = table.clone(objectiveAmounts)
    local visited = {}
    for index, resource in ipairs(queue) do
        local node = craftingTree[resource]
        if not node then continue end
        if visited[node] then continue end
        local amount = amounts[index] - currentResources[resource] - queuedOutputs[resource]
        local traversal, recipe = condition(resource, node, amount, machine)
        if not recipe then
            continue
        elseif traversal then
            for _, allocator in traversal do
                Allocate(allocator[1], allocator[2], allocator[3])
            end
            Allocate(resource, uplinkAmounts[index])
            return recipe
        end
        visited[node] = true
        for k, v in recipe.Input do
            queue[#queue + 1] = k
            amounts[#queue] = amount * v
            uplinkAmounts[#queue] = v
        end
    end
    return nil
end

local function craftRecipe(machine: any, recipe: recipe) -- assume machine is correct
    if not recipe.Craft then return false end
    local discrete = recipe.Discrete
    if discrete then
        Utils.AddTo(recipe.Output, queuedOutputs, 1)
    end
    Utils.AddTo(recipe.Input, queuedInputs, 1)
    local result = recipe:Craft(machine)
    if discrete then
        Utils.AddTo(recipe.Output, queuedOutputs, -1)
    end
    Utils.AddTo(recipe.Input, queuedInputs, -1)
    return result
end
local Factory = {}
Factory.objectiveAmounts = nil
Factory.objectiveResources = nil
function Factory:SetObjective(recipe: {[string]: number})
    local objectiveResources, objectiveAmounts = {}, {}
    for k, v in recipe do
        objectiveResources[#objectiveResources + 1] = resources[k]
        objectiveAmounts[#objectiveAmounts + 1] = v
    end
    Factory.objectiveResources = objectiveResources
    Factory.objectiveAmounts = objectiveAmounts
end
function Factory:MachineLoop(machine: any, class: string): any? -- if machine utilized
    if machine:IsDestroyed() then return false end
    if not Factory.objectiveResources then return true end
    local recipe = CraftingTree.Traverse(self.objectiveResources, self.objectiveAmounts, CraftingTree.TraversalCondition, class)
    if recipe then
        return if craftRecipe(machine, recipe) then true else `failed to craft {recipe.Machine};{recipe.Name}`
    else
        return true
    end
end
function Factory:SpawnLoop(machine: any, class: string)
    task.spawn(function()
        while true do
            local a = pilot.getCPUTime()
            local result = self:MachineLoop(machine, class)
            local b = pilot.getCPUTime()
            local timeToWait = (b-a)/100
            if timeToWait > 0.5 then print("took more time") end
            task.wait(timeToWait)
        end
    end)
end

craftingTree[resources.Sand::any]={{
    Machine = "Pulverizer";
    Name = "Sand";
    Input = encodeRecipe{
        Stone = 1;
        Quartz = 1;
    };
    Output = encodeRecipe{
        Sand = 1;
    };
    Discrete = true;
    Void = false;
    Craft = nil;
}}
craftingTree[resources.Snow::any]={{
    Machine = "Pulverizer";
    Name = "Snow";
    Input = encodeRecipe{
        Ice = 1;
    };
    Output = encodeRecipe{
        Snow = 1;
    };
    Discrete = true;
    Void = false;
    Craft = nil;
}}
local refining = {
    Machine = "Refinery";
    Name = "Refine";
    Input = encodeRecipe{
        Oil = 1;
    };
    Output = encodeRecipe{
        Gasoline = 1;
        Petroleum = 1;
    };
    Discrete = false;
    Void = true;
    Craft = nil;
}
craftingTree[resources.Gasoline::any] = {refining}
craftingTree[resources.Petroleum::any] = {refining}
craftingTree[resources.Water::any]={{
    Machine = "Melter";
    Name = "Ice";
    Input = encodeRecipe{
        Ice = 1;
    };
    Output = encodeRecipe{
        Water = 1;
    };
    Discrete = true;
    Void = false;
    Craft = nil;
},{
    Machine = "Melter";
    Name = "Snow";
    Input = encodeRecipe{
        Snow = 1;
    };
    Output = encodeRecipe{
        Water = 1;
    };
    Discrete = true;
    Void = false;
    Craft = nil;
}}
-- not discrete -> don't queue

UpdateContainers()
for _, assembler in GetPartsFromPort(103, "Assembler") do
    Factory:SpawnLoop(assembler, "Assembler")
end
Factory:SetObjective({Wire = 100})