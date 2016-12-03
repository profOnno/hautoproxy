#!/usr/bin/env lua5.3
--socket = require "socket"
-- socket.unix = require "socket.unix"

--c = assert(socket.unix());
--assert(c:connect("/var/run/docker.sock"))
require "pl"
--http = require("socket.http")
unixHTTP= require("usock")
assert(unixHTTP)
json = require("cjson")
assert(json)
applyTemplate = require "pl.template".substitute

function updateConfig()
	-- Get running containers
	--b, c, h = http.request("http://localhost:8080/containers/json")
	h, b = unixHttp.request("/containers/json")
	-- print("b",b)
	res = json.decode(b)
	-- for key, val in pairs(res) do print (key, val) end
	print(pretty.write(res))
	print("----------")
	containers={}

	for a, b in ipairs(res) do
		local rec={}
		rec.Id=b.Id
		--strip front slash
		rec.Name=string.sub(b.Names[1],2,-1)
		print(rec.Name)
		--print("n ports:"..#b.Ports) --should show length

		--table.foreach(b.Ports, function(k,v)print( v.PrivatePort)end);
		--if hasPort80(b.Ports) then print(rec.Name.." yup") else print(rec.Name.." nup") end
		--if hasPort80(b.Ports) then
		if b.Labels.hautoproxy then
			print("Labels :")
			print("hautoproxy:")
			print(b.Labels.hautoproxy)
			print("cname:")
			print(b.Labels.cname)
			print("domain:")
			print(b.Labels.domain)
			
			if b.Labels.domain then
				rec.Domain = b.Labels.domain
			else
				-- rec.Domain = "pump.ninja"
				rec.Domain = os.getenv("HA_DOMAIN")
			end

			print("n ports:"..#b.Ports) --should show length
			for key, value in ipairs(b.Ports) do 
				print("Port:"..value.PrivatePort)
				if value.PrivatePort == 80 then
					print("got port 80")
					-- we use SSL termination in haproxy
					rec.Port = 80
				elseif value.PrivatePort == 433 then
					print("got port 433")
					-- we use SSL termination in haproxy so this is kind double...
					-- maybe use haproxy ssl through mode
					rec.Port = 443
				end
			end
			
			rec.IP=getIP(rec.Name)
			print("IP: "..rec.IP)
			if (rec.Port) then
				print("inserting container")
				table.insert(containers,rec)
			end

		end
		
		if hasEnvHautoproxy(rec.Name) then
			--rec.IP=b.Ports[1].IP
			--if hasEnvHautoproxy(rec.Name) then print("got hauto") else print("NO hauto") end
			rec.IP=getIP(rec.Name)
			print("got IP:"..rec.IP)
			-- needs more love
			--rec.PrivatePort=80 --b.Ports[1].PrivatePort
		end
		--print("rec.Name:",rec.Name)
		--print("rec.PrivatePort:",rec.PrivatePort)
		--print("--")
		--if rec.Port then
			--table.foreach(rec, print)
		--	for k, v in ipairs(rec) do print(v) end
		--	print("inserting container")
		--	table.insert(containers,rec)
		--end
	end

	haptl=file.read("./haproxy.tmpl")
	mres = applyTemplate(haptl,{_escape='>',containers=containers,ipairs=ipairs})
	--use diff? no write read access needed if there is nochange
	file.copy("./haproxy.cfg","./haproxy.cfg.old")
	file.write("./haproxy.cfg",mres)
--	print(mres)
end

function restartHAProxy()
	--note: there is a 'zero downtime version to restart haproxy'
	--http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html
	
	if os.execute("test -e /tmp/haproxy.pid") > 0 then
		cmd="haproxy -f ./haproxy.cfg -p /tmp/haproxy.pid"
		os.execute(cmd)
	else
		pid=file.read("/tmp/haproxy.pid")

		cmd="haproxy -f ./haproxy.cfg -p /tmp/haproxy.pid -sf "..pid
		os.execute(cmd);
		--os.execute(cmd);
	end
end

function getIP(name)
	h, b = unixHttp.request("/containers/"..name.."/json")
	--print("b",b)
	res = json.decode(b)
	--print(pretty.write(res.NetworkSettings.IPAddress))
	return res.NetworkSettings.IPAddress
end

function hasPort80(tab)
	local got80 = false
	--table.foreach(tab, function(v,k)
	for v,k in ipairs(tab) do
		if(k.PrivatePort == 80) then 
			--print("got one")
			got80 = true
			break
		end
	end
	return got80
end

function hasEnvHautoproxy(name)
	local gotHauto = false

	h, b = unixHttp.request("/containers/"..name.."/json")
	--print("b",b)
	res = json.decode(b)
	if res.Config.Env then
		for k,item in ipairs(res.Config.Env) do
			if string.find(item,"HAUTOPROXY") and string.find(item,"true") then
				gotHauto = true
			--	print("Env: "..item);
			end	
		end
	end
	return gotHauto

end

function hasLabelHautoproxy(name)
	local gotHauto = false

	h, b = unixHttp.request("/containers/"..name.."/json")
	--print("b",b)
	res = json.decode(b)
	if res.Config.Env then
		for k,item in ipairs(res.Config.Env) do
			if string.find(item,"HAUTOPROXY") and string.find(item,"true") then
				gotHauto = true
			--	print("Env: "..item);
			end	
		end
	end
	return gotHauto

end

function HAProxyNeedsUpdate()
	return os.execute("diff ./haproxy.cfg ./haproxy.cfg.old > /dev/null") ~= 0
end

function sleep(sec)
	return os.execute("sleep "..sec) == 0
end

repeat
	updateConfig()

	if HAProxyNeedsUpdate() then
		print("Updating HAProxy")
		-- ENABLE TODO restartHAProxy()
	end
	if not sleep(15) then
		--sigint ?
		os.exit(1)
	end
--	print("tick..")
until false 

