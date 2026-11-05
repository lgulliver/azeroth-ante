-- Compiles every .lua under AzerothAnte/ and exits 1 on any error.
local p = io.popen('find AzerothAnte -name "*.lua" | sort')
local failed, count = false, 0
for path in p:lines() do
  count = count + 1
  local chunk, err = loadfile(path)
  if not chunk then
    print("FAIL " .. err)
    failed = true
  end
end
p:close()
print(count .. " files checked")
if failed then os.exit(1) end
