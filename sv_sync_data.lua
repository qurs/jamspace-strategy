function GAMETHREAD.syncMembers()
	for k, v in pairs(GAMETHREAD.getClients()) do
		if not v:Alive() then
			v:Remove()
		else
			v.write(json.encode{ 'get_members', game.members })
			v.read()
		end
	end
end

function GAMETHREAD.syncNeighbors()
	for k, v in pairs(GAMETHREAD.getClients()) do
		if not v:Alive() then
			v:Remove()
		else
			v.write(json.encode{ 'get_neighbors', GAMETHREAD.gameData.neighbors })
			v.read()
		end
	end
end