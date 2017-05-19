#!/usr/bin/env lua

NUMBER_TYPES = {'CO', 'HKLN', 'HKLS', 'HS', 'T1U', 'TD'}


function get_config()

  local config_dir = '/etc/vcontrold'

  local file

  file = io.open(string.format('%s/%s', config_dir, 'vcontrold.xml'), "r")
  local vcontrold = minify_xml(file:read("*all"))
  file:close()

  file = io.open(string.gsub(vcontrold, '^.*<extern.->.*href="(.-)".*</extern>.*$', string.format('%s/%s', config_dir, '%1')), "r")
  local vito = minify_xml(file:read("*all"))
  file:close()

  local config = vcontrold:gsub('.*<unix>.*<config>(.*)</config>.*</unix>.*', '%1')
  local port =   config:gsub('.*<net>.*<port>(.-)</port>.*</net>.*', '%1')

  local unitlines
  unitlines = string.gsub(vcontrold, '^.*<units>(.*)</units>.*$', '%1')
  unitlines = string.gsub(unitlines, '(</unit>)', '%1\n')

  local units = {}

  for line in lines(unitlines) do
    local name   = string.match(line, 'name="(.-)"')
    local abbrev = string.match(line, '<abbrev>(.-)</abbrev>')
    local type   = string.match(line, '<type>(.-)</type>')

    units[abbrev] = {
      name = name,
      abbrev = abbrev,
      type = type
    }
  end

  local commandlines
  commandlines = string.gsub(vito, '^.*<commands>(.*)</commands>.*$', '%1')
  commandlines = string.gsub(commandlines, '(</command>)', '%1\n')
  commandlines = string.gsub(commandlines, "='(.-)'", '="%1"')

  local commands = {
    commands = {
      name = 'commands',
      desc = 'Available Commands'
    }
  }

  for line in lines(commandlines) do
    local name = string.match(line, 'name="(.-)"')
    local type = string.match(line, 'protocmd="(.-)"')
    local addr = string.match(line, '<addr>([A-F0-9][A-F0-9][A-F0-9][A-F0-9])</addr>')
    local len  = string.match(line, '<len>(%d)</len>')
    local unit = string.match(line, '<unit>(.-)</unit>')
    local desc = string.match(line, '<description>(.-)</description>')

    if string.match(line, '<description/>') then
      desc = ''
    end

    commands[name] = {
      name = name,
      type = type,
      addr = addr,
      len  = tonumber(len),
      unit = unit,
      desc = desc
    }

  end

  commands.commands.len = 0
  for _ in pairs(commands) do
    commands.commands.len = commands.commands.len + 1
  end


  config = {
    dir = config_dir,
    units = units,
    commands = commands,
    port = port
  }

  return config

end


function time_to_iso(time)

  if type(time) == 'string' then
    time = time:gsub("%u%l,([0-3]%d)\.([0-1]%d)\.(%d%d%d%d) ([0-2]%d)\:([0-5]%d)\:([0-5]%d)", "%3-%2-%1T%4:%5:%6")
  end

  return time

end


function error_to_table(error)

  local result = error

  if type(error) == 'string' then

    local date, text, code = error:match('^(%d%d%d%d%-[01]%d%-[0-3]%dT[0-2]%d%:[0-5]%d%:[0-5]%d) (.*) %((..)%)$')

    if date and text and code then
      result = {
        date = date,
        text = text,
        code = code
      }
    end

  end

  return result

end


function timer_to_table(timer)

  local result = timer

  if type(result) == 'string' then

    if result:match('1\:.*\:[0-2\-][0-9\-].*2\:.*\:[0-2\-][0-9\-].*3\:.*\:[0-2\-][0-9\-].*4\:.*\:[0-2\-][0-2\-]') then

      result = {}

      timer = timer:gsub('%-%-', '--:--')

      for line in lines(timer) do

        local id, on_full, on_hh, on_mm, off_full, off_hh, off_mm  = line:match('(%d):An:((..):(..)) +Aus:((..):(..))')

        local full = string.format('%s - %s', on_full, off_full)
        local full_plain = full:gsub(' - ', ' '):gsub('^(%-%-.-%-%-)$', '--')

        if not result.full then
          result.full = {
            formatted = full,
            plain = full_plain
          }
        else
          result.full = {
            formatted = string.format('%s, %s', result.full.formatted, full),
            plain = string.format('%s %s', result.full.plain, full_plain)
          }
        end

        result[id] = {
          full = full,
          from  = {
            full = on_full,
            hh   = on_hh,
            mm   = on_mm
          },
          to = {
            full = off_full,
            hh   = off_hh,
            mm   = off_mm
          }
        }

      end

    end

  end

  return result

end


function vclient_cli(cmd, format)

  local format = format or '\$R1'

  local template_name = string.format('/tmp/vclient.%s.tpl', string.gsub(format, '[^%a%d]', ''))
  local template_file = io.open(template_name, "w+")
        template_file:write(format)
        template_file:close()

  return os.capture(string.format("vclient -h 127.0.0.1:%d -c '%s' -t '%s'", get_config().port, cmd, template_name))

end


function cache(command, write_only)

  local cache_dir = '/tmp/vclient_cache/commands'
  local write_only = false or write_only
  local result

  if not write_only and command.type == 'getaddr' then
    os.execute(string.format("mkdir -p '%s'", cache_dir))
    cached_result = os.capture(string.format("cat '%s/%s'", cache_dir, command.name))
    if cached_result.status == 0 then
      result = cached_result
    end
  end

  if not result then

    local format
    if command.type == 'getaddr' and is_in_list(command.unit, NUMBER_TYPES) then
      format = '\$1'
    end

    local cmd = command.name
    if command.type == 'setaddr' and QUERY_STRING['set'] then
      cmd = string.format("%s %s", cmd, QUERY_STRING['set'])
    end

    result = vclient_cli(cmd, format)

    if command.type == 'getaddr' and result.status == 0 then

      local filename = string.format("%s/%s", cache_dir, command.name)

      local file = io.open(filename, "w+")
      file:write(result.result)
      file:close()

    end
  end

  if command.type == 'setaddr' then
    local commands = get_config().commands
    local get_command = string.gsub(command.name, '^set', 'get')

    if commands[get_command] then
      cache(commands[get_command], true)
    end
  end

  return result

end
