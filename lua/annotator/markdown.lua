local M = {}

local function fence_for(text)
  if (text or ""):find("```", 1, true) then
    return "````"
  end
  return "```"
end

local function line_range(annotation)
  if annotation.start_line == annotation.end_line then
    return "line " .. annotation.start_line
  end
  return "lines " .. annotation.start_line .. "–" .. annotation.end_line
end

local function sorted_annotations(items)
  table.sort(items, function(a, b)
    local a_path = a.relative_path or a.file_path
    local b_path = b.relative_path or b.file_path
    if a_path == b_path then
      if a.start_line == b.start_line then
        if a.end_line == b.end_line then
          return tostring(a.id or "") < tostring(b.id or "")
        end
        return a.end_line < b.end_line
      end
      return a.start_line < b.start_line
    end
    return a_path < b_path
  end)
  return items
end

local function has_path_prefix(path, prefix)
  return path == prefix or vim.startswith(path, prefix .. "/")
end

local function is_private_path(path)
  local normalized = vim.fn.fnamemodify(path or "", ":p")
  normalized = normalized:gsub("/+$", "")
  return has_path_prefix(normalized, "/private/var")
    or has_path_prefix(normalized, "/var")
    or has_path_prefix(normalized, "/private/tmp")
    or has_path_prefix(normalized, "/tmp")
end

local function display_file(annotation)
  if is_private_path(annotation.file_path) then
    return nil
  end
  return annotation.relative_path or annotation.file_path
end

local function quote_lines(lines, text)
  for _, line in ipairs(vim.split(tostring(text or ""), "\n", { plain = true })) do
    table.insert(lines, "> " .. line)
  end
end

local function append_fence(lines, text)
  local fence = fence_for(text)
  table.insert(lines, fence)
  table.insert(lines, text or "")
  table.insert(lines, fence)
end

local function suggestion_comment(annotation)
  local parts = {}
  if annotation.comment and annotation.comment ~= "" then
    table.insert(parts, annotation.comment)
  end
  if annotation.replacement and annotation.replacement ~= "" then
    table.insert(parts, "Suggested replacement:\n" .. annotation.replacement)
  end
  if #parts == 0 then
    return "Suggested replacement."
  end
  return table.concat(parts, "\n\n")
end

local function heading_for(annotation)
  local kind = annotation.kind or "comment"
  if kind == "delete" then
    return "Remove this"
  end
  if kind == "label" then
    local title = annotation.label_title or annotation.label or "Label"
    return "[" .. title .. "] Feedback on: \"" .. (annotation.snippet or "") .. "\""
  end
  return "Feedback on: \"" .. (annotation.snippet or "") .. "\""
end

local function append_annotation(lines, annotation, index, heading_level)
  local kind = annotation.kind or "comment"
  table.insert(lines, string.format("%s %d. (%s) %s", heading_level, index, line_range(annotation), heading_for(annotation)))

  if kind == "delete" then
    append_fence(lines, annotation.snippet)
    quote_lines(lines, "I don't want this in the message.")
  elseif kind == "suggest" then
    quote_lines(lines, suggestion_comment(annotation))
  else
    quote_lines(lines, annotation.comment or "")
  end

  table.insert(lines, "")
end

local function label_summary(items)
  local counts = {}
  local ordered = {}
  for _, annotation in ipairs(items) do
    if (annotation.kind or "comment") == "label" then
      local title = annotation.label_title or annotation.label or "Label"
      if not counts[title] then
        counts[title] = 0
        table.insert(ordered, title)
      end
      counts[title] = counts[title] + 1
    end
  end
  return ordered, counts
end

---@param items AnnotatorAnnotation[]
---@return string
function M.render(items)
  local annotations = sorted_annotations(vim.deepcopy(items))
  if #annotations == 0 then
    return "User reviewed the message and has no feedback."
  end

  local lines = {
    "# Message Feedback",
    "",
    string.format(
      "I've reviewed this message and have %d piece%s of feedback:",
      #annotations,
      #annotations == 1 and "" or "s"
    ),
    "",
  }

  local current_file = false
  for index, annotation in ipairs(annotations) do
    local file = display_file(annotation)
    local heading_level = "##"
    if file then
      if file ~= current_file then
        current_file = file
        table.insert(lines, "## " .. file)
        table.insert(lines, "")
      end
      heading_level = "###"
    else
      current_file = false
    end

    append_annotation(lines, annotation, index, heading_level)
  end

  table.insert(lines, "---")

  local labels, counts = label_summary(annotations)
  if #labels > 0 then
    table.insert(lines, "")
    table.insert(lines, "## Label Summary")
    table.insert(lines, "")
    for _, title in ipairs(labels) do
      table.insert(lines, string.format("- **%s**: %d", title, counts[title]))
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

---@param annotation AnnotatorAnnotation
---@return string
function M.preview(annotation)
  return M.render({ annotation })
end

return M
