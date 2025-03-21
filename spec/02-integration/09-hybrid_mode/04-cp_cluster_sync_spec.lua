local helpers = require "spec.helpers"

local function find_in_file(filepath, pat)
  local f = assert(io.open(filepath, "r"))

  local line = f:read("*l")

  local found = false
  while line and not found do
    if line:find(pat, 1, true) then
      found = true
    end

    line = f:read("*l")
  end

  f:close()

  return found
end


for _, v in ipairs({ {"off", "off"}, {"on", "off"}, {"on", "on"}, }) do
  local rpc, rpc_sync = v[1], v[2]

for _, strategy in helpers.each_strategy() do
  describe("CP/CP sync works with #" .. strategy .. " rpc_sync=" .. rpc_sync .. " backend", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, { "routes", "services" })

      assert(helpers.start_kong({
        prefix = "servroot",
        admin_listen = "127.0.0.1:9000",
        admin_gui_listen = "off",
        cluster_listen = "127.0.0.1:9005",

        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_rpc = rpc,
        cluster_rpc_sync = rpc_sync,
      }))

      assert(helpers.start_kong({
        prefix = "servroot2",
        admin_listen = "127.0.0.1:9001",
        admin_gui_listen = "off",
        cluster_listen = "127.0.0.1:9006",

        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_rpc = rpc,
        cluster_rpc_sync = rpc_sync,
      }))

    end)

    lazy_teardown(function()
      assert(helpers.stop_kong("servroot"))
      assert(helpers.stop_kong("servroot2"))
    end)

    it("syncs across other nodes in the cluster", function()
      local admin_client_2 = assert(helpers.http_client("127.0.0.1", 9001))

      local res = admin_client_2:post("/services", {
        body = { name = "example", url = "http://example.dev" },
        headers = { ["Content-Type"] = "application/json" }
      })
      assert.res_status(201, res)

      assert(admin_client_2:close())

      local cfg = helpers.test_conf
      local filepath = cfg.prefix .. "/" .. cfg.proxy_error_log
      helpers.wait_until(function()
        return find_in_file(filepath,
        -- this line is only found on the other CP (the one not receiving the Admin API call)
                          "clustering] received clustering:push_config event for services:create") and
          find_in_file(filepath,
            "worker-events: handling event; source=clustering, event=push_config")
      end, 10)
    end)
  end)
end -- for _, strategy
end -- for rpc_sync
