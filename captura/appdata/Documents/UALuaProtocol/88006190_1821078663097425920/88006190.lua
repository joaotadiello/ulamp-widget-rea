---@diagnostic disable: param-type-mismatch
--region
-- &: 按位与
-- |: 按位或
-- ~: 按位异或
-- >>: 右移
-- <<: 左移
-- ~: 按位非


--这个原理是逐个解析字符串，同样可以解析json、xml
--这里解析json作为实例
-- local luaJson = {}
function json2true(str, from, to)
    return true, from + 3
end

 function json2false(str, from, to)
    return false, from + 4
end

 function json2null(str, from, to)
    return nil, from + 3
end

 function json2nan(str, from, to)
    return nil, from + 2
end

 numberchars = {
    ['-'] = true,
    ['+'] = true,
    ['.'] = true,
    ['0'] = true,
    ['1'] = true,
    ['2'] = true,
    ['3'] = true,
    ['4'] = true,
    ['5'] = true,
    ['6'] = true,
    ['7'] = true,
    ['8'] = true,
    ['9'] = true,
}

 function json2number(str, from, to)
    local i = from + 1
    while (i <= to) do
        local char = string.sub(str, i, i)
        if not numberchars[char] then
            break
        end
        i = i + 1
    end
    local num = tonumber(string.sub(str, from, i - 1))
    if not num then
        Log("red", 'json格式错误，不正确的数字, 错误位置:', from)
    end
    return num, i - 1
end

 function json2string(str, from, to)
    local ignor = false
    for i = from + 1, to do
        local char = string.sub(str, i, i)
        if not ignor then
            if char == '\"' then
                return string.sub(str, from + 1, i - 1), i
            elseif char == '\\' then
                ignor = true
            end
        else
            ignor = false
        end
    end
    -- Log("red", 'json格式错误，字符串没有找到结尾, 错误位置:{from}', from)
