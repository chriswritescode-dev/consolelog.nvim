local helper = require('tests.lua.test_helper')
local assert = helper.assert
local describe = helper.describe
local it = helper.it

package.path = package.path .. ";./lua/?.lua"

describe("Monorepo Framework Detection Tests", function()
	local framework_detector
	local temp_dir
	local monorepo_root

	-- Setup before each test
	local function setup()
		framework_detector = require('consolelog.injection.framework_detector')

		-- Create temporary monorepo structure
		temp_dir = "/tmp/consolelog_monorepo_test_" .. vim.fn.getpid()
		monorepo_root = temp_dir
		vim.fn.mkdir(temp_dir, "p")

		-- Create workspace directories
		vim.fn.mkdir(temp_dir .. "/apps", "p")
		vim.fn.mkdir(temp_dir .. "/packages", "p")
	end

	-- Cleanup after each test
	local function cleanup()
		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.system("rm -rf " .. vim.fn.shellescape(temp_dir))
		end
	end

	describe("Monorepo Next.js detection", function()
		it("should detect Next.js in workspace package", function()
			setup()

			-- Create root package.json with workspaces but no Next.js
			local root_package = [[{
        "name": "monorepo",
        "private": true,
        "workspaces": [
          "apps/*",
          "packages/*"
        ]
      }]]

			vim.fn.writefile(vim.split(root_package, "\n"), monorepo_root .. "/package.json")

			-- Create Next.js app in apps/web
			local web_app_dir = monorepo_root .. "/apps/web"
			vim.fn.mkdir(web_app_dir, "p")

			local web_package = [[{
        "name": "web-app",
        "dependencies": {
          "next": "^13.0.0",
          "react": "^18.0.0"
        }
      }]]

			vim.fn.writefile(vim.split(web_package, "\n"), web_app_dir .. "/package.json")

			-- Should detect Next.js from workspace
			local framework = framework_detector.detect_framework(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.NEXTJS, framework,
				"Should detect Next.js in monorepo workspace")

			cleanup()
		end)

		it("should detect Next.js via config file", function()
			setup()

			-- Create root package.json without workspaces (to test config file fallback)
			local root_package = [[{
        "name": "simple-app"
      }]]

			vim.fn.writefile(vim.split(root_package, "\n"), monorepo_root .. "/package.json")


			vim.fn.writefile({ "module.exports = {}" }, monorepo_root .. "/next.config.js")

			-- Should detect Next.js from config file
			local framework = framework_detector.detect_framework(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.NEXTJS, framework,
				"Should detect Next.js via config file")

			cleanup()
		end)

		it("should detect Vite in workspace package", function()
			setup()

			-- Create root package.json with workspaces
			local root_package = [[{
        "name": "monorepo",
        "private": true,
        "workspaces": [
          "apps/*"
        ]
      }]]

			vim.fn.writefile(vim.split(root_package, "\n"), monorepo_root .. "/package.json")

			-- Create Vite app in apps/admin
			local admin_app_dir = monorepo_root .. "/apps/admin"
			vim.fn.mkdir(admin_app_dir, "p")

			local admin_package = [[{
        "name": "admin-app",
        "devDependencies": {
          "vite": "^4.0.0"
        }
      }]]

			vim.fn.writefile(vim.split(admin_package, "\n"), admin_app_dir .. "/package.json")

			-- Should detect Vite from workspace
			local framework = framework_detector.detect_framework(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.VITE, framework,
				"Should detect Vite in monorepo workspace")

			cleanup()
		end)

		it("should handle glob pattern workspaces", function()
			setup()

			-- Create root package.json with glob workspaces
			local root_package = [[{
        "name": "monorepo",
        "private": true,
        "workspaces": [
          "packages/*"
        ]
      }]]

			vim.fn.writefile(vim.split(root_package, "\n"), monorepo_root .. "/package.json")

			-- Create multiple packages
			local packages = { "ui", "utils", "config" }
			for _, pkg_name in ipairs(packages) do
				local pkg_dir = monorepo_root .. "/packages/" .. pkg_name
				vim.fn.mkdir(pkg_dir, "p")

				if pkg_name == "ui" then
					-- Make ui package a React package
					local pkg = [[{
            "name": "]] .. pkg_name .. [[",
            "dependencies": {
              "react": "^18.0.0",
              "react-dom": "^18.0.0"
            }
          }]]
					vim.fn.writefile(vim.split(pkg, "\n"), pkg_dir .. "/package.json")
				else
					-- Other packages are just regular node packages
					local pkg = [[{
            "name": "]] .. pkg_name .. [["
          }]]
					vim.fn.writefile(vim.split(pkg, "\n"), pkg_dir .. "/package.json")
				end
			end

			-- Should detect React from ui package
			local framework = framework_detector.detect_framework(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.REACT, framework,
				"Should detect React in glob workspace")

			cleanup()
		end)

		it("should return unknown for non-framework monorepo", function()
			setup()

			-- Create root package.json with workspaces
			local root_package = [[{
        "name": "monorepo",
        "private": true,
        "workspaces": [
          "packages/*"
        ]
      }]]

			vim.fn.writefile(vim.split(root_package, "\n"), monorepo_root .. "/package.json")

			-- Create packages without frameworks
			local packages = { "utils", "config" }
			for _, pkg_name in ipairs(packages) do
				local pkg_dir = monorepo_root .. "/packages/" .. pkg_name
				vim.fn.mkdir(pkg_dir, "p")

				local pkg = [[{
          "name": "]] .. pkg_name .. [["
        }]]
				vim.fn.writefile(vim.split(pkg, "\n"), pkg_dir .. "/package.json")
			end

			-- Should return unknown (no frameworks found)
			local framework = framework_detector.detect_framework(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.UNKNOWN, framework,
				"Should return UNKNOWN for non-framework monorepo")

			cleanup()
		end)
	end)

	describe("Workspace detection helpers", function()
		it("should detect framework in specific workspace", function()
			setup()

			-- Create a workspace with Next.js
			local workspace_dir = monorepo_root .. "/test-workspace"
			vim.fn.mkdir(workspace_dir, "p")

			local package = [[{
        "name": "test-workspace",
        "dependencies": {
          "next": "^13.0.0"
        }
      }]]

			vim.fn.writefile(vim.split(package, "\n"), workspace_dir .. "/package.json")

			local framework = framework_detector.check_workspace_for_framework(workspace_dir)
			assert.equals(framework_detector.FRAMEWORKS.NEXTJS, framework,
				"Should detect Next.js in workspace")

			cleanup()
		end)

		it("should detect framework by config files", function()
			setup()

			-- Create next.config.js
			vim.fn.writefile({ "module.exports = {}" }, monorepo_root .. "/next.config.js")

			local framework = framework_detector.detect_by_config_files(monorepo_root)
			assert.equals(framework_detector.FRAMEWORKS.NEXTJS, framework,
				"Should detect Next.js by config file")

			cleanup()
		end)
	end)
end)

