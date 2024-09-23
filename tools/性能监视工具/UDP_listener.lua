----------------------------------------
---UDP 监听器

local socket = assert(require("socket"))

local NETWORK_TIMEOUT=0.001
local NETWORK_IP,NETWORK_PORT="localhost",7
local SERVER_IP,SERVER_PORT="*",7

local MSG_HEAD="[MSG]"
local PING_HEAD="[PING]"
local REV_HEAD="[REV]"

local LOG_HEAD="[INFO]"
local WARN_HEAD="[WARN]"
local ERR_HEAD="[ERROR]"

local UDP=nil--udp object

local function UDP_Check()
	if UDP==nil then
		--创建UDP object并绑定到本地端口
		UDP=assert(socket.udp())
		local flag=false
		--bind
		local state,errmsg=UDP:setsockname(SERVER_IP,SERVER_PORT)
		if state then
			print(LOG_HEAD.."Bind to local successfully. ")
			flag=true
		elseif errmsg then
			print(ERR_HEAD..tostring(errmsg))
			flag=false
		else
			print(ERR_HEAD.."Unkown error.")
			flag=false
		end
		--check once again
		local ip, port = UDP:getsockname()
		if ip then
			print(LOG_HEAD.."Check pass,bind to "..tostring(ip)..":"..tostring(port))
			flag=true
		elseif port then
			print(ERR_HEAD..tostring(port))
			flag=false
		else
			print(ERR_HEAD.."Unkown error.")
			flag=false
		end
		if not flag then
			UDP:close()
			UDP=nil
		end
		return flag
	end
	return true
end

local function UDP_Receive()
	msg=tostring(msg)
	local msg,ip,port=UDP:receivefrom()
	if msg then
		--print(LOG_HEAD.."Receive message from "..tostring(ip)..":"..tostring(port))
		if string.sub(msg,1,5)==MSG_HEAD then
			--打印消息
			local str=string.sub(msg,6)
			print(str)
			--打印字节码，用于测试字符编码
			--[[
			local STRCODE={}
			for i=1,string.len(str) do
				STRCODE[i]=string.byte(str,i)
			end
			local CODE=""
			for _,v in ipairs(STRCODE) do
				CODE=CODE..string.format("%d ",v)
			end
			print(CODE)
			--]]
		end
	elseif ip then
		print(ERR_HEAD..tostring(ip))
		UDP:close()
		UDP=nil
	end
end

----------------------------------------
---循环

function FrameFunc()
	if not UDP_Check() then return end
	while true do
		UDP_Receive()
	end
end

----------------------------------------
---主逻辑

function main()
	while true do
		FrameFunc()
	end
end

main()