end

 function json2array(str, from, to)
    local result = {}
    from = from or 1
    local pos = from + 1
    local to = to or string.len(str)
    while (pos <= to) do
        local char = string.sub(str, pos, pos)
        if char == '\"' then
            result[#result + 1], pos = json2string(str, pos, to)
        --[[    elseif char == ' ' then
        
        elseif char == ':' then
        
        elseif char == ',' then]]
        elseif char == '[' then
            result[#result + 1], pos = json2array(str, pos, to)
        elseif char == '{' then
            result[#result + 1], pos = json2table(str, pos, to)
        elseif char == ']' then
            return result, pos
        elseif (char == 'f' or char == 'F') then
            result[#result + 1], pos = json2false(str, pos, to)
        elseif (char == 't' or char == 'T') then
            result[#result + 1], pos = json2true(str, pos, to)
        elseif (char == 'n') then
            result[#result + 1], pos = json2null(str, pos, to)
        elseif (char == 'N') then
            result[#result + 1], pos = json2nan(str, pos, to)
        elseif numberchars[char] then
            result[#result + 1], pos = json2number(str, pos, to)
        end
        pos = pos + 1
    end
end

 function string2json(key, value)
    return string.format("\"%s\":\"%s\",", key, value)
end

 function number2json(key, value)
    return string.format("\"%s\":%s,", key, value)
end

 function boolean2json(key, value)
    value = value == nil and false or value
    return string.format("\"%s\":%s,", key, tostring(value))
end

 function array2json(key, value)
    local str = "["
    for k, v in pairs(value) do

        if type(v) == "string" then
            str = str .. string.format("\"%s\"",v)
        elseif type(v) == "number" then
            str = str .. string.format("%s", v)
        elseif type(v) == "boolean" then
            v = v == nil and false or v
            -- str = str .. boolean2json(k, v)
            str = str .. string.format("%s", key, tostring(v))
        elseif type(v) == "table" then
            str = str .. table2json(k, v)
        end

        str = str .. ","
    end
    str = string.sub(str, 1, string.len(str) - 1) .. "]"
    return string.format("\"%s\":%s,", key, str)
end

 function isArrayTable(t)

    if type(t) ~= "table" then
        return false
    end

    local n = #t
    for i, v in pairs(t) do
        if type(i) ~= "number" then
            return false
        end

        if i > n then
            return false
        end
    end

    return true
end

 function table2json(key, value)
    if isArrayTable(value) then
        return array2json(key, value)
    end
    local tableStr = Table2jsonString(value)

    return string.format("\"%s\":%s,", key, tableStr)
end


function json2table(str, from, to)
    local result = {}
    from = from or 1
    local pos = from + 1
    local to = to or string.len(str)
    local key
    while (pos <= to) do
        local char = string.sub(str, pos, pos)
        --Log("yellow", pos, "-->", char)
        if char == '\"' then
            if not key then
                key, pos = json2string(str, pos, to)
            else
                result[key], pos = json2string(str, pos, to)
                key = nil
            end
        --[[    elseif char == ' ' then
        
        elseif char == ':' then
        
        elseif char == ',' then]]
        elseif char == '[' then
            if not key then
                key, pos = json2array(str, pos, to)
            else
                result[key], pos = json2array(str, pos, to)
                key = nil
            end
        elseif char == '{' then
            if not key then
                key, pos = json2table(str, pos, to)
            else
                result[key], pos = json2table(str, pos, to)
                key = nil
            end
        elseif char == '}' then
            return result, pos
        elseif (char == 'f' or char == 'F') then
            result[key], pos = json2false(str, pos, to)
            key = nil
        elseif (char == 't' or char == 'T') then
            result[key], pos = json2true(str, pos, to)
            key = nil
        elseif (char == 'n') then
            result[key], pos = json2null(str, pos, to)
            key = nil
        elseif (char == 'N') then
            result[key], pos = json2nan(str, pos, to)
            key = nil
        elseif numberchars[char] then
            if not key then
                key, pos = json2number(str, pos, to)
            else
                result[key], pos = json2number(str, pos, to)
                key = nil
            end
        end
        pos = pos + 1
    end
end

--json格式中表示字符串不能使用单引号
local jsonfuncs = {
    ['\"'] = json2string,
    ['['] = json2array,
    ['{'] = json2table,
    ['f'] = json2false,
    ['F'] = json2false,
    ['t'] = json2true,
    ['T'] = json2true,
}

function json2lua(str)
    local char = string.sub(str, 1, 1)
    local func = jsonfuncs[char]
    if func then
        return func(str, 1, string.len(str))
    end
    if numberchars[char] then
        return json2number(str, 1, string.len(str))
    end
end

function Table2jsonString(tab)
    local str = "{"
    for k, v in pairs(tab) do
        if type(v) == "string" then
            str = str .. string2json(k, v)
        elseif type(v) == "number" then
            str = str .. number2json(k, v)
        elseif type(v) == "boolean" then
            str = str .. boolean2json(k, v)
        elseif type(v) == "table" then
            str = str .. table2json(k, v)
        end
    end
    str = string.sub(str, 1, string.len(str) - 1)

    if string.len(str) == 0 then
        return ""
    else
        return str .. "}"
    end
end
----------上面代码是简单的json处理

function Get_random()
    math.randomseed(tostring(os.time()):reverse():sub(1, 7))
    local value = math.random(0,255);
    return value;
end

TID = 0

---数据解析
function CurrTid()
     if (TID > 255) then
        TID = 0x00
     end
end

--将字符串转换成16进制的字符串 abc = 0x12,0x34,0x56  return 123456
function ConvertHexString(stringValue)
    local result;
    local stringLen = string.len(stringValue)
    if stringLen == 0 then
        result = nil
    else
        for i = 1, stringLen, 1 do
            local temp = string.byte(string.sub(stringValue, i, i))
            if result ~= nil then
                result = result..string.format("%02x", temp)
            else
                result = string.format("%02x", temp)
            end
        end
    end
    return result
end

--小段在前
function IntFromString(stringValue)
    local lenth = string.len(stringValue)
    local result = 0
    for index=lenth, 1, -1 do  --从最后一个字符开始计算
       result = result*16*16 + string.byte(string.sub(stringValue, index, index))
    end
   return result
end

--将1个两位16进制的字符串转换成整形  比如 FE -> 15 * 16 + 14
function Convert16HexStrToInt8(hexString)
    local value = tonumber(string.sub(hexString, 1, 1), 16) * 16;
    value = value + tonumber(string.sub(hexString, 2, 2), 16)
    return value
end

-- 数组位异或
function XorValue(bleArray, lenth)
    local result = bleArray[1];
    for i = 2, lenth do
        result = result~bleArray[i]
    end
    return result
end

-- 将颜色转转成RGB的值 颜色按照RGB的顺序给的
function ConvertColor(colorValue)
    local redColor = (colorValue>>16) & 0xFF
    local greenColor = (colorValue>>8) & 0xFF
    local blueColor = colorValue & 0xFF
    return redColor,greenColor,blueColor
end

--将一个整整转换成4个字节  0x02345678   78,56,34,2
function Convert4ByteValue(convertValue)
    local topValue = (convertValue>>24) & 0xFF
    local secondValue = (convertValue>>16) & 0xFF
    local thirdValue = (convertValue>>8) & 0xFF
    local lastValue = (convertValue) & 0xFF
    --小端在前
    return lastValue, thirdValue, secondValue, topValue
end

--将一个整整转换成4个字节  0x02345678   78,56,34,2
function Convert2ByteValue(convertValue)
    local topValue = (convertValue>>8) & 0xFF
    local lastValue = (convertValue) & 0xFF
    --小端在前
    return lastValue, topValue
end

-- 获取个数
function GetTableCount(table)
    local count=0
    for k,v in pairs(table) do
        count = count + 1
    end
    return count
end

----------------------- Lua 对外的接口函数

-- 获取蓝牙协议的头部信息
function GetBleDeviceStatusHeadPackage()
    local resultStr
    local checkValue = 0x4a;

     --固定格式
     resultStr = string.format("%02x", 0x0A)
     checkValue = 0x0A;

     resultStr = resultStr..string.format("%02x", 0xA5)
     checkValue = checkValue~0xA5

     --消息ID
     resultStr = resultStr..string.format("%02x", TID)
     checkValue = checkValue~TID
     TID = TID + 1
     CurrTid()

     return resultStr, checkValue
end

--获取设备状态
function GetBleDeviceStatusBlePackage()
    --头部数据
    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    --0x82D0表示获取设备状态信息
    resultStr = resultStr..string.format("%02x", 0xFF)
    checkValue = checkValue~0xFF

    return resultStr
end

function ControlBleDevice(rnTableStr)
    local rnTable = {}
    rnTable = json2table(rnTableStr);

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    local power = rnTable['power']
    local mode = rnTable['mode']
    local lamp_beads = rnTable['lamp_bead']
    local total_lamp_bead = rnTable['total_lamp_bead']

    --1：RGB 2：RBG 3：BRG 4：BGR 5：GRB 6：GBR
    local lineStyle = rnTable['lineStyle']

    local musicTable = rnTable['musicInfo']
    local sceneTable = rnTable['sceneInfo']
    local sceneId = rnTable['scene']

    --白平衡 测试使用
    local whiteBalanceTable = rnTable['whiteBalance'];

    --涂抹颜色
    local paintColorTable  = rnTable['paintColor']

    --设置电视框灯珠
    local tvLampBeadsTable = rnTable['tvLampBeads']
	
	local advanceInfoTable = rnTable['advanceInfo']
	

    if type(power) ~= "nil" then
        resultStr = resultStr..string.format("%02x", 0x01)
        checkValue = checkValue ~ 0x01

        resultStr = resultStr..string.format("%02x", power)
        checkValue = checkValue ~ power

    elseif type(mode) ~= "nil" then
        resultStr = resultStr..string.format("%02x", 0x02)
        checkValue = checkValue ~ 0x02

        resultStr = resultStr..string.format("%02x", mode)
        checkValue = checkValue ~ mode
    elseif type(lamp_beads) ~= "nil" then
        resultStr = resultStr..string.format("%02x", 0x07)
        checkValue = checkValue ~ 0x07

        local lampBeadsLastValue, lampBeadsTopValue = Convert2ByteValue(lamp_beads)
        resultStr = resultStr..string.format("%02x", lampBeadsLastValue)
        checkValue = checkValue~lampBeadsLastValue
        resultStr = resultStr..string.format("%02x", lampBeadsTopValue)
        checkValue = checkValue~lampBeadsTopValue

        local totolLampBeadsLastValue, totolLampBeadsTopValue = Convert2ByteValue(total_lamp_bead)
        resultStr = resultStr..string.format("%02x", totolLampBeadsLastValue)
        checkValue = checkValue~totolLampBeadsLastValue
        resultStr = resultStr..string.format("%02x", totolLampBeadsTopValue)
        checkValue = checkValue~totolLampBeadsTopValue

    elseif type(lineStyle) ~= "nil" then
        resultStr = resultStr..string.format("%02x", 0x09)
        checkValue = checkValue ~ 0x09

        resultStr = resultStr..string.format("%02x", lineStyle)
        checkValue = checkValue~lineStyle
    elseif type(musicTable) ~= "nil" then
        local currResultValue, currCheckValue = ControlMusic(musicTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(sceneTable) ~= "nil" then
        local currResultValue, currCheckValue = ControlDiyScene(sceneTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(sceneId) ~= "nil" then
        local currResultValue, currCheckValue = ControlScene(sceneId)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(paintColorTable) ~= "nil" then
        local currResultValue, currCheckValue = ControlPaintColor(paintColorTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(whiteBalanceTable) ~= "nil" then
        local currResultValue, currCheckValue = ControlWhiteBalance(whiteBalanceTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(advanceInfoTable) ~= "nil" then
        local currResultValue, currCheckValue = ControlAdvanceInfoTable(advanceInfoTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    elseif type(tvLampBeadsTable) ~= nil then
        local currResultValue, currCheckValue = ControlTVLampBeads(tvLampBeadsTable)
        resultStr = resultStr..currResultValue
        checkValue = checkValue ~ currCheckValue
    end
    return resultStr
end

function ControlMusic(musicTable)
    local resultStr, checkValue
    resultStr = string.format("%02x", 0x06)
    checkValue = 0x06

    local openMusic = musicTable['openMusic'];  --本地mic是否打开
    local musicMode = musicTable['musicMode'];    --音乐模式
    local direction = musicTable['direction'];     --变化方向 预留 可以没有
    local sensitivity = musicTable['sensitivity'];  --灵敏度
    local colors = musicTable['colors']
    local count = GetTableCount(colors);

    resultStr = resultStr..string.format("%02x", openMusic)
    checkValue = checkValue ~ openMusic

    resultStr = resultStr..string.format("%02x", musicMode)
    checkValue = checkValue ~ musicMode

    if type(direction) == "nil" then
        direction = 0;
    end
    resultStr = resultStr..string.format("%02x", direction)
    checkValue = checkValue ~ direction

    resultStr = resultStr..string.format("%02x", sensitivity)
    checkValue = checkValue ~ sensitivity

    resultStr = resultStr..string.format("%02x", count)
    checkValue = checkValue ~ count

    for k, v in pairs(colors) do
        local currColor = string.sub(v,2,-1)

        local rColor, gColor,bColor = Convert16HexStrToInt8(currColor.sub(currColor, 1, 2)),Convert16HexStrToInt8(currColor.sub(currColor, 3, 4)),Convert16HexStrToInt8(currColor.sub(currColor, 5, 6))

        resultStr = resultStr..string.format("%02x", rColor)
        checkValue = checkValue~rColor

        resultStr = resultStr..string.format("%02x", gColor)
        checkValue = checkValue~gColor

        resultStr = resultStr..string.format("%02x", bColor)
        checkValue = checkValue~bColor
    end

    return resultStr, checkValue
end

function ControlScene(sceneId)
    local sceneTable = {}
    sceneTable["sceneId"] = sceneId;
    if sceneId == 0x01 then
        --01 11 10 57 57 84 0000 64 000D 42 0136 63 007D 64 003A 60 00B7 64
        sceneTable["changeMode"] = 0x10;  --10流水
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#FF7B56";
        colors[2] = "#FF02D4";
        colors[3] = "#00FF15";
        colors[4] = "#FFF60A";
        colors[5] = "#00F2FF";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x02 then
        --01 12 0B 57 57 60 0B0C 64 00F064 007864 016564
        sceneTable["changeMode"] = 0x0B;  --10流水
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 0; -- 分段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 0; -- 拓展模式位0
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0000FF";
        colors[2] = "#00FF00";
        colors[3] = "#FF000C";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x03 then
        --01 13 06 64 64 84 0000 64 00AB64 011D64 003864 006D4A 001656
        sceneTable["changeMode"] = 0x06;  --10流水
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#00FFD8";
        colors[2] = "#BF00FF";
        colors[3] = "#FFEE00";
        colors[4] = "#64FF42";
        colors[5] = "#FF7423";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x04 then
        --01 14 08 60 60 84 0000 64 00CC64 014864 004864 008D64 002564
        sceneTable["changeMode"] = 0x08;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0099FF";
        colors[2] = "#FF0087";
        colors[3] = "#CCFF00";
        colors[4] = "#00FF59";
        colors[5] = "#FF9D00";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x05 then
        --01 15 09 50 50 84 0000 64 00CC64 014864 004864 008D64 002564
        sceneTable["changeMode"] = 0x09;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0099FF";
        colors[2] = "#FF0087";
        colors[3] = "#CCFF00";
        colors[4] = "#00FF59";
        colors[5] = "#FF9D00";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x06 then
        --01 16 0C 3F 3F 84 0000 64 00E762 013464 003D64 007E64 000264
        sceneTable["changeMode"] = 0x0C;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#052AFF";
        colors[2] = "#FF00DD";
        colors[3] = "#FAFF00";
        colors[4] = "#00FF19";
        colors[5] = "#FF0800";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x07 then
        --01 17 0D 54 54 84 0000 64 00EA64 014064 003D64 007664 000264
        sceneTable["changeMode"] = 0x0D;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位1
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0019FF";
        colors[2] = "#FF00A9";
        colors[3] = "#FAFF00";
        colors[4] = "#08FF00";
        colors[5] = "#FF0800";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x08 then
        --0118 0A 49 49 88 0000 64 000264 00F664 007D64 002E64 005C33
        sceneTable["changeMode"] = 0x0A;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 2; -- 拓展模式位0B10
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#FF0800";
        colors[2] = "#1900FF";
        colors[3] = "#00FF15";
        colors[4] = "#FFC300";
        colors[5] = "#B9FF7C";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x09 then
        --0119 0F 45 45 80 0000 64 00EA64 014064 003D64 007664 000264
        sceneTable["changeMode"] = 0x0F;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位0B10
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0019FF";
        colors[2] = "#FF00A9";
        colors[3] = "#FAFF00";
        colors[4] = "#08FF00";
        colors[5] = "#FF0800";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x0A then
        --011a 10 60 60 80 0000 64 00D964 013864 003C64 00645B 015A2C
        sceneTable["changeMode"] = 0x10;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 1; -- 全段
        sceneTable["direction"] = 1; -- 顺时针
        sceneTable["expansion"] = 1; -- 拓展模式位0B10
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#0061FF";
        colors[2] = "#FF00CC";
        colors[3] = "#FFFF00";
        colors[4] = "#64FF16";
        colors[5] = "#FF8EA8";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x0B then
        --011b 03 5E 5E 60 0000 64 00382F 001E5C 00D545 011A64
        sceneTable["changeMode"] = 0x03;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 0; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 0; -- 拓展模式位0B10
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#FFF787";
        colors[2] = "#FF8914";
        colors[3] = "#4F9EFF";
        colors[4] = "#B200FF";
        sceneTable["colors"] = colors;
    elseif sceneId == 0x0C then
        --011c 0C 3232 60 0B0C 64 003764 013864 00C064 016764
        sceneTable["changeMode"] = 0x0C;
        sceneTable["speed"] = 50;
        sceneTable["sceneType"] = 0; -- 全段
        sceneTable["direction"] = 0; -- 顺时针
        sceneTable["expansion"] = 0; -- 拓展模式位0B10
        sceneTable["brightness"] = 100;
        local colors = {}
        colors[1] = "#FFE900";
        colors[2] = "#FF00CC";
        colors[3] = "#00CCFF";
        colors[4] = "#FF0004";
        sceneTable["colors"] = colors;
    end
    return ControlDiyScene(sceneTable);
end

function ControlDiyScene(sceneTable)
    local resultStr, checkValue
    resultStr = string.format("%02x", 0x05)
    checkValue = 0x05

    local sceneId = sceneTable["sceneId"]

    local changeMode = sceneTable["changeMode"]
    local sceneSpeed = sceneTable["speed"]
    -- 0：全段   1：分段
    local sceneType = sceneTable["sceneType"]
    -- 方向
    local sceneDirection = sceneTable["direction"]
    -- 拓展模式
    local expansion = sceneTable["expansion"]

    local brightness = sceneTable["brightness"]
	local luminance = sceneTable["luminance"]
    local colors = sceneTable["colors"]
    local colorCount
    if type(colors) == "nil" then
        colorCount = 0
    else
        colorCount = GetTableCount(colors)
    end

    --场景编号
    resultStr = resultStr..string.format("%02x", sceneId)
    checkValue = checkValue~sceneId

    --变化方向
    if type(changeMode) == "nil" then
        changeMode = 0;
    end
    resultStr = resultStr..string.format("%02x", changeMode)
    checkValue = checkValue~changeMode

    if type(sceneSpeed) == "nil" then
        sceneSpeed = 0;
    end
    resultStr = resultStr..string.format("%02x", sceneSpeed)
    checkValue = checkValue~sceneSpeed

    local value = 0;
    if sceneId == 0 then
        --亮度增强
        -- 2bit 预留 (1~2)
        value = value | expansion
        -- 3~4bit：拓展模式
        value = value | (sceneDirection<<4);
    else
        -- 2bit 预留 (1~2)
        value = value | (expansion<<2)
        -- 3~4bit：拓展模式
        value = value | (sceneDirection<<4);
        -- value = value + 0   6~7bit：预留
        value = value | (sceneType << 7);
    end
    resultStr = resultStr..string.format("%02x", value)
    checkValue = checkValue~value
    -- 预留
    if sceneId ~= 0 then
        resultStr = resultStr..string.format("%02x", 0)
        checkValue = checkValue~0
        resultStr = resultStr..string.format("%02x", 0)
        checkValue = checkValue~0
    else
        -- TV模式
        -- if changeMode == 0 then
        --     local section = sceneTable["section"]
        --     resultStr = resultStr..string.format("%02x", section)
        --     checkValue = checkValue~section
        --     resultStr = resultStr..string.format("%02x", 0)
        --     checkValue = checkValue~0
        -- else
        --     local musicMode = sceneTable["musicMode"]
        --     if type(musicMode) == "nil" then
        --         musicMode = 1;
        --     end
        --     local section = sceneTable["section"]
        --      if type(section) == "nil" then
        --         section = 0;
        --      end
        --     resultStr = resultStr..string.format("%02x", section)
        --     checkValue = checkValue~section
            -- resultStr = resultStr..string.format("%02x", musicMode)
            -- checkValue = checkValue~musicMode
        -- end
        local section = sceneTable["section"]
        if type(section) == "nil" then
            section = 0;
        end
        resultStr = resultStr..string.format("%02x", section)
        checkValue = checkValue~section

        local musicMode = sceneTable["musicMode"]
        if type(musicMode) == "nil" then
            musicMode = 0;
        end
        resultStr = resultStr..string.format("%02x", musicMode)
        checkValue = checkValue~musicMode
    end

    --亮度（1-100）
    resultStr = resultStr..string.format("%02x", brightness)
    checkValue = checkValue~brightness
	
	if luminance ~= nil and luminance ~= '' then
		resultStr = resultStr..string.format("%02x", luminance)
		checkValue = checkValue..luminance
	end

    if colorCount > 0 then
        resultStr = resultStr..string.format("%02x", colorCount)
        checkValue = checkValue~colorCount

        for k, v in pairs(colors) do
            local currColor = string.sub(v,2,-1)

            local rColor, gColor,bColor = Convert16HexStrToInt8(currColor.sub(currColor, 1, 2)),Convert16HexStrToInt8(currColor.sub(currColor, 3, 4)),Convert16HexStrToInt8(currColor.sub(currColor, 5, 6))

            resultStr = resultStr..string.format("%02x", rColor)
            checkValue = checkValue~rColor

            resultStr = resultStr..string.format("%02x", gColor)
            checkValue = checkValue~gColor

            resultStr = resultStr..string.format("%02x", bColor)
            checkValue = checkValue~bColor
        end
    end
    return resultStr, checkValue;
end

function ControlPaintColor(paintColorTable)
    local resultStr, checkValue
    resultStr = string.format("%02x", 0x04)
    checkValue = 0x04

    local paintType = paintColorTable["type"];
    resultStr = resultStr..string.format("%02x", paintType)
    checkValue = checkValue~paintType

     local action = paintColorTable["action"];
     resultStr = resultStr..string.format("%02x", action)
     checkValue = checkValue~action

    local colors = paintColorTable["colors"];
    local brightnesses = paintColorTable["brightnesses"];
    local colorCount = GetTableCount(colors);

    resultStr = resultStr..string.format("%02x", colorCount)
    checkValue = checkValue~colorCount

    for k, v in pairs(colors) do
        local currBrightness = brightnesses[k];
        resultStr = resultStr..string.format("%02x", currBrightness)
        checkValue = checkValue~currBrightness

        local currColor = string.sub(v,2,-1)
        local rColor, gColor,bColor = Convert16HexStrToInt8(currColor.sub(currColor, 1, 2)),Convert16HexStrToInt8(currColor.sub(currColor, 3, 4)),Convert16HexStrToInt8(currColor.sub(currColor, 5, 6))

        resultStr = resultStr..string.format("%02x", rColor)
        checkValue = checkValue~rColor

        resultStr = resultStr..string.format("%02x", gColor)
        checkValue = checkValue~gColor

        resultStr = resultStr..string.format("%02x", bColor)
        checkValue = checkValue~bColor
    end

    return resultStr, checkValue;
end

function ControlWhiteBalance(whiteBalanceTable)

    local resultStr, checkValue
    resultStr = string.format("%02x", 0x0B)
    checkValue = 0x0B

    local whiteBalanceRed = whiteBalanceTable["whiteBalanceRed"];
    resultStr = resultStr..string.format("%02x", whiteBalanceRed)
    checkValue = checkValue~whiteBalanceRed

    local whiteBalanceGreen = whiteBalanceTable["whiteBalanceGreen"];
    resultStr = resultStr..string.format("%02x", whiteBalanceGreen)
    checkValue = checkValue~whiteBalanceGreen

    local whiteBalanceBlue = whiteBalanceTable["whiteBalanceBlue"];
    resultStr = resultStr..string.format("%02x", whiteBalanceBlue)
    checkValue = checkValue~whiteBalanceBlue

    return resultStr, checkValue;
end

function ControlAdvanceInfoTable(advanceInfoTable)

    local resultStr, checkValue
    resultStr = string.format("%02x", 0x0F)
    checkValue = 0x0F

    local dormancy = advanceInfoTable["dormancy"];
    resultStr = resultStr..string.format("%02x", dormancy)
    checkValue = checkValue~dormancy

    return resultStr, checkValue;
end

function ControlTVLampBeads(tvLampBeadsTable)

    local resultStr, checkValue
    resultStr = string.format("%02x", 0x0C)
    checkValue = 0x0B

    local section = tvLampBeadsTable["section"];
    resultStr = resultStr..string.format("%02x", section)
    checkValue = checkValue~section

    local lampBeads = tvLampBeadsTable["lampBeads"];
    resultStr = resultStr..string.format("%02x", lampBeads)
    checkValue = checkValue~lampBeads

    local confirm = tvLampBeadsTable["confirm"];
    resultStr = resultStr..string.format("%02x", confirm)
    checkValue = checkValue~confirm

    return resultStr, checkValue;

end

--删除定时
function DeleteCountdown(timerId)
    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();
    resultStr = resultStr..string.format("%02x", 0x0A);
    checkValue = checkValue ~ 0x0A
    for i = 1, 8, 1 do
        resultStr = resultStr..string.format("%02x", 0x00)
        checkValue = checkValue ~ 0x00
    end
    return resultStr
end


--创建定时器
function CreateCountdown(timerTableStr)
    local timerTable = {}
    timerTable = json2table(timerTableStr);

    local timerId = timerTable['timerId']
    local power = timerTable['power']
    local taskStartTimeStamp = timerTable['startTimeStamp']
    local taskEndTimeStamp = timerTable['stopTimeStamp']

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x", 0x0A);
    checkValue = checkValue ~ 0x0A

    local countdownValue = taskEndTimeStamp - taskStartTimeStamp;

   --4个字节，倒计时的时长
   local startTimeStampLastValue, startTimeStampThirdValue, startTimeStampSecondValue, startTimeStampStopValue = Convert4ByteValue(countdownValue)

   resultStr = resultStr..string.format("%02x", startTimeStampLastValue)
   checkValue = checkValue~startTimeStampLastValue

   resultStr = resultStr..string.format("%02x", startTimeStampThirdValue)
   checkValue = checkValue~startTimeStampThirdValue

   resultStr = resultStr..string.format("%02x", startTimeStampSecondValue)
   checkValue = checkValue~startTimeStampSecondValue

   resultStr = resultStr..string.format("%02x", startTimeStampStopValue)
   checkValue = checkValue~startTimeStampStopValue


   resultStr = resultStr..string.format("%02x", startTimeStampLastValue)
   checkValue = checkValue~startTimeStampLastValue

   resultStr = resultStr..string.format("%02x", startTimeStampThirdValue)
   checkValue = checkValue~startTimeStampThirdValue

   resultStr = resultStr..string.format("%02x", startTimeStampSecondValue)
   checkValue = checkValue~startTimeStampSecondValue

   resultStr = resultStr..string.format("%02x", startTimeStampStopValue)
   checkValue = checkValue~startTimeStampStopValue

    -- resultStr = resultStr..string.format("%02x", checkValue)

    return resultStr
end

--接收到的蓝牙数据解析
function BleRecieveDataResolv(bleData)
    local index = 1
    local table = {}
    local lenth = string.len(bleData)
    local result

    local head1 = string.sub(bleData, index, index + 1)
    index = index + 2    --index =  3

    local header = IntFromString(head1)
    if header ~= 0xA50A then
        return nil
    end

    --消息ID
    index = index + 1  -- index = 4

    local opCode = string.byte(string.sub(bleData, index, index));
    index = index + 1  -- index = 5

    if opCode == 0x01 then
        local power = string.byte(string.sub(bleData, index, index));
        table["power"] = power
    elseif opCode == 0x02 then --设置模式
        local mode = string.byte(string.sub(bleData, index, index));
        table["mode"] = mode
    elseif opCode == 0x04 then  -- 设置涂抹调色
        local type = string.byte(string.sub(bleData, index, index));
        index = index + 1  -- index = 6

        local aciton = string.byte(string.sub(bleData, index, index));
        index = index + 1 --index = 7

        local colorCount = string.byte(string.sub(bleData, index, index));
        index = index + 1  -- index = 8

        local colorArray = {}
        local brightnessArray = {}

        for i = 1, colorCount, 1 do
            local currColor = string.sub(bleData, index, index+3)
            index = index + 4;

            local brightness = string.byte(string.sub(currColor, 1, 1))
            brightnessArray[i] = brightness;

            local color = string.sub(currColor, 2, 4)
            colorArray[i] = string.upper('#'..ConvertHexString(color));
        end
        local paintColorTable = {}
        paintColorTable["action"] = aciton
        paintColorTable["colors"] = colorArray
        paintColorTable["brightnesses"] = brightnessArray
        paintColorTable["type"] = type
        table["paintColor"] = paintColorTable;
    elseif opCode == 0x05 then --设置幻彩场景
        local sceneId = string.byte(string.sub(bleData, index, index));
        index = index + 1

        if sceneId == 0 then
            local sceneTable = {}
            local changeMode = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local sceneSpeed = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local tempExpansion = string.byte(string.sub(bleData, index, index));
            index = index + 1
			local sceneDirection = ((tempExpansion>>4) & 1);  -- 5Bit
			local expansion = (tempExpansion & 1);  -- 3~4Bit

            -- if changeMode == 0 then --多段
            --     local section = string.byte(string.sub(bleData, index, index));
            --     index = index + 1
            --     sceneTable["section"] = section

            --     local musicMode = string.byte(string.sub(bleData, index, index));
            --     index = index + 1
            --     sceneTable["musicMode"] = musicMode
            -- else --music模式
            --     local section = string.byte(string.sub(bleData, index, index));
            --     index = index + 1
            --     sceneTable["section"] = section

            --     local musicMode = string.byte(string.sub(bleData, index, index));
            --     index = index + 1
            --     sceneTable["musicMode"] = musicMode
            -- end

            local section = string.byte(string.sub(bleData, index, index));
            index = index + 1
            sceneTable["section"] = section

            local musicMode = string.byte(string.sub(bleData, index, index));
            index = index + 1
            sceneTable["musicMode"] = musicMode

            local brightness = string.byte(string.sub(bleData, index, index));
            index = index + 1
			
            local luminance = string.byte(string.sub(bleData, index, index));
            index = index + 1

            sceneTable["sceneId"] = sceneId
            sceneTable["changeMode"] = changeMode
            sceneTable["speed"] = sceneSpeed
			sceneTable["direction"] = sceneDirection
            sceneTable["brightness"] = brightness
			sceneTable["luminance"] = luminance
            sceneTable["expansion"] = expansion
            table["sceneInfo"] = sceneTable
        elseif sceneId > 0 then
            table["scene"] = sceneId
        else
            local sceneTable = {}
            local changeMode = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local sceneSpeed = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local temp = string.byte(string.sub(bleData, index, index));
            index = index + 1
            local sceneType = ((temp>>7) & 1);  -- 8it
            local sceneDirection = ((temp>>4) & 1);  -- 5Bit
            local expansion = ((temp>>2) & 3);  -- 3~4Bit

            index = index + 2; -- 预留

            local brightness = string.byte(string.sub(bleData, index, index));
            index = index + 1
			
            local luminance = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local colorCount = string.byte(string.sub(bleData, index, index));
            index = index + 1

            local colorArray = {}
            for i = 1, colorCount, 1 do
                local color = string.sub(bleData, index, index+2)
                index = index + 3;
                colorArray[i] = string.upper('#'..ConvertHexString(color));
            end
            sceneTable["sceneId"] = sceneId
            sceneTable["changeMode"] = changeMode
            sceneTable["speed"] = sceneSpeed
            sceneTable["expansion"] = expansion
            sceneTable["sceneType"] = sceneType
            sceneTable["direction"] = sceneDirection
            sceneTable["brightness"] = brightness
			sceneTable["luminance"] = luminance
            sceneTable["colors"] = colorArray
            table["sceneInfo"] = sceneTable
        end
    elseif opCode == 0x06 then --音乐律动
        local musicTable = {};
        local openMusic = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local musicMode = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local direction = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local sensitivity = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local colorCount = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local colorArray = {}
        for i = 1, colorCount, 1 do
            local color = string.sub(bleData, index, index+2)
            index = index + 3;
            colorArray[i] = string.upper('#'..ConvertHexString(color));
        end

        musicTable["openMusic"] = openMusic;
        musicTable["musicMode"] = musicMode;
        musicTable["direction"] = direction;
        musicTable["sensitivity"] = sensitivity;
        musicTable["colors"] = colorArray;
        table["musicInfo"] = musicTable;
    elseif opCode == 0x07 or opCode == 0x08 then  --设置灯带点数
        local lampBead = IntFromString(string.sub(bleData, index, index + 1));
        index = index + 2;
        table["lamp_bead"] = lampBead
        -- 总个数
        local totalLampBead = IntFromString(string.sub(bleData, index, index + 1));
        index = index + 2;
        table["total_lamp_bead"] = totalLampBead
    elseif opCode == 0x09 then  --设置灯带点数
        local lineStyle = string.byte(string.sub(bleData, index, index));
        table["lineStyle"] = lineStyle
    elseif opCode == 0x0A  then --设置倒计时
        local totolTime = IntFromString(string.sub(bleData, index, index + 3));
        index = index + 4;

        local countdown = IntFromString(string.sub(bleData, index, index + 3));
        index = index + 4;

        if countdown == 0 then
            table["timerId"] = 0
            table["totolTime"] = 0
            table["countdown"] = 0
        else
            table["timerId"] = 1
            table["totolTime"] = totolTime;
            table["countdown"] = countdown
        end
    elseif opCode == 0x0B then --白平衡
        local whiteBalanceTable = {}

        local whiteBalanceRed = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local whiteBalanceGreen = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local whiteBalanceBlue = string.byte(string.sub(bleData, index, index));
        index = index + 1

        whiteBalanceTable["whiteBalanceRed"] = whiteBalanceRed;
        whiteBalanceTable["whiteBalanceGreen"] = whiteBalanceGreen;
        whiteBalanceTable["whiteBalanceBlue"] = whiteBalanceBlue;

        table["whiteBalance"] = whiteBalanceTable;
    elseif opCode == 0x0C then --TV+MIC模式下灯珠数量
        local tvLampBeadsTable = {}

        local section = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local lampBeads = string.byte(string.sub(bleData, index, index));
        index = index + 1

        local confirm = string.byte(string.sub(bleData, index, index));
        index = index + 1

        tvLampBeadsTable["section"] = section;
        tvLampBeadsTable["lampBeads"] = lampBeads;
        tvLampBeadsTable["confirm"] = confirm;

        table["tvLampBeads"] = tvLampBeadsTable;
    elseif opCode == 0x0D then
        local screenSceneInfo = {}

        --灵敏度
        local speed = string.byte(string.sub(bleData, index, index));
        index = index + 1

        --亮度增强
        local expansion = string.byte(string.sub(bleData, index, index));
        index = index + 1

        --饱和度
        local brightness = string.byte(string.sub(bleData, index, index));
        index = index + 1

        --段数
        local section = string.byte(string.sub(bleData, index, index));
        index = index + 1

        screenSceneInfo["section"] = section;
        screenSceneInfo["brightness"] = brightness;
        screenSceneInfo["expansion"] = expansion;
        screenSceneInfo["speed"] = speed;

        table["screenSceneInfo"] = screenSceneInfo;
    elseif opCode == 0x0F then
        local advanceInfo = {}

        --休眠
        local dormancy = string.byte(string.sub(bleData, index, index));
        index = index + 1


        advanceInfo["dormancy"] = dormancy;

        table["advanceInfo"] = advanceInfo;
    end
    return Table2jsonString(table);
end

--广播

function AddEndString(currStr)
    local lenth = string.len(currStr);
    local resultStr = currStr;

    -- 需要补齐的长度
    local addStrLen = 32 - lenth;
    for i = 1, addStrLen, 1 do
        resultStr = resultStr.."0";
    end
    return resultStr;
end

function ReverseString(currStr)
    --每次两位取值
    local strLenth = string.len(currStr);
    local resultStr = "";
    for i = strLenth-1, 2-1, -2 do
        resultStr = resultStr..string.sub(currStr, i, i+1);
    end
    return resultStr
end

function GetTVLightMacAddress(macAddress)
    local currMacAddress = ""
    local strLenth = string.len(macAddress);
    for i = strLenth-1, 2-1 + 4, -2 do
        currMacAddress = currMacAddress..string.sub(macAddress, i, i+1);
    end
    return currMacAddress;
end

--组相关的函数 添加子设备 操作码0x01
function AddSubDeviceToGroup(addSubDeviceTableStr)
    local addSubDeviceTable = {}
    addSubDeviceTable = json2table(addSubDeviceTableStr);

    local macAddress= addSubDeviceTable["macAddress"];
    local subMacAddress = addSubDeviceTable["subMacAddress"];
    local groupId = addSubDeviceTable["groupId"];

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x",0x01);
    checkValue = checkValue ~ 0x01;

    resultStr = resultStr..string.format("%02x",groupId);
    checkValue = checkValue ~ groupId;

    --被关联设备Mac地址  取出后面8位
    resultStr = resultStr..GetTVLightMacAddress(macAddress);

    --关联设备的Mac地址,如果没有这个值，表示关联所有的子设备
    if type(subMacAddress) == "nil"then
        resultStr = resultStr.."FFFFFFFF";
    else
        resultStr = resultStr..string.sub(subMacAddress,5,-1);
    end
    

    return ReverseString(AddEndString(resultStr))
end

--解绑子设备
function RemoveSubDeviceToGroup(removeSubDeviceTableStr)
    local removeSubDeviceTable = {}
    removeSubDeviceTable = json2table(removeSubDeviceTableStr);

    local macAddress= removeSubDeviceTable["macAddress"];
    local subMacAddress = removeSubDeviceTable["subMacAddress"];
    local groupId = removeSubDeviceTable["groupId"];

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x",0x00);
    checkValue = checkValue ~ 0x00;

    resultStr = resultStr..string.format("%02x",groupId);
    checkValue = checkValue ~ groupId;

    --被关联设备Mac地址  取出后面8位
    resultStr = resultStr..GetTVLightMacAddress(macAddress);

    --关联设备的Mac地址
    resultStr = resultStr..string.sub(subMacAddress,5,-1);

    return ReverseString(AddEndString(resultStr))

end

--解散群组 0x02
function RemoveGroup(removeGroupTableStr)
    local removeGroupTable = {}
    removeGroupTable = json2table(removeGroupTableStr);

    local macAddress= removeGroupTable["macAddress"];
    local groupId = removeGroupTable["groupId"];

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x",0x02);
    checkValue = checkValue ~ 0x02;

    if type(groupId) == "nil" then
        groupId = 0x00;
    end
    resultStr = resultStr..string.format("%02x",groupId);
    checkValue = checkValue ~ groupId;

    --被关联设备Mac地址  取出后面8位
    resultStr = resultStr..GetTVLightMacAddress(macAddress);

    --关联设备的Mac地址
    resultStr = resultStr.."00000000";
    return ReverseString(AddEndString(resultStr))
end

-- 取消设备群组关联
function CanelBindGroup(cancelBindGroupTableStr)
    local cancelBindGroupTable = {}
    cancelBindGroupTable = json2table(cancelBindGroupTableStr);

    local macAddress= cancelBindGroupTable["macAddress"];
    local groupId = cancelBindGroupTable["groupId"];

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x",0x03);
    checkValue = checkValue ~ 0x03;

    if type(groupId) == "nil" then
        groupId = 0x00;
    end
    resultStr = resultStr..string.format("%02x",groupId);
    checkValue = checkValue ~ groupId;

    --被关联设备Mac地址  取出后面8位
    resultStr = resultStr..GetTVLightMacAddress(macAddress);

    --关联设备的Mac地址
    resultStr = resultStr.."00000000";
    return ReverseString(AddEndString(resultStr))
end


-- 取消设备群组关联
function SetBindGroup(cancelBindGroupTableStr)
    local cancelBindGroupTable = {}
    cancelBindGroupTable = json2table(cancelBindGroupTableStr);

    local macAddress= cancelBindGroupTable["macAddress"];
    local groupId = cancelBindGroupTable["groupId"];

    local resultStr, checkValue = GetBleDeviceStatusHeadPackage();

    resultStr = resultStr..string.format("%02x",0x04);
    checkValue = checkValue ~ 0x04;

    if type(groupId) == "nil" then
        groupId = 0x00;
    end
    resultStr = resultStr..string.format("%02x",groupId);
    checkValue = checkValue ~ groupId;

    --被关联设备Mac地址  取出后面8位
    resultStr = resultStr..GetTVLightMacAddress(macAddress);

    --关联设备的Mac地址
    resultStr = resultStr.."00000000";
    return ReverseString(AddEndString(resultStr))
end


--local myTest = ControlBleDevice("{\"sceneInfo\": {\n    \"sceneId\": 0,\n    \"brightness\": 30,\n    \"speed\": 100,\n    \"expansion\": 0,\n    \"changeMode\": 241,\n    \"section\": 1,\n    \"musicMode\": 1,\n    \"direction\": 0,\n  \"luminance\": 30},\"mac\":\"202303131128\",\"productId\":\"3111fbae\"}")
--local myTest = ControlBleDevice("{\"mode\": 2,\"mac\":\"202303131128\",\"productId\":\"3111fbae\"}")
--print(string.format("out control ble data:%s",myTest))

--local testClass = BleRecieveDataResolv("0aa5000500f1640001011e")
--local testClass = BleRecieveDataResolv("0aa5000202")
--print(testClass)