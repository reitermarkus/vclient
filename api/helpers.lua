#!/usr/bin/env lua


function camel_to_underscore(str)
  str = str:gsub('(.)([A-Z][a-z]+)', '%1_%2')
  str = str:gsub('([a-z0-9])([A-Z])', '%1_%2')

  return str:lower()
end


function minify_xml(xml)
  xml = xml:gsub('\t+', ' ')
  xml = xml:gsub('\n', ' ')
  xml = xml:gsub(' +', ' ')
  xml = xml:gsub('> <', '><')
  xml = xml:gsub(' /><', '/><')
  xml = xml:gsub("='(.-)'", '="%1"')

  return xml
end


function url_decode(s)
  return s:gsub ('+', ' '):gsub ('%%(%x%x)', function (hex) return string.char(tonumber(hex, 16)) end)
end


function query_string(url)

  local result = {}
  local query_string = url:match '\?(.*)$'

  for name, value in url:gmatch('([^&=]+)=([^&=]+)') do

    value = url_decode(value)

    local key = name:match('%[([^%&%=]*)%]')

    if key then
      name, key = url_decode(name:match('^[^%[]+')), url_decode (key)

      if type(result[name]) ~= 'table' then
        result[name] = {}
      end

      if key == '' then
        key = #result[name] + 1
      else
        key = tonumber(key) or key
      end

      result[name][key] = value
    else
      name = url_decode(name)
      result[name] = value
    end

  end

  return result

end


function os.capture(cmd)
  local file = assert(io.popen(string.format("%s\nprintf '\n%%s' $?", cmd), 'r'))
  local output = assert(file:read('*a'))
  file:close()

  result, status = output:match('^(.*)\n(%d-)$')

  return {
    result = result,
    status = tonumber(status)
  }

end


function lines(input)
  return input:gmatch('[^\r\n]+')
end


function split(source, delimiters)
  local elements = {}
  local pattern = '([^' .. delimiters .. ']+)'
  string.gsub(source, pattern, function(value) elements[#elements + 1] = value;  end);
  return elements
end


function is_in_list(item, list)

  for _, itm in pairs(list) do
    if itm == item then
      return true
    end
  end

  return false

end


function is_number(number)
  if tonumber(number) == nil then
    return false
  else
    return true
  end
end
