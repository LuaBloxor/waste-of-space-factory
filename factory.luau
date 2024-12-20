local EMode = true
local TargetTemp = 950
local Anchor = GetPart("Anchor")
local ReactorPorts = GetPorts(110)
local function SetPoly(Polysilicon, Type, Amount)
	Polysilicon.PolysiliconMode = Type or "FlipFlop"
	Polysilicon.Frequency = Amount or 1
	if Amount then
		Polysilicon:Trigger()
	end
	return Amount or 0
end
local function SetRods(Target, Rods, Polysilicon)
	local change = Target - Rods
	if change == 0 then return Target end
	if change > 0 then SetPoly(Polysilicon, 0, change) end
	if change < 0 then SetPoly(Polysilicon, 1, -change) end
	return Target
end
local Connections = {}
for ind, Port in ReactorPorts do
	local Reactor = GetPartFromPort(Port, "Reactor")
	local Rods = 10
	local Polysilicon = GetPartFromPort(Port, "Polysilicon")
	local Dispenser = GetPartFromPort(Port, "Dispenser")
	Reactor.TriggerWhenEmpty = true
	SetPoly(Polysilicon, "Activate", 10)
	SetPoly(Polysilicon)
	local event = function()
		local Fuels = Reactor:GetFuel()
		local RodsInserted = 0
		for _, Fuel in Fuels do
			if Fuel == -1 then
				-- Polysilicon.PolysiliconMode = 2
				-- TriggerPort(Port)
			end
			if Fuel > 0 then
				RodsInserted += 1
			end
		end
		if RodsInserted < 4 then
			if not Microcontroller:IsGrounded() then Anchor.Anchored = true end
			Dispenser:Dispense()
			RodsInserted += 1
		end
		if RodsInserted < 1 then return end -- *
		local Diff = TargetTemp - Reactor:GetTemp()
		local NewRods = math.ceil(math.clamp(10 - (Diff * 3 + 20) / RodsInserted, 0, 10))
		Rods = SetRods(NewRods, Rods, Polysilicon)
		SetPoly(Polysilicon)
		-- ((10-Rods)*RodsInserted-20)/3
	end
	if EMode then
		Connections[ind] = event
	else
		Reactor.Loop:Connect(event)
	end
