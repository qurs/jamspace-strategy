local VERSION = 'v1.0.1'

local net = require('coro-net')
local json = require('json')
local inflate = require('inflate')
local fs = require('fs')
local http = require('coro-http')

local userAgent = 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.61 Safari/537.36'
local repoURL = 'https://api.github.com/repos/qurs/jamspace-hoi4/releases/latest'
local downloadUpdateURL = 'https://github.com/qurs/jamspace-hoi4/archive/refs/heads/master.zip'

local function getLatestVersion()
	local _, body = http.request('GET', repoURL, {{'User-Agent', userAgent}})
	if not body then return end

	local data = json.decode(body)
	if not data then return end

	return data.tag_name
end

local function downloadFile(url, name)
	local _, body = http.request('GET', url)
	if not body then return end

	return fs.writeFileSync(name, body)
end

local function unzipFile(fileName, excludeDir)
	local stream = inflate:new(fs.readFileSync(fileName))
	for name, offset, size, packed in stream:files() do
		if name:sub(-1) == '/' and name ~= excludeDir then
			fs.mkdirSync(excludeDir and name:gsub(excludeDir, '') or name)
		else
			local content
			if packed then
				content = stream:inflate(offset)
			else
				content = stream:extract(offset, size)
			end

			fs.writeFileSync(excludeDir and name:gsub(excludeDir, '') or name, content)
		end
	end
end

-- do
-- 	local lastVersion = getLatestVersion()
-- 	if not lastVersion then
-- 		print('Не удалось получить последнюю версию! Авто-обновление не сработает!')
-- 	elseif lastVersion ~= VERSION then
-- 		local ok = downloadFile(downloadUpdateURL, 'temp.zip')
-- 		if not ok then return print('Не удалось скачать ZIP-файл для обновления!') end

-- 		unzipFile('temp.zip', 'jamspace%-hoi4%-master/')
-- 		fs.unlinkSync('temp.zip')

-- 		print('Клиент успешно обновлен!')
-- 	else
-- 		print('Установлена последняя версия: ' .. VERSION)
-- 	end
-- end

local NICK
local members = {}
local neighbors = {}

local gameCycle

local read, write
local function tryConnect(ipAddress)
	local host = ipAddress or '127.0.0.1'

	if not ipAddress then
		local ip = fs.readFileSync('ip.txt')
		if ip then
			host = ip
		else
			ip = fs.readFileSync('ip.txt.example')
			fs.writeFileSync('ip.txt', ip)
			host = ip
		end
	end

	read, write, dsocket = net.connect({
		host = host,
		port = 1337,
	})
end
tryConnect()

local function diplomacy()
	local i = 0
	local players = {}

	for name, v in pairs(members) do
		i = i + 1
		players[i] = name

		print( ('[%d] - %s'):format(i, name) )
	end

	local select = tonumber( io.read() )
	while not select or select < 1 or select > #players do
		select = tonumber( io.read() )
	end

	local name = players[select]
	local ply = members[name]

	os.execute('cls')

	print('Регионы:')
	for regionName in pairs(ply.regions) do
		print('> ' .. regionName)
	end

	print('[0] - Назад')

	local move = tonumber( io.read() )
	while not move or move ~= 0 do
		move = tonumber( io.read() )
	end

	os.execute('cls')
	gameCycle({'move'})
end

