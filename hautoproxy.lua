#!/usr/bin/env lua5.3

require "pl"
unixHTTP = assert(require("lib/usock"))
json = assert(require("cjson"))
log = assert(require("lib/log"))
applyTemplate = require "pl.template".substitute

function logif(str, arg)
	if (arg) then
	--	print (str .. arg)
		log.trace(str .. arg)
	end
end

function updateConfig()
	-- Get running containers
	--b, c, h = http.request("http://localhost:8080/containers/json")
	h, b = unixHttp.request("/containers/json")
	-- print("b",b)
	res = json.decode(b)
	-- for key, val in pairs(res) do print (key, val) end
	-- print(pretty.write(res))
	-- print("----------")
	containers={}
	ssl_containers={}

	for a, b in ipairs(res) do
		local rec={}
		rec.Id=b.Id
		--strip front slash
		rec.Name=string.sub(b.Names[1],2,-1)
		log.debug("container name: " .. rec.Name)
		--print("n ports:"..#b.Ports) --should show length

		if b.Labels.hautoproxy then
--			print("Labels :")
			logif("hautoproxy: ", b.Labels.hautoproxy)
			logif("cname: ", b.Labels.cname)
			logif("domain: ", b.Labels.domain)
			logif("ha_port: ", b.Labels.ha_port)
			logif("ha_ssl: ",b.Labels.ha_ssl)
--			print("n ports:"..#b.Ports) --should show length
			for key, value in ipairs(b.Ports) do 
--				print("Port:"..value.PrivatePort)
				if value.PrivatePort == 80 then
--					print("got port 80")
					-- we use SSL termination in haproxy
					rec.Port = 80
				elseif value.PrivatePort == 433 then
--					print("got port 433")
					-- we use SSL termination in haproxy so this is kind double...
					-- maybe use haproxy ssl through mode
					rec.Port = 443
				-- for testing
				elseif value.PrivatePort == 3000 then
--					print("got port 8080")
					rec.Port = 3000
				elseif value.PrivatePort == 8080 then
--					print("got port 8080")
					rec.Port = 8080
				end
			end

			
			rec.IP=getIP(rec.Name)

			-- do this after we got ip by name
			if b.Labels.cname then
				log.trace("usinging cname: "..b.Labels.cname)
				rec.Name=b.Labels.cname
			end
			
			if b.Labels.domain then
				log.trace("special domain: " .. b.Labels.domain);
				rec.Domain = b.Labels.domain
			else
				-- rec.Domain = "pump.ninja"
				log.trace("use default domain");
				rec.Domain = os.getenv("HA_DOMAIN")
			end

			if b.Labels.ha_port then
				log.trace("using local port: "..b.Labels.ha_port)
				rec.Port = b.Labels.ha_port
			end

			if b.Labels.ha_ssl then
				local ssl_rec={}
				log.trace("forcing ssl");
				ssl_rec.Domain = rec.Domain
				ssl_rec.Name = rec.Name
				table.insert(ssl_containers,ssl_rec)
			end


--			print("IP: "..rec.IP)
			if (rec.Port) then
--				print("inserting container")
--				print("")
				table.insert(containers,rec)
			end
		end
	end

	haptl=file.read("./haproxy.tmpl")
	mres = applyTemplate(haptl,{_escape='>',containers=containers,ssl_containers=ssl_containers,ipairs=ipairs})
	--use diff? no write read access needed if there is nochange
	file.copy("./haproxy.cfg","./haproxy.cfg.old")
	file.write("./haproxy.cfg",mres)
--	print(mres)
end

function restartHAProxy()
	--note: there is a 'zero downtime version to restart haproxy'
	--http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html
	
	--if os.execute("test -e /tmp/haproxy.pid") > 0 then
	if path.isfile("/var/run/haproxy.pid") then
		log.info("Restarting")
		pid=file.read("/var/run/haproxy.pid")
		cmd="haproxy -D -f ./haproxy.cfg -sf "..pid
		os.execute(cmd);
	else
		log.warn("dont have /var/run/haproxy.pid")
		cmd="haproxy -D -f ./haproxy.cfg"
		os.execute(cmd)
	end
end

function getIP(name)
	h, b = unixHttp.request("/containers/"..name.."/json")
	--print("b",b)
	res = json.decode(b)
	--print(pretty.write(res.NetworkSettings.IPAddress))
	return res.NetworkSettings.IPAddress
end

function HAProxyNeedsUpdate()
	-- first parm is true if exec true...
	-- nodifference is true
	return not os.execute("diff ./haproxy.cfg ./haproxy.cfg.old > /dev/null")
end

function sleep(sec)
	return os.execute("sleep "..sec)
end

function startupCheck()
	-- test if /var/run/docker.sock is there
	-- use file or docker interface?

	log.info("Startup check...")

	-- io.write ("Test for /var/run/docker.sock ... ")
	log.info ("Test for /var/run/docker.sock... ")
	-- if path.isfile("/var/run/docker.sock") then
	if path.exists("/var/run/docker.sock") then
		log.info("OK")
	else
		log.fatal("FAIL")
		log.fatal("Error: /var/run/docker.sock is missing")
		log.info("Start container with -v /var/run/docker.sock:/var/run/docker.sock:ro")
		os.exit(1)
	end

	-- TODO check read only
	--io.write ("Test if /var/run/docker.sock is read only... ")
	log.info("Test if /var/run/docker.sock is read only... ")
	
	-- get my stats
	local fp = io.popen('cat /proc/self/cgroup | grep name | sed "'..[[s/^.*docker\///]]..'"','r')
	local myid = fp.read(fp) -- TODO fixme... examples don't use a fp but '*a' or '*all'
	fp.close()

--	print(myid)

	h, b = unixHttp.request("/containers/"..myid.."/json")
	--print("b",b)
	res = json.decode(b)

	local gotSock = false
	
	for k,v in ipairs(res.Mounts) do
		if v.Destination == "/var/run/docker.sock" then
			gotSock = true
--			print "got the Destination"
--			print ("mode: " .. v.Mode)
			if not (v.Mode == "ro") then
				log.fatal("FAIL")
				log.fatal("Error: /var/run/docker.sock not mounted read only")
				log.info("Don't forget to append :ro to your volumes")
				os.exit(1)
			else
				log.info("OK")
			end
		end
	end

	if not gotSock then
		log.fatal("Can't find /var/run/docker.sock in Mounts")
		log.info("Start container with -v /var/run/docker.sock:/var/run/docker.sock:ro")
		os.exit(1)
	end

	-- test if haproxy exists -- TODO
	
--	print(pretty.write(res.Mounts[1]))
	log.info("") -- new line
end

function main()
	log.level=os.getenv("HA_LOGLEVEL")
	if not log.level then 
		log.level = "info"
	end

	startupCheck()

	log.info("Starting hautoproxy...")

	cmd="haproxy -D -f ./haproxy.cfg"
	os.execute(cmd)
	repeat
		updateConfig()

		if HAProxyNeedsUpdate() then
			log.debug("Updating HAProxy")
			restartHAProxy()
		end
		if not sleep(15) then
			--sigint ?
			os.exit(1)
		end
		-- print("tick..")
		log.debug("") -- newline
	until false 
end

main()