end
print("num of reactors", #Connections)
if EMode then
	GetPartFromPort(ReactorPorts[1], "Reactor").Loop:Connect(function()
		for ind, Port in ReactorPorts do
			Connections[ind]()
		end
	end)
end

--[[
crafing tree manipulation version 2.1.0
]]
--type OrderiumImpl<a> = {__lt:(a:Orderium<a>,a:Orderium<a>)->boolean}
--type Orderium<a> = typeof(setmetatable({}::any, {} :: OrderiumImpl<a>))
type Ordered<a> = number--|Orderium<a>

type Dict<K, V> = {[K]: V}
type MemoizedImpl<K, V> = {
	__index: (Memoized<K, V>, K) -> V?
}
type Memoized<K, V> = typeof(setmetatable({}::Dict<K, V>,{}:: MemoizedImpl<K, V>))
local Memoized = {}
Memoized.new = (function<K, V> (func, storage)
	return setmetatable(storage, {
		__index = function(_, index)
			local newValue = func(index, storage)
			if newValue then storage[index] = newValue end
			return newValue
		end;
	}::MemoizedImpl<K, V>)
end)::<K, V>((K, Dict<K, V>) -> V?,Dict<K, V>)->(Memoized<K, V>)

type resourceID = number
type Recipe = Dict<resourceID, number>
type StringRecipe = {
	[string]: number
}
type ConfigDef = {
	Input: StringRecipe;
	Deposit: string?;
	Output: StringRecipe;
}
type MachineDef = {
	Config: string?;
	Power: number?;
	Recipes: {
		[string]: ConfigDef
	};
}
type MachineDefs = {
	[string]: MachineDef
}
type Config = {
	Name: string;
	Machine: resourceID;
	Input: Recipe;
	Output: Recipe;
	Deposit: resourceID?;
}
type Machine = {
	Config: string?;
	Name: string;
}
type State = {
	Resources: Resources;
	CraftQueue: Recipe;
	ResourceQueue: Recipe;
	Target: Recipe;
	Repeat: Recipe?;
}
type Machines = {
	[resourceID]: {any}
}
type Resources = {
	Storage: {[resourceID]: number};
	Capacity: {[resourceID]: number};
}
type System = {
	Produce: (boolean, Recipe) -> (State, string?);
	AddMachines: (string, WoSPart) -> ();
	DisplayMessage: (any, string) -> ();
}
type WoSPart = {
	GUID: string;
	ClassName: string;
	[string|number]: any;
};
type WoS = {
	GetPartsFromPort: (any, any) -> {WoSPart};
	GetPartFromPort: (any, any) -> WoSPart?;
	GetPort: (number) -> WoSPart?;
	[string]: any;
}

-- DATA START
local MachineDefs: MachineDefs = {
	Hydroponic = {
		Config = "Grow";
		Power = 5;
		Recipes = {
			Grass = {
				Input = {Water=2};
				Output = {Grass=1};
			};
			Stick = {
				Input = {Water=2};
				Output = {Stick=1};
			};
			Wood = {
				Input = {Water=2};
				Output = {Wood = 1};
			};
		};
	};
	Assembler = {
		Config = "Assemble";
		Recipes = {};
	};
	Refinery = {
		Power = 15;
		Recipes = {
			Default = {
				Input = {Oil = 1};
				Output = {Gasoline = 1, Petroleum = 1};
			};
		};
	};
	Melter = {
		Power = 5;
		Recipes = {
			Default = {
				Input = {Ice = 1};
				Output = {Water = 1};
			};
		};
	};
	Freezer = {
		Power = 5;
		Recipes = {
			Default = {
				Input = {Water = 1};
				Output = {Ice = 1};
			};
		};
	};
	Pulverizer = {
		Power = 3;
		Recipes = {
			Default = {
				Input = {Stone = 1, Quartz = 1};
				Output = {Sand = 1};
			};
		};
	};
	Kiln = {
		Power = 5;
		Recipes = {
			Default = {
				Input = {Sand = 1};
				Output = {Glass = 1};
			};
		};
	};
	Pump = {
		Power = 5;
		Recipes = {
			Default = {
				Input = {};
				Deposit = "Water";
				Output = {Water = 1};
			};
		};
	};
	Boiler = {
		Recipes = {
			Default = {
				Input = {Water = 1, Coal = 1};
				Output = {Steam = 1};
			};
		};
	};
	SolarScoop = {
		Recipes = {
		}
	};
}

local GlobalDeposits:{[string]:string}={
	Mountain="Stone,Ruby,Quartz,Silicon,Flint,Sulfur,Oil,Helium,Ice";
	Tree="Wood,Stick";
	IceAsteroid="Ice";
	Sand="Sand";
	Grass="Grass";
	Snow="Snow";
}
local PlanetDeposits = {
	"Iron","Copper","Coal",
	"Aluminum","Diamond","Titanium",
	"Uranium","Beryllium","Lead",
	"Jade","Gold"
}
local MiningLaserDeposits = {
	AluminumDeposit = 201;
	CoalDeposit = 202;
	CopperDeposit = 203;
	DiamondDeposit = 204;
	BerylliumDeposit = 205;
	GoldDeposit = 206;
	IronDeposit = 207;
	JadeDeposit = 208;
	LeadDeposit = 209;
	TitaniumDeposit = 210;
	UraniumDeposit = 211;
	Grass = 220;
	IceAsteroid = 221;
	Mountain = 222;
	Sand = 223;
	Snow = 224;
	Tree = 225;
}
local LiquidGas={Water=0,Helium=1,Hydrogen=1,Steam=1,Petroleum=1,Gasoline=0,Oil=0,Plasma=1,MustardGas=1}
-- generate the rest of the machine info
local Deposits = {}
-- parse planetary deposits list
for _,resource in PlanetDeposits do
	local deposit=resource.."Deposit"
	Deposits[deposit]={resource}
end
-- parse "GlobalDeposits"
for deposit,resources in GlobalDeposits do
	Deposits[deposit]=string.split(resources, ",")
end
-- add types of MiningLaser
local function AddDeposit(deposit: string, resources: {string}): MachineDef
	local MiningLaserRecipes = {}
	local MiningLaser: MachineDef = {
		Config = "MaterialToExtract";
		Power = 25;
		Recipes = MiningLaserRecipes;
	};
	for _, resource in resources do
		MiningLaserRecipes[resource] = {
			Input = {};
			Output = {[resource] = 2};
		}
	end
	MachineDefs[deposit] = MiningLaser
	return MiningLaser
end
for deposit, resources in Deposits do
	AddDeposit("MiningLaser "..deposit, resources)
end
-- DATA END

local _inf = 1/0
local debugOn = true
local db:(...any)->() = function(...) if not debugOn then return end; print(`debug {table.concat(table.pack(...), " ")}`); end; -- function()end

local FromID: {[number]: any} = {
	"Power", "Hydrogen", "tinnitus", "Plasma"
}
local ToIDStorage = {}
for index, object in FromID do
	ToIDStorage[object] = index
end
local counter: number = #FromID+1
local function AddResource(resource) -- ??? (TBD)
	FromID[counter] = resource
	counter += 1
	return counter - 1
end

local ToID: Memoized<any, number> = Memoized.new(AddResource, ToIDStorage)
local function ToRecipe(recipe: {[any]: number}, toID): Recipe
	if not toID then toID = ToID end
	local output = {}
	for resource, amount in recipe do
		output[toID[resource]] = amount
	end
	return output
end
local function FromRecipe(recipe: Recipe, fromID): {[any]: number}
	if not fromID then fromID = FromID end
	local output = {}
	for resource, amount in recipe do
		output[fromID[resource]] = amount
	end
	return output
end
local GetConfig: Memoized<resourceID, {resourceID}>
local Recipes = {}
local MachineTypes: {[resourceID]: Machine} = {}
local function RegisterRecipe(recipe, machineID: resourceID, info: MachineDef, configName: string, configs: {resourceID}?): resourceID
	local machineName = FromID[machineID]
	local input = ToRecipe(recipe.Input, ToID)
	local power = info.Power
	if power then
		input[1] = power
	end
	local output = ToRecipe(recipe.Output, ToID)
	local config:Config = {
		Name = configName;
		Machine = machineID;
		Input = input;
		Output = output;
		Deposit = if recipe.Deposit then ToID[recipe.Deposit] else nil;
	}
	local configID = ToID[`{machineName};{configName}`]
	Recipes[configID] = config
	for k, v in output do
		local configs = configs or GetConfig[k]
		configs[#configs + 1] = configID
	end
	return configID
end

local WoS = {}
-- local GetPartFromPort,GetPartsFromPort,GetPort,JSONEncode,JSONDecode,TriggerPort,Beep,SandboxID,SandboxRunID=require(game.ServerScriptService['MBEEE.PilotLua']).GetGlobals()
if workspace and workspace:FindFirstChild("WoSModule") then
	WoS = error(workspace:FindFirstChild("WoSModule"))
else
	WoS.GetPartFromPort,WoS.GetPartsFromPort,WoS.GetPort,WoS.JSONEncode,WoS.JSONDecode,WoS.TriggerPort,WoS.Beep,WoS.SandboxID,WoS.SandboxRunID=GetPartFromPort,GetPartsFromPort,GetPort,JSONEncode,JSONDecode,TriggerPort,Beep,SandboxID,SandboxRunID
end
local repr = require("repr")
Network = Network --fix
local debugRecipe = function(a) db(print(repr(FromRecipe(a,FromID)))) end

local Assembler = WoS.GetPartFromPort(103,"Assembler") -- Get assembler for calc
GetConfig = Memoized.new(function(index, storage)
	if not Assembler then
		print("no assembler")
		return {}
	end
	local recipe = Assembler:GetRecipe(FromID[index])
	local configs = {}
	if not recipe then return configs end
	local configName = FromID[index]
	RegisterRecipe({
		Input = recipe;
		Output = {[configName] = 1}
	}, ToID.Assembler, MachineDefs.Assembler, configName, configs)
	return configs
end, {})
local MachineOrders = {
	"Hydroponic", "Pulverizer", "Pump", "Melter", "Freezer"
}
for _, machineName in MachineOrders do
	local info = MachineDefs[machineName]
	local machine = {}
	local machineID = ToID[machineName]
	machine.Config = info.Config
	machine.Name = machineName
	MachineTypes[machineID] = machine
	for configName, recipe in info.Recipes do
		RegisterRecipe(recipe, machineID, info, configName)
	end
end
for machineName, info in MachineDefs do
	local machineID = ToID[machineName]
	if MachineTypes[machineID] then continue end
	local machine = {}
	machine.Config = info.Config
	machine.Name = machineName
	MachineTypes[machineID] = machine
	for configName, recipe in info.Recipes do
		RegisterRecipe(recipe, machineID, info, configName)
	end
end

local function Add(weights: {number}, operands: {Recipe}, addto: Recipe?) -- adds elements entry-wise
	local output: Recipe = addto or {}
	for index, operand in operands do
		local weight = weights[index]
		if weight == 0 then continue end
		for k,v in operand do
			local calculatedValue = (output[k] or 0) + v * weight
			if calculatedValue == 0 then
				output[k] = nil
			else
				output[k] = calculatedValue
			end
		end
	end
	return output
end

-- amount of y that fits in x
local function Div(operand1: Recipe, operand2: Recipe): number
	local min=1/0
	for k,v in operand2 do
		local new=(operand1[k] or 0)//v
		if new<min then min=new end
	end
	return min
end

-- amount of y that exceeds x's values (probably all at once)
local function DivReq(operand1: Recipe, operand2: Recipe): number
	local max=0
	for k,v in operand2 do
		local new=math.ceil((operand1[k] or 0)/v)
		if new>max then max=new end
	end
	return max
end
local subMult = {1, -1}
local negative = {-1}
local binaryAdditionIndices = {1, 1}
local CurrentState: State?
local craftCounter = 0
local LiquidGas = ToRecipe(LiquidGas, ToID)

-- start of pilot.lua code
local function Merge(...) -- remove duplicates in stable
	local output={}
	local visited={}
	for _,parts in {...} do
		for _,part in parts do
			if visited[part]==nil then
				visited[part]=true
				output[#output+1]=part
			end
		end
	end
	return output
end
local MachineGUIDS: {
	[any]: resourceID
} = {}
type Sector = {any}
type MachineSectors = {
	[any]: Sector
}
type SectorSet = {
	[any]: boolean;
	length: number;
}
local MachineSectors: {[resourceID]: MachineSectors} = {}
local MachinePorts:{[string]:any}={ -- initial machine ports to connect
	Pulverizer=101;
	Kiln=102;
	Assembler=103;
	Melter=106;
	Hydroponic=107;
	Refinery=108;
	Pump=109;
	Boiler=104;
	SteamTurbine=105;
}
for deposit, index in MiningLaserDeposits do
	MachinePorts["MiningLaser " .. deposit] = index
end

local Machines:Machines = {}
local Ports : {any} = Network:GetParts("Port")
print(`amount of ports {#Ports}`)
local Parts = {}
for _, port in Ports do
	local portID = port.PortID
	local group = Parts[portID] or {}
	Parts[portID] = group
	group[port] = true
	--[[debug]]
	--[[
	print(port.PortID)
	local subnet = Network:GetSubnet(port)
	for _, i in subnet:GetPartsFromPort(port) do
		print("    ", i.ClassName)
	end
	for _, i in subnet:GetPartsFromPort(port,"PowerCell") do
		print("    ", i.ClassName)
	end
	--]]
	--[[debug]]
end
local function AddMachines(machineName: string)
	if not Parts[MachinePorts[machineName]] then return end
	local machineDescription = machineName:split(" ")
	local partName = machineDescription[1]
	if partName == "MiningLaser" and not MachineDefs[machineName] then
		local resource = machineDescription[2]:sub(1,-7)
		local machineID = ToID[machineName]
		local MiningLaser = AddDeposit(machineDescription[2], {resource})
		RegisterRecipe(MiningLaser[resource], machineID, MiningLaser, resource)
	end
	local machineID = ToID[machineName] -- ID associated with the machine's recipes
	local sectors: MachineSectors = MachineSectors[machineID] or {}
	local machines: Machines = Machines[machineID] or {}
	for machineSector, _ in Parts[MachinePorts[machineName]] do
		local subnet = Network:GetSubnet(machineSector)
		if MachineGUIDS[machineSector] then
			error("already exists")
			return
		end
		MachineGUIDS[machineSector] = machineID
		local switch = subnet:GetPartFromPort(machineSector, "Switch")
		local machinesInSector = subnet:GetPartsFromPort(machineSector, partName)
		sectors[#sectors + 1] = {switch, machinesInSector}
	end
	table.sort(sectors, function(x,y) return #x[2] > #y[2] end)
	for _, sector in sectors do
		for _, machinePart in sector[2] do
			machines[#machines + 1] = machinePart
		end
	end
	if #machines>0 then
		MachineSectors[machineID]=sectors
		Machines[machineID]=machines
	end
end
-- initialize storage system
local StorageSectors: {[number]: {any}} = {{},{},{}}
local ReservedStorageSectors: {[number]: {any}} = {{}, {}}
local FreeSectors: {[number]: SectorSet} = {{length=0},{length=0}}
local Allocation: {[resourceID]: SectorSet} = {}

local function _GetSectorStorage(sector,resources: Recipe?): Recipe
	local resources: Recipe = resources or {}
	local isPower = sector[1] == false
	for _, container in sector[2] do
		local containerResource = container:GetResource()
		if isPower and containerResource ~= "Power" then print("no filter for "..container.ClassName) end
		if not containerResource or containerResource == "nil" then
			continue
		end
		local resource = ToID[containerResource]
		local amount = container:GetResourceAmount()
		resources[resource] = (resources[resource] or 0) + amount
	end
	return resources
end

local function AllocateContainers(resources, deallocate: boolean?)
	-- if resource == 1 then return end
	local numToAllocate: {{[resourceID]:number}} = {{},{}}
	local resourcesLeftToAllocate = {0,0}
	for resource, amount in resources do
		if resource == 1 then continue end
		local allocation:SectorSet = Allocation[resource] or {length=0}
		local storageGroup = if LiquidGas[resource] then 2 else 1
		local numToAllocate = numToAllocate[storageGroup]
		local allocate = math.ceil(amount / if storageGroup == 2 then 1250 else 1000) - allocation.length
		Allocation[resource] = allocation
		if allocate <= 0 then continue end
		numToAllocate[resource] = allocate
		resourcesLeftToAllocate[storageGroup] += 1
	end
	for storageGroup = 1, 2 do
		local numToAllocate = numToAllocate[storageGroup]
		local freeSectors = FreeSectors[storageGroup]
		local resourcesLeftToAllocate = resourcesLeftToAllocate[storageGroup]
		for sector, _ in freeSectors do
			if sector == "length" then continue end
			if resourcesLeftToAllocate == 0 then break end
			if not freeSectors[sector] then continue end
			-- if numContainers == 0 then print("no containers", storageGroup) end
			for resource, allocate in numToAllocate do -- find first allocation canidate -- `for resource,binsLeft in needsAssign do` reference
				local allocation = Allocation[resource]
				allocation[sector] = true
				allocation.length += 1
				local resourceName = FromID[resource]
				sector.Resource = resourceName
				freeSectors[sector] = nil
				freeSectors.length -= 1
				numToAllocate[resource] -= 1
				if numToAllocate[resource] == 0 then
					numToAllocate[resource] = nil
					resourcesLeftToAllocate -= 1
				end
				break
			end
		end
	end
	--[[
	if numToAllocate <= 0 then
		if not deallocate then return end
		for sector, _ in StorageSectors[storageGroup] do
			if not allocation[sector] then continue end
			local resources = GetSectorStorage(sector)
			if resources[resource] then continue end
			local numContainers = #sector[2]
			if -numToAllocate < numContainers then continue end
			allocation[sector] = nil
			allocation.length -= numContainers
			freeSectors[sector] = true
			freeSectors.length += numContainers
			numToAllocate += numContainers
			if numToAllocate == 0 then return end
		end
		return
	end
	]]
end
local function ReloadStorage(): Recipe
	local ReservedStorage = Network:GetSubnet(111)
	local totalResources: Recipe = {}
	-- remember Solid, Liquid, and Gas filters connecting to network as well :skull:
	-- power doesn't need a filter
	FreeSectors = {{length=0},{length=0}}
	Allocation = {}
	StorageSectors = {
		Network:GetParts("Bin"),
		Network:GetParts("Tank"),
		Merge(Network:GetParts("PowerCell"), Network:GetParts("Battery"), Network:GetParts("DevBattery"))
	}
	ReservedStorageSectors = {
		ReservedStorage:GetParts("Bin"),
		ReservedStorage:GetParts("Tank")
	}
	-- AR TEST
		--[[
		if filter then
			local part = Instance.new("Part")
			part.Size = filter.Size
			part.CFrame = filter.CFrame
			part.Parent = Main:GetPart("ARController"):GetCanvas("3D")
		end
		--]]
	for storageGroup, sectors in StorageSectors do
		for _, sector in sectors do
			local containerResource = sector:GetResource()
			local resource: number? = if tostring(containerResource) == "nil" then nil else ToID[containerResource]
			if resource then
				totalResources[resource] = (totalResources[resource] or 0) + sector:GetResourceAmount()
			end
			if storageGroup == 3 then continue end
			if resource then
				local allocation:SectorSet = Allocation[resource] or {length=0}
				Allocation[resource] = allocation
				allocation[sector] = true
				sector.Resource = FromID[resource]
				allocation.length += 1
			else
				local freeStorage = FreeSectors[storageGroup]
				freeStorage[sector] = true
				sector.Resource = "None"
				freeStorage.length += 1
			end
		end
	end
	for storageGroup, sectors in ReservedStorageSectors do
		for _, sector in sectors do
			local binResource = sector:GetResource()
			local containerResource = tostring(binResource) ~= "nil" and sector:GetResource() or sector.Resource
			local resource: number? = if containerResource == "None" then nil else ToID[containerResource]
			if resource then
				totalResources[resource] = (totalResources[resource] or 0) + sector:GetResourceAmount()
				local allocation:SectorSet = Allocation[resource] or {length=0}
				Allocation[resource] = allocation
				allocation[sector] = true
				allocation.length += 1
			end
		end
	end
	return totalResources
end
-- initialize machine registry
--[[
for _,i in  Main:GetParts() do
	print(i.ClassName)
	if i.ClassName == "Port" then print(i.PortID) end
end]]
for machineName, portNum in MachinePorts do
	AddMachines(machineName)
end
local PlanetaryCraft: Memoized<number, number> = Memoized.new(function(resc,storage)
	local crafts = GetConfig[resc]
	if not crafts then return nil end
	for _,craft in crafts do
		local recipe = Recipes[craft]
		local machines = Machines[recipe.Machine]
		if not machines or #machines == 0 then continue end
		return craft
	end
	return nil
end, {})
local switchValues = {}
local function assignValues(machine:resourceID)
	local sectors = MachineSectors[machine]
	local values = {}
	local accumulator = 0
	local numSectors = #sectors
	for i = numSectors, 1, -1 do
		local sector = sectors[i]
		local switch = sector[1]
		if not switch then print("no switch found", FromID[machine]) end
		accumulator += #sector[2]
		values[i] = accumulator
	end
	switchValues[machine] = values
	return values
end
local function AdjustSwitches(machine:resourceID, target:number, switchConfigs)
	local target = math.ceil(target)
	local sectors = MachineSectors[machine]
	local values = switchValues[machine] or assignValues(machine)
	local usedMachines = {}
	local unusedMachines = {}
	for index, sector in sectors do
		local sectorValue = #sector[2]
		local switch = sector[1]
		if sectorValue > target then
			if (values[index + 1] or 0) < target then
				switchConfigs[switch] = true
				for _,machine in sector[2] do
					usedMachines[#usedMachines + 1] = machine
				end
				target = 0
				continue
			end
		elseif target > 0 and values[index] >= target then
			switchConfigs[switch] = true
			for _,machine in sector[2] do
				usedMachines[#usedMachines + 1] = machine
			end
			target -= sectorValue
			continue
		end
		switchConfigs[switch] = false
		for _,machine in sector[2] do
			unusedMachines[#unusedMachines + 1] = machine
		end
	end
	if target > 0 then
		error("not enough machines (2)")
	end
	return usedMachines, unusedMachines, switchConfigs
end
local AssemblerID = ToID.Assembler
local Assemblers = Machines[AssemblerID]
local EmptyList: {} = {}
local function Craft(state: State, machineUsage, machine, craftingOperations, machineConfigs: {[any]:{[string]:any}}, switchConfigs)
	-- print("empty error")
	local usedMachines, unusedMachines = AdjustSwitches(machine, machineUsage[machine] or 0, switchConfigs)
	local machineConfig = MachineTypes[machine].Config
	local configs = machineConfigs
	-- set switch state
	if #usedMachines == 0 then return end
	--db(FromID[machine], #usedMachines, machineUsage[machine])
	local machineIndex = 1
	if not machineConfig then
		for craft, amount in craftingOperations do
			local recipe = Recipes[craft]
			Add({amount}, {recipe.Output}, state.Resources.Storage)
		end
		return
	end
	for craft, amount in craftingOperations do
		local recipe = Recipes[craft]
		Add({amount}, {recipe.Output}, state.Resources.Storage)
		local recipeName = recipe.Name
		for i = machineIndex, machineIndex + amount - 1 do
			configs[usedMachines[i]] = {machineConfig, recipeName}
		end
		machineIndex += amount
	end
	for i = machineIndex, #usedMachines do
		configs[usedMachines[i]] = {machineConfig, ""}
	end
end
local machineConfigs = {}
local function OnMachineTick(state: State, System: System)
	db("tick")
	for machinePart, config in machineConfigs do
		machinePart[config[1]] = config[2]
	end
	local generationLimit = Add(subMult, {state.Resources.Capacity, state.Resources.Storage})
	local machineUsage: {[resourceID]: number} = {}
	local newCraftsGroups={}
	local isEmpty = true
	for craft, count in state.CraftQueue do
		isEmpty = false
		local recipe: Config = Recipes[craft]
		local machine = recipe.Machine
		local numMachines = #Machines[machine]
		if (machineUsage[machine] or 0) >= numMachines then continue end
		local amount=math.min(
			count, -- how many is needed to complete the job
			Div(generationLimit,recipe.Output), -- how many can be crafted before filling up bins
			Div(state.Resources.Storage,recipe.Input), -- how many can be crafted with these resources
			numMachines - (machineUsage[machine] or 0) -- how many resources can be produced by machines at once
		)
		db(	FromID[craft],
			count, -- how many is needed to complete the job
			Div(generationLimit,recipe.Output), -- how many can be crafted before filling up bins
			Div(state.Resources.Storage,recipe.Input), -- how many can be crafted with these resources
			numMachines - (machineUsage[machine] or 0) -- how many resources can be produced by machines at once
		)
		--debugRecipe(state.Resources.Storage)
		if amount == 0 then continue end
		Add({-amount}, {recipe.Input}, state.Resources.Storage)
		--[[db("assembling", FromID[craft], amount, ":",
			FromRecipe(recipe.Input,FromID),
			Div(state.Resources.Storage,recipe.Input)
		)]]
		Add({-amount}, {{[craft] = 1}}, state.CraftQueue)
		local newCrafts = newCraftsGroups[machine]
		if not newCrafts then
			newCrafts = {}
			newCraftsGroups[machine] = newCrafts
		end
		Add({amount},{{[craft] = 1}}, newCrafts)
		machineUsage[machine] = (machineUsage[machine] or 0) + amount
	end
	machineConfigs = {}
	local switchConfigs = {}
	if isEmpty then
		print("nothing to assemble")
		for machine, machines in Machines do
			Craft(state, {}, machine, EmptyList, machineConfigs, switchConfigs)
		end
	else
		for machine, _ in Machines do
			Craft(state, machineUsage, machine, newCraftsGroups[machine] or EmptyList, machineConfigs, switchConfigs)
		end
		craftCounter += 1
	end
	for switch, config in switchConfigs do
		switch.SwitchValue = config
	end
	return isEmpty
end
local System:System
function Produce(mode: boolean, recipe: Recipe): (State, string?)
	local resources = ReloadStorage()
	local capacity = {}
	local target
	if mode then
		target = {}
		for i, j in recipe do
			target[i] = (resources[i] or 0) + j
		end
	else
		target = recipe
	end
	local state = {
		Target = target;
		Resources = {Storage = resources, Capacity = capacity};
		CraftQueue = {};
		ResourceQueue = Add(subMult,{target, resources});
		Repeat = if mode then recipe else nil;
	}
	debugRecipe(resources)
	local allocation = {}
	for i = 1, 10 do
		local isRecursionEmpty = true
		for resource, amount in state.ResourceQueue do
			if amount <= 0 then continue end
			isRecursionEmpty = false
			local craft = PlanetaryCraft[resource]
			--db(`{FromID[resource]}: {amount}, {FromID[craftID or 1]}`)
			if not craft then
				CurrentState = nil
				return state, `produce: Missing recipe or insufficient resources of '{FromID[resource]}'.`
			end -- not enough resources
			local recipe: Config = Recipes[craft]
			local count = DivReq(state.ResourceQueue, recipe.Output)
			if count <= 0 then continue end
			Add({-count}, {recipe.Output}, state.ResourceQueue)
			Add({count}, {recipe.Input}, state.ResourceQueue)
			Add({count}, {{[craft] = 1}}, state.CraftQueue)
			for k, v in recipe.Output do
				allocation[k] = math.max(allocation[k] or 0, v)
			end
			for k, v in recipe.Input do
				allocation[k] = math.max(allocation[k] or 0, v)
			end
		end
		if isRecursionEmpty then
			print("nothing left to recurse")
			break
		end
	end
	for k, v in target do
		allocation[k] = math.max(allocation[k] or 0, v)
	end
	debugRecipe(allocation)
	AllocateContainers(allocation)
	for resource, sectors in Allocation do
		local numContainers = sectors.length
		local storageGroup = if LiquidGas[resource] then 2 else 1
		capacity[resource] = (
			if storageGroup == 1 then numContainers * 1000
				elseif storageGroup == 2 then numContainers * 10000
				else numContainers * 200000
		)
	end
	local power = 0
	for _, sector in StorageSectors[3] do
		power += 200000
	end
	capacity[1] = power
	debugRecipe(capacity)
	if not mode then
		machineConfigs = {}
	end
	CurrentState = state
	return state, if mode then `produce: Repeating...` else `produce: Objective set.`
end
--local safecallDebug = false
--local function safecall<x...,y...>(func:(x...)->y...):any  return (function(...)local err={pcall(func,...)} if safecallDebug then print("safecall ran") end if not table.unpack(err,1,1) then print(table.unpack(err,2,2)) else return table.unpack(err,2) end end) end
local Disk = GetPart("Disk")
local Speaker = GetPart("Speaker")
local Keyboard = GetPart("Keyboard")
local EntireDisk = Disk:ReadAll()
local Events: {[string]: (...any)->()} = {}
local function Scan()

end
function Events.Detected(machine, port)
	System.DisplayMessage("Notify", `Found {machine} at {port}`)
end
-- KEYBOARD CODE START
local function DisplayMessage(context: any, message: string)
	print(message)
	if context == "Keyboard" or context == "Microphone" or context == "Notify" then
		Speaker:Chat(message)
	end
end
System = {
	Produce = Produce;
	AddMachines = AddMachines;
	DisplayMessage = DisplayMessage;
}
local function ExecuteCommand(context: any, ...)
	local commands = table.pack(...)
	local command = commands[1]:lower()
	if command == "produce.set" or command == "produce.repeat" then
		local target = {}
		local repeating = command == "produce.repeat"
		local resource: number? = nil
		for i = 2, #commands do
			if resource == nil then
				resource = ToID[commands[i]]
			else
				target[resource] = tonumber(commands[i]) or 1
				resource = nil
			end
		end
		local state, message = Produce(repeating, target)
		if message then DisplayMessage(context, message) end
	elseif command == "produce.clear" then
		CurrentState = nil
		System.DisplayMessage(context, "produce: Objective cleared.")
	elseif command == "scan" then
		Scan()
		System.DisplayMessage(context, `scan: Completed`)
	else
		System.DisplayMessage(context, "terminal: Unrecognized command.")
	end
end
local Reserving = false
GetPart("Transformer").Loop:Connect(function()
	task.wait(0.2)
	if CurrentState and not Reserving and OnMachineTick(CurrentState, System) then
		local state = CurrentState
		if not CurrentState then System.DisplayMessage("Notify", "Sending commands too fast!") end
		if state.Repeat then
			Reserving = true
			task.wait(1.2)
			Reserving = false
			if state ~= CurrentState then return end
			local _, message = System.Produce(true, state.Repeat)
			System.DisplayMessage("Notify", message)
		else
			CurrentState = nil
			System.DisplayMessage("Notify", "produce: Objective reached.")
		end
	end
end)
Keyboard.TextInputted:Connect(function(text: string, player: string)
	local commands = text:sub(1,-2):split(" ")
	ExecuteCommand("Keyboard", table.unpack(commands))
end)
