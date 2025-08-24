_G.game = {}
game.members = {}

local function preHandleAction(client, data)
	if data[1] ~= 'action_move' then return false end

	return true
end

local function haveNoRegions(name)
	for k, v in pairs(game.members[name].regions) do
		return false
	end

	return true
end

local function getActiveArmy(name)
	local army = 0

	for k, v in pairs(game.members[name].regions) do
		army = army + v
	end

	return army
end

local function getArmySupply(name)
	local army = getActiveArmy(name)
	if army <= 0 then return 0 end

	local equipment = game.members[name].equipment
	return math.min(equipment / army, 1)
end

local function Remap( value, inMin, inMax, outMin, outMax )
	return outMin + ( ( ( value - inMin ) / ( inMax - inMin ) ) * ( outMax - outMin ) )
end

local function getSupplyDebuff(supply)
	local supplyRemaped = Remap(supply, 0, 1, 1, 0)
	return math.min(supplyRemaped * GAMETHREAD.gameData.maxSupplyDebuff, 1)
end

local handles = {
	[2] = function(client, data)
		if not preHandleAction(client, data) then return end

		local name = client.name

		local attack = data[2]
		if not attack then return end

		local target = data[3]
		if not game.members[target] then return end

		local region = data[4]
		if not GAMETHREAD.gameData.neighbors[region] then return end
		if not game.members[target].regions[region] then return end

		local fromRegion = data[5]
		if not fromRegion or not game.members[name].regions[fromRegion] then return end
		if not GAMETHREAD.gameData.neighbors[region][fromRegion] then return end
		if attack > game.members[name].regions[fromRegion] then return end

		return attack, target, region, fromRegion
	end,

	[3] = function(client, data)
		if not preHandleAction(client, data) then return end

		local move = data[2]
		if not move or (move ~= 1 and move ~= 2 and move ~= 3) then return end

		return move
	end,

	[4] = function(client, data)
		if not preHandleAction(client, data) then return end

		local region = data[2]
		if not region or region == '' then return end

		return region
	end,

	[5] = function(client, data)
		if not preHandleAction(client, data) then return end

		local name = client.name

		local region = data[2]
		if not game.members[name].regions[region] then return end

		local defend = data[3]
		if not defend or defend > game.members[name].milScore then return end

		return region, defend
	end,

	[6] = function(client, data)
		if not preHandleAction(client, data) then return end

		local name = client.name

		local region = data[2]
		if not game.members[name].regions[region] then return end

		local undefend = data[3]
		if not undefend or undefend > game.members[name].regions[region] then return end

		return region, undefend
	end,

	[7] = function(client, data)
		if not preHandleAction(client, data) then return end

		local name = client.name

		local fromRegion = data[2]
		if not fromRegion or not game.members[name].regions[fromRegion] then return end

		local toRegion = data[3]
		if not toRegion or not game.members[name].regions[toRegion] then return end

		local army = data[4]
		if not army or army > game.members[name].regions[fromRegion] then return end

		return fromRegion, toRegion, army
	end,
}

local function tryChance(chance)
	local ch = chance / 100

	return math.random() <= ch
end

local function hasMilitaryInRegions(client)
	local regions = game.members[client.name].regions
	for k, v in pairs(regions) do
		if v > 0 then return true end
	end

	return false
end

local function hasNeighbors(client)
	local regions = game.members[client.name].regions
	for k, v in pairs(GAMETHREAD.gameData.neighbors) do
		for regionName in pairs(regions) do
			if v[regionName] then return true end
		end
	end

	return false
end

local function howMuchMobilize(name)
	local bonus = 0
	for region in pairs(game.members[name].regions) do
		local targetRegionType = GAMETHREAD.gameData.regionTypes[region]
		if targetRegionType then
			local regionProperties = GAMETHREAD.gameData.regionTypesProperties[targetRegionType]
			bonus = bonus + regionProperties.mobilization_force
		end
	end

	return math.floor(game.members[name].milXP * bonus)
end

