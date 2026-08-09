local h = require("helpers")

local specs = {
  "core",
  "setup",
  "root",
  "env",
  "buffers",
  "picker",
  "snacks",
  "telescope",
  "health",
  "e2e",
}

local only = vim.env.WRT_SPEC

local start = vim.uv.hrtime()
for _, name in ipairs(specs) do
  if not only or only == name then
    h.reset_state()
    h.clean_buffers()
    local ok, err = pcall(function()
      require("specs." .. name .. "_spec")(h)
    end)
    if not ok then
      h.spec(name)
      h.check(false, "spec crashed: " .. tostring(err))
    end
  end
end
h.cleanup()
local elapsed = (vim.uv.hrtime() - start) / 1e9

print("")
print(
  "──────────────────────────────────────────────────────────"
)
for _, name in ipairs(specs) do
  local counts = h.spec_summary()[name]
  if counts then
    print(("  %-10s %3d passed  %3d failed"):format(name, counts.passed, counts.failed))
  end
end
print(
  "──────────────────────────────────────────────────────────"
)
if #h.failures > 0 then
  print("")
  print("FAILURES:")
  for _, failure in ipairs(h.failures) do
    print("  - " .. failure)
  end
end
print("")
print(
  ("  total: %d assertions, %d passed, %d failed  (%.1fs)"):format(
    h.stats.passed + h.stats.failed,
    h.stats.passed,
    h.stats.failed,
    elapsed
  )
)
print("")

if h.stats.failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qall!")
end
