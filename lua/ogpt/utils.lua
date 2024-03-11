local Config = require("ogpt.config")
local Path = require("plenary.path")
local Job = require("plenary.job")
local M = {}

local ESC_FEEDKEY = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)

function M.split(text)
  local t = {}
  for str in string.gmatch(text, "%S+") do
    table.insert(t, str)
  end
  return t
end

function M.split_string_by_line(text)
  local lines = {}
  if text then
    for line in (text .. "\n"):gmatch("(.-)\n") do
      table.insert(lines, line)
    end
  end
  return lines
end

function M.max_line_length(lines)
  local max_length = 0
  for _, line in ipairs(lines) do
    local str_length = string.len(line)
    if str_length > max_length then
      max_length = str_length
    end
  end
  return max_length
end

function M.wrapText(text, maxLineLength)
  local lines = M.wrapTextToTable(text, maxLineLength)
  return table.concat(lines, "\n")
end

function M.trimText(text, maxLength)
  if #text > maxLength then
    return string.sub(text, 1, maxLength - 3) .. "..."
  else
    return text
  end
end

function M.wrapTextToTable(text, maxLineLength)
  local lines = {}

  local textByLines = M.split_string_by_line(text)
  for _, line in ipairs(textByLines) do
    if #line > maxLineLength then
      local tmp_line = ""
      local words = M.split(line)
      for _, word in ipairs(words) do
        if #tmp_line + #word + 1 > maxLineLength then
          table.insert(lines, tmp_line)
          tmp_line = word
        else
          tmp_line = tmp_line .. " " .. word
        end
      end
      table.insert(lines, tmp_line)
    else
      table.insert(lines, line)
    end
  end
  return lines
end

---@return table selected range, contains {start} and {end} tables with {line} (0-indexed, end inclusive) and {character} (0-indexed, end exclusive) values
function M.get_selected_range(bufnr)
  local z_save = vim.fn.getreg("z")
  vim.cmd('silent! normal! "zy')
  local selected = vim.fn.getreg("z")
  selected = string.gsub(vim.fn.escape(selected, "\\/"), "\n", "\\n")
  vim.fn.setreg("z", z_save)
  return selected
end

