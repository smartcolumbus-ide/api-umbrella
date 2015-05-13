local _M = {}

local cjson = require "cjson"
local distributed_rate_limit_queue = require "distributed_rate_limit_queue"
local http = require "resty.http"
local inspect = require "inspect"
local types = require "pl.types"
local utils = require "utils"

local is_empty = types.is_empty

local delay = 1  -- in seconds
local new_timer = ngx.timer.at

local indexes_created = false

local function create_indexes()
  if not indexes_created then
    local httpc = http.new()
    local res, err = httpc:request_uri("http://127.0.0.1:8181/docs/api_umbrella/" .. config["mongodb"]["database"] .. "/system.indexes", {
      method = "POST",
      headers = {
        ["Content-Type"] = "application/json",
      },
      query = {
        extended_json = "true",
      },

      body = cjson.encode({
        ns = config["mongodb"]["database"] .. ".rate_limits",
        key = {
          updated_at = -1,
        },
        name = "updated_at",
        background = true,
      })
    })

    local httpc = http.new()
    local res, err = httpc:request_uri("http://127.0.0.1:8181/docs/api_umbrella/" .. config["mongodb"]["database"] .. "/system.indexes", {
      method = "POST",
      headers = {
        ["Content-Type"] = "application/json",
      },
      query = {
        extended_json = "true",
      },
      body = cjson.encode({
        ns = config["mongodb"]["database"] .. ".rate_limits",
        key = {
          expire_at = 1,
        },
        name = "expire_at",
        expireAfterSeconds = 0,
        background = true,
      })
    })

    indexes_created = true
  end
end

local function do_check()
  create_indexes()

  local data = distributed_rate_limit_queue.fetch()
  if is_empty(data) then
    return
  end

  for key, expire_at in pairs(data) do
    local update = {
      ["$currentDate"] = {
        updated_at = true,
      },
      ["$inc"] = {
        count = 1,
      },
    }

    if expire_at and expire_at > 0 then
      update["$setOnInsert"] = {
        expire_at = ngx.now() * 1000 + 60000,
      }
    end

    local httpc = http.new()
    local res, err = httpc:request_uri("http://127.0.0.1:8181/docs/api_umbrella/" .. config["mongodb"]["database"] .. "/rate_limits/" .. key, {
      method = "PUT",
      headers = {
        ["Content-Type"] = "application/json",
      },
      query = {
        extended_json = "true",
      },
      body = cjson.encode(update),
    })
  end
end

local function check(premature)
  if premature then
    return
  end

  local ok, err = pcall(do_check)
  if not ok then
    ngx.log(ngx.ERR, "failed to run backend load cycle: ", err)
  end

  local ok, err = new_timer(delay, check)
  if not ok then
    if err ~= "process exiting" then
      ngx.log(ngx.ERR, "failed to create timer: ", err)
    end

    return
  end
end

function _M.spawn()
  local ok, err = new_timer(0, check)
  if not ok then
    log(ERR, "failed to create timer: ", err)
    return
  end
end

return _M
