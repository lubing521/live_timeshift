--[[
---- Filename: live_timeshift.lua
---- Description: 直播时移的主代码
---- 
---- Version:  1.0
---- Created:  2014年07月29日 11时23分51秒
---- Revision:  none
---- 
---- Author:  郭强 (guoqiang), guoqiang@cnbn.com
---- Company: gitv 2014 版权所有
--]]

-------------------------------------------------------
-- 参数:待分割的字符串,分割字符
-- 返回:子串表.(含有空串)
function lua_string_split(str, split_char)
    local sub_str_tab = {};
    while (true) do
        local pos = string.find(str, split_char);
        if (not pos) then
            sub_str_tab[#sub_str_tab + 1] = str;
            break;
        end
        local sub_str = string.sub(str, 1, pos - 1);
        sub_str_tab[#sub_str_tab + 1] = sub_str;
        str = string.sub(str, pos + 1, #str);
    end

    return sub_str_tab;
end

function ts_find_pos(ts_list, time_point)
	for index=#ts_list, 1, -1
	do
		--ngx.say(index, '\t', ts_list[index])
		the_parts = lua_string_split(ts_list[index], ':')
		ts_time = tonumber(the_parts[1], 10)
		if ts_time <= time_point then			
			return index
		end
		
	end
	return 1
end

-- 变量定义区
local request_uri   = ngx.var.request_uri;
local uri           = ngx.var.uri; 
local query_string	= ngx.var.query_string;
local args          = ngx.req.get_uri_args();
local time_now      = os.time();
local time_delta	= tonumber(args['t'], 10);
local time_point    = time_now + time_delta;
--[[
ngx.say(request_uri);
ngx.say(uri);
ngx.say(query_string);
ngx.say(time_delta);
--]]
--ngx.say(time_now);
--ngx.say(time_point);

the_sections = lua_string_split(uri, '/');
--[[
for index=1, #the_sections, 1
do
    ngx.say(index,"\t", the_sections[index])
end
--]]

live_root = the_sections[2];
channel_name = the_sections[3];
m3u8_name = the_sections[4];
--ngx.say('channel:\t', channel_name);

local redis = require "resty.redis"
local cache = redis.new()
local ok, err = cache.connect(cache, '127.0.0.1', '6379')
cache:set_timeout(60000)
if not ok then
    ngx.say("failed to connect redis:", err)
    return
end

---local res, err = cache::get('dog')
local res, err = cache:lrange(channel_name, '0', '-1')
if not res then
    ngx.say("failed to get channel: ", err)
    return
end

if res == ngx.null then
    ngx.say("channel is null: ", channel_name)
    return
end

local ts_index = ts_find_pos(res, time_point)
ts_end = ts_index + 2
if ts_end > #res then
    ts_end = #res
end

--[[
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:157973
#EXTINF:10,
/gitv_live/CCTV-1/C16_1406347911_1406347920.ts
#EXTINF:10,
/gitv_live/CCTV-1/C16_1406347921_1406347930.ts
#EXTINF:10,
/gitv_live/CCTV-1/C16_1406347931_1406347940.ts
--]]
ts_line = res[ts_index]
the_parts = lua_string_split(ts_line, ':')
str_sequence = the_parts[5]
ngx.say('#EXTM3U')
ngx.say('#EXT-X-TARGETDURATION:10')
ngx.say('#EXT-X-MEDIA-SEQUENCE:', str_sequence)
for index=ts_index, ts_end, 1
do
	ts_line = res[index]
	--ngx.say(ts_line);
	the_parts = lua_string_split(ts_line, ':')
	--1406618591:1406618600:10:0:${sequence}:C103_1406618591_1406618600.ts
	str_begin_time = the_parts[1]
	str_end_time = the_parts[2]
	str_inf = the_parts[3]
	str_discontinuity = the_parts[4]
	str_sequence = the_parts[5]
	str_ts_name = the_parts[6]		
	ngx.say('#EXTINF:', str_inf);
	ts_uri = string.format("/%s/%s/%s", live_root, channel_name, str_ts_name);
	ngx.say(ts_uri);
	int_discontinuity = tonumber(str_discontinuity, 10);
	if int_discontinuity ~= 0 then
		ngx.say('#EXT-X-DISCONTINUITY');
	end
end

local ok, err = cache:close()
if not ok then
	ngx.say("failed to close redis: ", err)
	return
end