function M.get_visual_lines(bufnr)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_row == 0 then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    start_row = 1
    start_col = 0
    end_row = #lines
    end_col = #lines[#lines]
  end

  -- use 1-based indexing and handle selections made in visual line mode (see :help getpos)
  start_col = start_col + 1
  end_col = math.min(end_col, #lines[#lines] - 1) + 1

  -- shorten first/last line according to start_col/end_col
  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return lines, start_row, start_col, end_row, end_col
end

function M.count_newlines_at_end(str)
  local start, stop = str:find("\n*$")
  return (stop - start + 1) or 0
end

function M.replace_newlines_at_end(str, num)
  local res = str:gsub("\n*$", string.rep("\n", num), 1)
  return res
end

function M.change_mode_to_normal()
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", false)
end

function M.change_mode_to_insert()
  vim.api.nvim_command("startinsert")
end

function M.calculate_percentage_width(percentage)
  -- Check that the input is a string and ends with a percent sign
  if type(percentage) ~= "string" or not percentage:match("%%$") then
    error("Input must be a string with a percent sign at the end (e.g. '50%').")
  end

  -- Remove the percent sign from the string
  local percent = tonumber(string.sub(percentage, 1, -2))
  local editor_width = vim.api.nvim_get_option("columns")

  -- Calculate the percentage of the width
  local width = math.floor(editor_width * (percent / 100))
  -- Return the calculated width
  return width
end

function M.match_indentation(input, output)
  local input_indent = input:match("\n*([^\n]*)"):match("^(%s*)")
  local output_indent = output:match("\n*([^\n]*)"):match("^(%s*)")
  if input_indent == output_indent then
    return output
  end
  local lines = {}
  for line in output:gmatch("([^\n]*\n?)") do
    if line:match("^%s*$") then
      table.insert(lines, line)
    else
      table.insert(lines, input_indent .. line)
    end
  end
  return table.concat(lines)
end

function M.extract_code(text)
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  return nil
end

function M.write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

-- Function to convert a nested table to a string
function M.tableToString(tbl, indent)
  indent = indent or 0
  local str = ""
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      str = str .. string.rep("  ", indent) .. k .. ":\n"
      str = str .. M.tableToString(v, indent + 1)
    else
      str = str .. string.rep("  ", indent) .. k .. ": " .. tostring(v) .. "\n"
    end
  end
  return str
end

-- Partial application of arguments using closures
function M.partial(func, ...)
  local capturedArgs = { ... }
  return function(...)
    local args = { unpack(capturedArgs) } -- Captured arguments
    for _, v in ipairs({ ... }) do
      table.insert(args, v) -- Appending new arguments
    end
    return func(unpack(args))
  end
end

function M.is_buf_exists(bufnr)
  return vim.fn.bufexists(bufnr) == 1
end

function M.trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function M.process_string(inputString)
  -- Check if the inputString contains a comma
  if inputString:find(",") then
    local resultTable = {} -- Initialize an empty table to store split values
    -- Iterate through inputString and split by commas, adding each part to the resultTable
    for word in inputString:gmatch("[^,]+") do
      table.insert(resultTable, word) -- Insert each part into the resultTable
    end
    return resultTable -- Return the resulting table
  else
    return inputString -- If no commas found, return the inputString as it is
  end
end

function M.getSelectedCode(lines)
  local text = table.concat(lines, "\n")
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  vim.notify("No codeblock found", vim.log.levels.INFO)
  return nil
end

function M.escape_pattern(text)
  -- https://stackoverflow.com/a/34953646/4780010
  return text:gsub("([^%w])", "%%%1")
end

function M.update_url_route(url, new_model)
  local host = url:match("https?://([^/]+)")
  local subdomain, domain, tld = host:match("([^.]+)%.([^.]+)%.([^.]+)")
  local _new_url = url:gsub(host, new_model .. "." .. domain .. "." .. tld)
  return _new_url
end

function M.to_model_string(messages)
  local output = ""
  for _, entry in ipairs(messages) do
    if entry.content then
      output = output .. entry.role .. ": " .. entry.content .. "\n\n"
    end
  end
  return output
end

function M.startsWith(str, start)
  return string.sub(str, 1, string.len(start)) == start
end

function M.ensureUrlProtocol(str)
  if M.startsWith(str, "https://") or M.startsWith(str, "http://") then
    return str
  end

  return "https://" .. str
end

-- Function to format a table for logging
function M.format_table(tbl, indent)
  indent = indent or 0
  local result = ""

  for key, value in pairs(tbl) do
    local keyStr = tostring(key)
    local valueStr = type(value) == "table" and M.format_table(value, indent + 1) or tostring(value)
    local indentation = string.rep("\t", indent)

    result = result .. indentation .. keyStr .. " = " .. valueStr .. "\n"
  end

  return result
end

local log_filename =
  Path:new(vim.fn.stdpath("state")):joinpath("ogpt", "ogpt-" .. os.date("%Y-%m-%d") .. ".log"):absolute() -- convert Path object to string

function M.write_to_log(msg)
  local file = io.open(log_filename, "ab")
  if file then
    file:write(os.date("[%Y-%m-%d %H:%M:%S] "))
    file:write(msg .. "\n")
    file:close()
  else
    vim.notify("Failed to open log file for writing", vim.log.levels.ERROR)
  end
end

function M.log(msg, level)
  level = level or vim.log.levels.INFO

  msg = vim.inspect(msg)
  if level >= Config.options.debug.log_level then
    M.write_to_log(msg)
  end

  if level >= Config.options.debug.notify_level then
    vim.notify(msg, level, { title = "OGPT Debug" }, level)
  end
end

function M.shallow_copy(t)
  local t2 = {}
  for k, v in pairs(t) do
    t2[k] = v
  end
  return t2
end

function M.gather_text_from_parts(parts)
  if type(parts) == "string" then
    return parts
  else
    local _text = {}
    for _, part in ipairs(parts) do
      table.insert(_text, part.text)
    end
    return table.concat(_text, " ")
  end
end

function M.extract_urls(text_with_URLs)
  -- credit goes here - https://stackoverflow.com/questions/23590304/finding-a-url-in-a-string-lua-pattern
  -- Function to extract the URL from a text string
  -- all characters allowed to be inside URL according to RFC 3986 but without
  -- comma, semicolon, apostrophe, equal, brackets and parentheses
  -- (as they are used frequently as URL separators)
  local urls = {}

  local domains = [[.ac.ad.ae.aero.af.ag.ai.al.am.an.ao.aq.ar.arpa.as.asia.at.au
   .aw.ax.az.ba.bb.bd.be.bf.bg.bh.bi.biz.bj.bm.bn.bo.br.bs.bt.bv.bw.by.bz.ca
   .cat.cc.cd.cf.cg.ch.ci.ck.cl.cm.cn.co.com.coop.cr.cs.cu.cv.cx.cy.cz.dd.de
   .dj.dk.dm.do.dz.ec.edu.ee.eg.eh.er.es.et.eu.fi.firm.fj.fk.fm.fo.fr.fx.ga
   .gb.gd.ge.gf.gh.gi.gl.gm.gn.gov.gp.gq.gr.gs.gt.gu.gw.gy.hk.hm.hn.hr.ht.hu
   .id.ie.il.im.in.info.int.io.iq.ir.is.it.je.jm.jo.jobs.jp.ke.kg.kh.ki.km.kn
   .kp.kr.kw.ky.kz.la.lb.lc.li.lk.lr.ls.lt.lu.lv.ly.ma.mc.md.me.mg.mh.mil.mk
   .ml.mm.mn.mo.mobi.mp.mq.mr.ms.mt.mu.museum.mv.mw.mx.my.mz.na.name.nato.nc
   .ne.net.nf.ng.ni.nl.no.nom.np.nr.nt.nu.nz.om.org.pa.pe.pf.pg.ph.pk.pl.pm
   .pn.post.pr.pro.ps.pt.pw.py.qa.re.ro.ru.rw.sa.sb.sc.sd.se.sg.sh.si.sj.sk
   .sl.sm.sn.so.sr.ss.st.store.su.sv.sy.sz.tc.td.tel.tf.tg.th.tj.tk.tl.tm.tn
   .to.tp.tr.travel.tt.tv.tw.tz.ua.ug.uk.um.us.uy.va.vc.ve.vg.vi.vn.vu.web.wf
   .ws.xxx.ye.yt.yu.za.zm.zr.zw]]
  local tlds = {}
  for tld in domains:gmatch("%w+") do
    tlds[tld] = true
  end
  local function max4(a, b, c, d)
    return math.max(a + 0, b + 0, c + 0, d + 0)
  end
  local protocols = { [""] = 0, ["http://"] = 0, ["https://"] = 0, ["ftp://"] = 0 }
  local finished = {}

  for pos_start, url, prot, subd, tld, colon, port, slash, path in
    text_with_URLs:gmatch("()(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w+)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))")
  do
    if
      protocols[prot:lower()] == (1 - #slash) * #path
      and not subd:find("%W%W")
      and (colon == "" or port ~= "" and port + 0 < 65536)
      and (
        tlds[tld:lower()]
        or tld:find("^%d+$")
          and subd:find("^%d+%.%d+%.%d+%.$")
          and max4(tld, subd:match("^(%d+)%.(%d+)%.(%d+)%.$")) < 256
      )
    then
      finished[pos_start] = true
      -- print(pos_start, url)
      table.insert(urls, url)
    end
  end

  for pos_start, url, prot, dom, colon, port, slash, path in
    text_with_URLs:gmatch("()((%f[%w]%a+://)(%w[-.%w]*)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))")
  do
    if
      not finished[pos_start]
      and not (dom .. "."):find("%W%W")
      and protocols[prot:lower()] == (1 - #slash) * #path
      and (colon == "" or port ~= "" and port + 0 < 65536)
    then
      -- print(pos_start, url)
      table.insert(urls, url)
    end
  end
  return urls
end

function M.system(args, writer)
  args = args or {}
  local job = Job:new({
    command = table.remove(args, 1),
    args = args or {},
    writer = writer,
  })
  return job
  -- job:sync()
  -- return table.concat(job:result(), "\n")
end

function M.curl(args, on_exit)
  local stdout_results = {}

  -- on_exit = on_exit or function(j, return_val)
  --   stdout_results = j:result()
  -- end
  local curl_args = {
    "--silent",
    "--show-error",
    "--no-buffer",
  }
  for _, arg in ipairs(args) do
    table.insert(curl_args, arg)
  end

  local job = Job:new({
    command = "curl",
    args = curl_args,
    -- on_exit = on_exit,
  })
  -- job:sync()
  -- return table.concat(job:result(), "\n")
  return job
end

return M