game.actions = {
	[1] = function(client, name)
		local add = howMuchMobilize(name)

		game.members[name].milScore = game.members[name].milScore + add

		GAMETHREAD.addPersonalMessage(client, 'Ты нанял военного! (+%s военная сила)', true, add)
		-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' нанял военного! (+' .. add .. ' военная сила)'
		GAMETHREAD.nextMove()
	end,

	[2] = function(client, name)
		GAMETHREAD.loadGameData()

		if not hasMilitaryInRegions(client) then return GAMETHREAD.nextMove() end
		if not hasNeighbors(client) then return GAMETHREAD.nextMove() end

		client.write(json.encode{ 'action_move', 2, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[2],
			function(client)
				client.write(json.encode{ 'action_move', 2, name })
			end,
			function(client, attack, target, region, fromRegion)
				-- game.members[name].milScore = game.members[name].milScore - attack
				local supply = getArmySupply(name)

				game.members[name].regions[fromRegion] = game.members[name].regions[fromRegion] - attack

				local damage = attack
				local debuff = 0

				local targetRegionType = GAMETHREAD.gameData.regionTypes[region]
				if targetRegionType then
					local regionProperties = GAMETHREAD.gameData.regionTypesProperties[targetRegionType]
					debuff = math.min(debuff + regionProperties.debuff_on_attack, 100)
				end

				debuff = math.min(debuff + getSupplyDebuff(supply), 100)

				if debuff > 0 then
					damage = damage * ( (100 - debuff) / 100 )
				end

				local targetRegionDefend = game.members[target].regions[region]
				if targetRegionDefend < damage then
					local diff = damage - targetRegionDefend
					game.members[target].regions[region] = nil
					game.members[name].regions[region] = math.floor(diff)

					if haveNoRegions(target) then
						local ip = game.members[target].ip
						local port = game.members[target].port
						local targetClient = GAMETHREAD.getClientByIpPort(ip, port)

						if targetClient:Remove(true) == true then return end
					end

					GAMETHREAD.addMessage('%s успешно захватил регион %s!', true, name, region)
					GAMETHREAD.nextMove()
				else
					game.members[target].regions[region] = math.floor(game.members[target].regions[region] - damage)

					GAMETHREAD.addMessage('%s не смог захватить регион %s (нанесенный урон: %s). В регионе %s теперь %s военных!', true, name, region, damage, region, game.members[target].regions[region])
					GAMETHREAD.nextMove()
				end
			end
		)
	end,

	[3] = function(client, name)
		client.write(json.encode{ 'action_move', 3, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[3],
			function(client)
				client.write(json.encode{ 'action_move', 3, name })
			end,
			function(client, move)
				if move == 1 then
					if tryChance(GAMETHREAD.gameData.chances.reformaArmii + game.members[name].chanceAdd) then
						local add = GAMETHREAD.gameData.bonuses.reformaArmii

						game.members[name].milXP = game.members[name].milXP + add

						GAMETHREAD.addPersonalMessage(client, 'Ты успешно исследовал реформу армии (+%s Фактор военнообязанного населения)', true, add)
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = ('%s успешно исследовал реформу армии (+%s Фактор военнообязанного населения)'):format(name, add)
					else
						GAMETHREAD.addPersonalMessage(client, 'У тебя не получилось исследовать реформу армии')
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' не получилось исследовать реформу армии'
					end
				elseif move == 2 then
					if tryChance(GAMETHREAD.gameData.chances.reformaPriziva + game.members[name].chanceAdd) then
						local base = howMuchMobilize(name)
						local add = base * GAMETHREAD.gameData.bonuses.reformaPriziva

						game.members[name].milScore = game.members[name].milScore + add

						GAMETHREAD.addPersonalMessage(client, 'Ты успешно исследовал рекламу службы по контракту (мобилизация с бонусом x%s)', true, add)
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = ('%s успешно исследовал рекламу службы по контракту (+%s Военной силы)'):format(name, add)
					else
						GAMETHREAD.addPersonalMessage(client, 'У тебя не получилось исследовать рекламу службы по контракту')
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' не получилось исследовать рекламу службы по контракту'
					end
				elseif move == 3 then
					if game.members[name].chanceAdd >= 35 then
						GAMETHREAD.addPersonalMessage(client, 'Ты достиг максимальной надбавки к исследованиям!')
						return GAMETHREAD.nextMove()
					end

					if tryChance(GAMETHREAD.gameData.chances.reformaObrazovaniya + game.members[name].chanceAdd) then
						local add = GAMETHREAD.gameData.bonuses.reformaObrazovaniya

						game.members[name].chanceAdd = game.members[name].chanceAdd + add

						GAMETHREAD.addPersonalMessage(client, 'Ты успешно исследовал реформу высшего образования (+%s%% шанс ко всем исследованиям)', true, add)
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = ('%s успешно исследовал реформу высшего образования (+%s%% шанс ко всем исследованиям)'):format(name, add)
					else
						GAMETHREAD.addPersonalMessage(client, 'У тебя не получилось исследовать реформу высшего образования')
						-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' не получилось исследовать реформу высшего образования'
					end
				end

				GAMETHREAD.nextMove()
			end
		)
	end,

	[4] = function(client, name)
		client.write(json.encode{ 'action_move', 4, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[4],
			function(client)
				client.write(json.encode{ 'action_move', 4, name })
			end,
			function(client, region)
				if game.members[name].milScore < 1 then
					GAMETHREAD.addPersonalMessage(client, 'У тебя не хватило военного резерва для захвата свободной территории')
					GAMETHREAD.nextMove()
					return
				end

				game.members[name].regions[region] = 0
				game.members[name].milScore = game.members[name].milScore - 1

				GAMETHREAD.addMessage('%s захватил свободную территорию! (-1 военное очко)', true, name)
				GAMETHREAD.nextMove()
			end
		)
	end,

	[5] = function(client, name)
		client.write(json.encode{ 'action_move', 5, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[5],
			function(client)
				client.write(json.encode{ 'action_move', 5, name })
			end,
			function(client, region, defend)
				game.members[name].milScore = game.members[name].milScore - defend
				game.members[name].regions[region] = game.members[name].regions[region] + defend

				GAMETHREAD.addPersonalMessage(client, 'Ты поставил %s военных в регион %s', true, defend, region)
				-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' поставил ' .. defend .. ' военных на защиту региона ' .. region
				GAMETHREAD.nextMove()
			end
		)
	end,

	[6] = function(client, name)
		client.write(json.encode{ 'action_move', 6, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[6],
			function(client)
				client.write(json.encode{ 'action_move', 6, name })
			end,
			function(client, region, undefend)
				game.members[name].regions[region] = game.members[name].regions[region] - undefend
				game.members[name].milScore = game.members[name].milScore + undefend

				GAMETHREAD.addPersonalMessage(client, 'Ты забрал %s военных с региона %s', true, undefend, region)
				-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' забрал ' .. undefend .. ' военных с защиты региона ' .. region
				GAMETHREAD.nextMove()
			end
		)
	end,

	[7] = function(client, name)
		client.write(json.encode{ 'action_move', 7, name })
		GAMETHREAD.waitForAnswer(client, name, 'action_move', handles[7],
			function(client)
				client.write(json.encode{ 'action_move', 7, name })
			end,
			function(client, fromRegion, toRegion, army)
				game.members[name].regions[fromRegion] = game.members[name].regions[fromRegion] - army
				game.members[name].regions[toRegion] = game.members[name].regions[toRegion] + army

				GAMETHREAD.addPersonalMessage(client, 'Ты переместил %s военных из региона %s в регион %s', true, army, fromRegion, toRegion)
				-- GAMETHREAD.answers[#GAMETHREAD.answers + 1] = name .. ' поставил ' .. defend .. ' военных на защиту региона ' .. region
				GAMETHREAD.nextMove()
			end
		)
	end,

	[8] = function(client, name)
		local resources = 0
		for region in pairs(game.members[name].regions) do
			local targetRegionType = GAMETHREAD.gameData.regionTypes[region]
			if targetRegionType then
				local regionProperties = GAMETHREAD.gameData.regionTypesProperties[targetRegionType]
				resources = resources + regionProperties.resources
			end
		end

		game.members[name].resources = game.members[name].resources + resources

		GAMETHREAD.addPersonalMessage(client, 'Ты добыл %s ресурсов', true, resources)
		GAMETHREAD.nextMove()
	end,

	[9] = function(client, name)
		local resources = game.members[name].resources
		game.members[name].resources = 0

		game.members[name].equipment = game.members[name].equipment + resources

		GAMETHREAD.addPersonalMessage(client, 'Ты произвел %s оружия', true, resources)
		GAMETHREAD.nextMove()
	end,
}

function game.newPlayer(nick, ip, port)
	local member = game.members[nick]
	if member then
		member.ip = ip
		member.port = port
		return
	end

	game.members[nick] = {
		ip = ip,
		port = port,
		milScore = 10,
		milXP = 1,
		chanceAdd = 0,
		resources = 0,
		equipment = 0,
		regions = {},
	}
end