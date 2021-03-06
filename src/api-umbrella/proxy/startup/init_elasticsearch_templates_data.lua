local cjson = require "cjson"

local path = os.getenv("API_UMBRELLA_SRC_ROOT") .. "/config/elasticsearch_templates.json"
local f, err = io.open(path, "rb")
if err then
  ngx.log(ngx.ERR, "failed to open file: ", err)
else
  local content = f:read("*all")
  if content then
    local ok, data = pcall(cjson.decode, content)
    if ok then
      elasticsearch_templates = data
    else
      ngx.log(ngx.ERR, "failed to parse json for ", path)
    end
  end

  f:close()
end
