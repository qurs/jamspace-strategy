_G.GAMETHREAD = {}

local net = require('coro-net')
local fs = require('fs')
_G.json = require('json')

assert(loadfile('sv_game.lua'))()
assert(loadfile('sv_messages.lua'))()
assert(loadfile('sv_sync_data.lua'))()
assert(loadfile('sv_client.lua'))()

GAMETHREAD.membersByID = {}
GAMETHREAD.gameData = {}
GAMETHREAD.year = 1699

local savedIDMove = false

local function handleMove(client, data)
	if not data[2] then return end
	if type(data[2]) ~= 'number' then return end
	if not game.actions[data[2]] then return end

	return data[2]
end

local function clearConsoleForAll()
	for k, v in pairs(GAMETHREAD.getClients()) do
		if not v:Alive() then
			v:Remove()
		else
			v.write(json.encode{ 'clear' })
			v.read()
		end
	end
end

local function getAllArmy(member)
	local army = 0

	for k, v in pairs(member.regions) do
		army = army + v
	end

	return army
end

local function getArmySupply(member)
	local army = getAllArmy(member)
	if army <= 0 then return 0 end

	local m = member.equipment / army

	return math.floor(m * 100)
end

function GAMETHREAD.loadGameData()
	local raw = fs.readFileSync('sv_data.txt')
	if raw then
		GAMETHREAD.gameData = json.decode(raw)
	else
		raw = fs.readFileSync('sv_data.txt.example')
		fs.writeFileSync('sv_data.txt', raw)
		GAMETHREAD.gameData = json.decode(raw)
	end
end

function GAMETHREAD.endGame()
	os.execute('cls')
	clearConsoleForAll()

	print('Игра окончена!')
	GAMETHREAD.printForAll('Игра окончена!')
end

function GAMETHREAD.nextMove()
	GAMETHREAD.loadGameData()

	if GAMETHREAD.isWaiting() then return GAMETHREAD.nextMove() end

	local v
	local name

	if not currentIDMove then
		currentIDMove = 1
		name = GAMETHREAD.membersByID[currentIDMove]
		v = game.members[name]
	else
		if savedIDMove then
			savedIDMove = false
		else
			currentIDMove = currentIDMove + 1
		end

		if not GAMETHREAD.membersByID[currentIDMove] then
			currentIDMove = 1
		end

		name = GAMETHREAD.membersByID[currentIDMove]
		v = game.members[name]
	end

	local client = GAMETHREAD.getClientByIpPort(v.ip, v.port)
	if not client:Alive() then
		client:Remove()
		return GAMETHREAD.nextMove()
	end

	os.execute('cls')
	clearConsoleForAll()
	GAMETHREAD.syncMembers()
	GAMETHREAD.syncNeighbors()

	if currentIDMove == 1 then
		GAMETHREAD.printMessages()
		GAMETHREAD.year = GAMETHREAD.year + 1

		print('\n')
	end

	print('ГОД: ' .. GAMETHREAD.year)
	GAMETHREAD.printForAll('ГОД: ' .. GAMETHREAD.year)

	print('Ход игрока: ' .. name)
	print('=======================')
	print('Военный резерв: ' .. v.milScore)
	print('ФВН: ' .. v.milXP)
	print('Надбавка к шансам исследований: +' .. v.chanceAdd)
	print('Ресурсы: ' .. v.resources)
	print( ('Снабжение армии: %s%%'):format( getArmySupply(v) ) )
	print('=======================')

	print('Регионы:')
	for regionName, defend in pairs(v.regions) do
		print('- ' .. regionName .. ' = ' .. defend)
	end

	local saveData = {
		members = game.members,
		currentIDMove = currentIDMove,
		membersByID = GAMETHREAD.membersByID,
		year = GAMETHREAD.year,
	}

	local file = io.open('last_save.json', 'w')
	if file then
		file:write(json.encode(saveData))
		file:flush()
		file:close()
	end

	for id, otherClient in pairs(GAMETHREAD._clients) do
		if otherClient == client then goto continue end

		otherClient.write(json.encode{ 'my_stat' })
		otherClient.read()

		::continue::
	end

	if client then
		client.write(json.encode{ 'move', client.name })

		GAMETHREAD.waitForAnswer(client, client.name, 'move', handleMove,
			function(client)
				client.write(json.encode{ 'move', client.name })
			end,
			function(client, move, ...)
				math.randomseed(os.clock() * 26)
				game.actions[move](client, client.name, ...)
			end
		)
	end
end

print('Сколько ждать игроков?')
local maxPlayers = tonumber(io.read())
while not maxPlayers or maxPlayers < 1 do
	maxPlayers = tonumber(io.read())
end

maxPlayers = math.floor(maxPlayers)

local playerCount = 0

local lastSaveData = fs.readFileSync('last_save.json')
local saveLoaded = false

if lastSaveData then
	local saveData = json.decode(lastSaveData)

	game.members = saveData.members
	currentIDMove = saveData.currentIDMove
	GAMETHREAD.membersByID = saveData.membersByID
	GAMETHREAD.year = saveData.year

	savedIDMove = true
	saveLoaded = true
end

net.createServer({
	host = '0.0.0.0',
	port = 1337,
},
function(read, write, dsocket)
	local raw = read()
	if not raw then return dsocket:close() end

	local data = json.decode(raw)
	if not data then return dsocket:close() end

	local peer = dsocket:getpeername()
	local ip, port = peer.ip, peer.port

	local client = GAMETHREAD.getClientByIpPort(ip, port)
	if not client then
		if game.started then return dsocket:close() end

		if data[1] ~= 'nick' then return dsocket:close() end
		if not data[2] or data[2] == '' then return dsocket:close() end

		local nick = data[2]

		local attempt = 1
		while GAMETHREAD.getClientByName(nick) do
			attempt = attempt + 1
			nick = ('%s (%d)'):format(data[2], attempt)
		end

		GAMETHREAD.newClient(ip, port, {
			name = nick,
			read = read,
			write = write,
			socket = dsocket,
		})

		print('Новый игрок: ' .. nick)

		game.newPlayer(nick, ip, port)
		GAMETHREAD.syncMembers()

		playerCount = playerCount + 1

		if playerCount >= maxPlayers then
			game.started = true

			if not saveLoaded and #GAMETHREAD.membersByID < 1 then
				local id = 0
				for name, v in pairs(game.members) do
					id = id + 1

					GAMETHREAD.membersByID[id] = name
				end
			end

			GAMETHREAD.nextMove()
		end
	else
		client:HandleAnswer(data)
	end
end)