local actions = {
	[1] = function()
	end,
	[2] = function()
		print('-> Введи ник цели')

		local target = io.read()
		while not members[target] do
			print('Неправильная цель')
			target = io.read()
		end

		print('-> Введи регион')

		local region = io.read()
		while not region or region == '' or not members[target].regions[region] or not neighbors[region] do
			print('Неправильный регион')
			region = io.read()
		end

		print('-> Введи регион, откуда будешь вести атаку')

		local fromRegion = io.read()
		while not fromRegion or fromRegion == '' or not members[NICK].regions[fromRegion] or not neighbors[region][fromRegion] or members[NICK].regions[fromRegion] <= 0 do
			print('Неправильный регион')
			fromRegion = io.read()
		end

		print('-> Введи значение атаки')

		local attack = tonumber( io.read() )
		while not attack or attack > members[NICK].regions[fromRegion] do
			print('Неправильное значение атаки')
			attack = tonumber( io.read() )
		end

		write(json.encode{ 'action_move', attack, target, region, fromRegion })
	end,
	[3] = function()
		print('-> Введи что хочешь исследовать')
		print('[1] - Реформа армии')
		print('[2] - Реклама службы по контракту')
		print('[3] - Реформа высшего образования')

		local move = tonumber( io.read() )
		while not move or (move ~= 1 and move ~= 2 and move ~= 3) do
			print('Неправильное исследование!')
			move = tonumber( io.read() )
		end

		write(json.encode{ 'action_move', move })
	end,
	[4] = function()
		if members[NICK].milScore < 1 then
			os.execute('cls')

			print('У тебя не хватило военного резерва для захвата свободной территории')
			gameCycle({'move'})

			return
		end

		print('-> Введи название региона')

		local region = io.read()
		while not region or region == '' do
			print('Неправильный регион!')
			region = io.read()
		end

		write(json.encode{ 'action_move', region })
	end,
	[5] = function()
		print('-> Введи название региона')

		local region = io.read()
		while not members[NICK].regions[region] do
			print('Неправильный регион!')
			region = io.read()
		end

		print('-> Введи кол-во военных')

		local defend = tonumber( io.read() )
		while not defend or defend > members[NICK].milScore do
			print('У тебя нет столько свободных военных!')
			defend = tonumber( io.read() )
		end

		write(json.encode{ 'action_move', region, defend })
	end,
	[6] = function()
		print('-> Введи название региона')

		local region = io.read()
		while not members[NICK].regions[region] do
			print('Неправильный регион!')
			region = io.read()
		end

		print('-> Введи кол-во военных')

		local undefend = tonumber( io.read() )
		while not undefend or undefend > members[NICK].regions[region] do
			print('В этом регионе нет столько военных!')
			undefend = tonumber( io.read() )
		end

		write(json.encode{ 'action_move', region, undefend })
	end,
	[7] = function()
		print('-> Откуда? (название региона)')

		local fromRegion = io.read()
		while not members[NICK].regions[fromRegion] or members[NICK].regions[fromRegion] <= 0 do
			print('Неправильный регион!')
			fromRegion = io.read()
		end

		print('-> Куда? (название региона)')

		local toRegion = io.read()
		while not members[NICK].regions[toRegion] do
			print('Неправильный регион!')
			toRegion = io.read()
		end

		print('-> Введи кол-во военных')

		local army = tonumber( io.read() )
		while not army or army > members[NICK].regions[fromRegion] do
			print('У тебя нет столько военных в этом регионе!')
			army = tonumber( io.read() )
		end

		write(json.encode{ 'action_move', fromRegion, toRegion, army })
	end,
	[8] = function()
	end,
	[9] = function()
	end,
}

local function getAllArmy()
	local army = 0

	for k, v in pairs(members[NICK].regions) do
		army = army + v
	end

	return army
end

local function getArmySupply()
	local army = getAllArmy()
	if army <= 0 then return 0 end

	local m = members[NICK].equipment / army

	return math.floor(m * 100)
end

gameCycle = function(data)
	if data[1] == 'move' then
		print('[1] - Мобилизация\n[2] - Атака на регион\n[3] - Исследование\n[4] - Захват свободной территории\n[5] - Поставить военных в регион\n[6] - Забрать военных с региона\n[7] - Переместить военных из региона в регион\n[8] - Добывать ресурсы\n[9] - Производство оружия\n[10] - Дипломатия (Не тратит ход)')
		print('=========================')
		print('Твои показатели:')
		print('Военный резерв: ' .. members[NICK].milScore)
		print('Фактор военнообязанного населения: ' .. members[NICK].milXP)
		print('Надбавка к шансам исследования: +' .. members[NICK].chanceAdd)
		print('Ресурсы: ' .. members[NICK].resources)
		print( ('Снабжение армии (не считая резерв): %s%%'):format( getArmySupply() ) )
		print('=========================')

		print('Регионы:')
		for regionName, defend in pairs(members[NICK].regions) do
			print('- ' .. regionName .. ' = ' .. defend)
		end

		local move = tonumber( io.read() )
		while not move or (not actions[move] and move ~= (#actions + 1)) do
			move = tonumber( io.read() )
		end

		if move == (#actions + 1) then
			diplomacy()
		else
			write(json.encode{ 'move', move })
		end
	elseif data[1] == 'print' then
		print(data[2])
		write(1)
	elseif data[1] == 'clear' then
		os.execute('cls')
		write(1)
	elseif data[1] == 'get_members' then
		members = data[2]
		write(1)
	elseif data[1] == 'get_neighbors' then
		neighbors = data[2]
		write(1)
	elseif data[1] == 'action_move' then
		actions[data[2]]()
	elseif data[1] == 'my_stat' then
		print('=========================')
		print('Твои показатели:')
		print('Военный резерв: ' .. members[NICK].milScore)
		print('Фактор военнообязанного населения: ' .. members[NICK].milXP)
		print('Надбавка к шансам исследования: +' .. members[NICK].chanceAdd)
		print('Ресурсы: ' .. members[NICK].resources)
		print( ('Снабжение армии (не считая резерв): %s%%'):format( getArmySupply() ) )
		print('=========================')

		print('Регионы:')
		for regionName, defend in pairs(members[NICK].regions) do
			print('- ' .. regionName .. ' = ' .. defend)
		end

		write(1)
	elseif data[1] == 'checkAlive' then
		write('i am alive')
	end
end

print('Введи айпи адрес: ')
local ipAddress = io.read()

while not read do
	print('Попытка переподключиться...')
	tryConnect(ipAddress)
end

print('Введи никнейм: ')
NICK = io.read()

write(json.encode{ 'nick', NICK })



while true do
	if not read then
		return print('Ты был отключен от сервера!')
	else
		local raw = read()
		if not raw then
			return print('Ты был отключен от сервера!')
		end

		local data = json.decode(raw)
		if data then
			gameCycle(data)
		end
	end
end