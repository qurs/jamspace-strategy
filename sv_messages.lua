GAMETHREAD.answers = {}
GAMETHREAD.personalAnswers = {}

function GAMETHREAD.printForClient(client, msg)
	client.write(json.encode{ 'print', msg })
	client.read()
end

function GAMETHREAD.printForAll(msg)
	for k, v in pairs(GAMETHREAD.getClients()) do
		if not v:Alive() then
			v:Remove()
		else
			v.write(json.encode{ 'print', msg })
			v.read()
		end
	end
end

function GAMETHREAD.addMessage(msg, format, ...)
	local msg = msg
	if format then msg = msg:format(...) end

	GAMETHREAD.answers[#GAMETHREAD.answers + 1] = msg
end

function GAMETHREAD.addPersonalMessage(client, msg, format, ...)
	local msg = msg
	if format then msg = msg:format(...) end

	GAMETHREAD.personalAnswers[client] = GAMETHREAD.personalAnswers[client] or {}
	GAMETHREAD.personalAnswers[client][#GAMETHREAD.personalAnswers[client] + 1] = msg
end

function GAMETHREAD.printMessages()
	if #GAMETHREAD.answers > 0 then
		for _, msg in ipairs(GAMETHREAD.answers) do
			print(msg)
			GAMETHREAD.printForAll(msg)
		end
		GAMETHREAD.answers = {}
	end

	for client, v in pairs(GAMETHREAD.personalAnswers) do
		for _, msg in ipairs(v) do
			print( ('[%s] > %s'):format(client.name, msg) )
			GAMETHREAD.printForClient(client, msg)
		end
	end
	GAMETHREAD.personalAnswers = {}
end