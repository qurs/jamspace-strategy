local Client = {}
Client.__index = Client

GAMETHREAD._clients = {}
GAMETHREAD._waitingAnswer = {}

function GAMETHREAD.isWaiting()
	for k, v in pairs(GAMETHREAD._waitingAnswer) do
		return true
	end

	return false
end

function GAMETHREAD.waitForAnswer(client, name, act, handle, askFunc, success)
	GAMETHREAD._waitingAnswer[name] = {
		act = act,
		handle = handle,
		askFunc = askFunc,
		success = success,
	}

	client:GetAnswer()
end

function GAMETHREAD.getClients()
	return GAMETHREAD._clients
end

function GAMETHREAD.getClientByIpPort(ip, port)
	return GAMETHREAD._clients[ip .. ':' .. port]
end

function GAMETHREAD.getClientByName(name)
	for k, v in pairs(GAMETHREAD._clients) do
		if v.name == name then
			return v
		end
	end
end

function Client:_removeID()
	local i
	for id, name in ipairs(GAMETHREAD.membersByID) do
		if name == self.name then
			i = id
			break
		end
	end
	if not i then return end

	table.remove(GAMETHREAD.membersByID, i)
end

function Client:Remove(bCloseConnection)
	self:_removeID()

	if bCloseConnection then
		GAMETHREAD._clients[self.ip .. ':' .. self.port].socket:close()
	end

	GAMETHREAD._clients[self.ip .. ':' .. self.port] = nil

	if #GAMETHREAD.membersByID < 2 then
		GAMETHREAD.endGame()
		return true
	end

	return false
end

function Client:HandleAnswer(ans)
	local needle = GAMETHREAD._waitingAnswer[self.name]
	if not needle then return end

	if ans[1] ~= needle.act then return end

	local data = {needle.handle(self, ans)}
	if data and #data > 0 then
		GAMETHREAD._waitingAnswer[self.name] = nil
		needle.success(self, unpack(data))
	else
		needle.askFunc(self)
	end
end

function Client:GetAnswer()
	local dsocket = self.socket
	local raw = self.read()
	if not raw then return dsocket:close() end

	local data = json.decode(raw)
	if not data then return dsocket:close() end

	local peer = dsocket:getpeername()
	local ip, port = peer.ip, peer.port

	if not GAMETHREAD._clients[ip .. ':' .. port] then return end

	self:HandleAnswer(data)
end

function Client:Alive()
	local ok = pcall(self.write, json.encode{ 'checkAlive' })
	if not ok then return false end
	ok, answer = pcall(self.read)
	if not ok or answer ~= 'i am alive' then return false end

	return true
end

function GAMETHREAD.newClient(ip, port, data)
	data.ip = ip
	data.port = port

	local client = setmetatable(data, Client)
	GAMETHREAD._clients[ip .. ':' .. port] = client

	return client
end