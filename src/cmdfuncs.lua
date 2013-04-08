------------------------------------------------------------------------
-- The command functions
------------------------------------------------------------------------

require("strict")
require("myGlobals")
require("string_trim")
require("escape")
require("TermWidth")
local BeautifulTbl = require('BeautifulTbl')
local ColumnTable  = require('ColumnTable')
local Dbg          = require("Dbg")
local MName        = require("MName")
local Spider       = require("Spider")
local concatTbl    = table.concat
local getenv       = os.getenv
local hook         = require("Hook")
local posix        = require("posix")

local s_readRC     = false
RCFileA = {
   pathJoin(os.getenv("HOME"),".lmodrc.lua"),
   pathJoin(cmdDir(),"../../etc/.lmodrc.lua"),
   pathJoin(cmdDir(),"../init/.lmodrc.lua"),
   os.getenv("LMOD_RC"),
}

function readRC()
   if (s_readRC) then
      s_readRC = true
      return 
   end

   declare("propT",       false)
   declare("scDescriptT", false)
   local results = {}

   for i = 1,#RCFileA do
      local f  = RCFileA[i]
      local fh = io.open(f)
      if (fh) then
         assert(loadfile(f))()
         fh:close()
         break
      end
   end
   s_propT       = _G.propT         or {}
   s_scDescriptT = _G.scDescriptT   or {}
end

function getPropT()
   return s_propT
end

function getSCDescriptT()
   return s_scDescriptT
end

function UUIDString(epoch)
   local ymd  = os.date("*t", epoch)

   --                                y    m    d    h    m    s
   local uuid_date = string.format("%d_%02d_%02d_%02d_%02d_%02d", 
                                   ymd.year, ymd.month, ymd.day, 
                                   ymd.hour, ymd.min,   ymd.sec)
   
   local uuid_str  = capture("uuidgen"):sub(1,-2)
   local uuid      = uuid_date .. "-" .. uuid_str

   return uuid
end

function Purge()
   local master = Master:master()
   local mt     = MT:mt()
   local dbg    = Dbg:dbg()

   local totalA  = mt:list("short","any")

   if (#totalA < 1) then
      return
   end

   local a = {}
   for _,v in ipairs(totalA) do
      a[#a + 1] = v
   end
   dbg.start("Purge(",concatTbl(a,", "),")")

   MCP:unload(unpack(a))

   -- Make Default Path be the new MODULEPATH

   mt:buildMpathA(mt:getBaseMPATH())

   dbg.fini("Purge")
end

local __expert = false

function expert()
   if (__expert == false) then
      __expert = getenv("LMOD_EXPERT")
   end
   return __expert
end


function extractVersion(full, sn)
   if (full == nil or sn == nil) then
      return nil
   end
   local pat     = '^' .. escape(sn) .. '/?'
   local version = full:gsub(pat,"")
   if (version == "") then
      version = nil
   end
   return version
end


function path_regularize(value)
   if value == nil then return nil end

   value = value:gsub("//+","/")
   value = value:gsub("/%./","/")
   value = value:gsub("/$","")
   return value
end

function readAdmin()

   -- If there is anything in [[adminT]] then return because
   -- this routine has already read in the file.
   if (next (adminT)) then return end

   local adminFn = getenv("LMOD_ADMIN_FILE") or pathJoin(cmdDir(),"../../etc/admin.list")
   local f       = io.open(adminFn,"r")

   -- Put something in adminT so that this routine will not be
   -- run again even if the file does not exist.
   adminT["foo"] = "bar"

   if (f) then
      local whole = f:read("*all") .. "\n"
      f:close()


      -- Parse file: ignore "#" comment lines and blank lines
      -- Split lines on ":" module:message

      local state = "init"
      local key   = "unknown"
      local value = nil
      local a     = {}

      for v in whole:split("\n") do

         if (v:sub(1,1) == "#") then
            -- ignore this comment line


         elseif (v:find("^%s*$")) then
            if (state == "value") then
               value       = concatTbl(a, " ")
               a           = {}
               adminT[key] = value
               state       = "init"
            end

            -- Ignore blank lines
         elseif (state == "value") then
            a[#a+1]     = v:trim()
         else
            local i     = v:find(":")
            if (i) then
               key      = v:sub(1,i-1):trim()
               local  s = v:sub(i+1):trim()
               if (s:len() > 0) then
                  a[#a+1]  = s
               end
               state    = "value"
            end
         end
      end
   end
end


function prtErr(...)
   io.stderr:write(...)
end

function length(s)
   s = s:gsub("\027[^m]+m","")
   return s:len()
end

function List(...)
   local dbg    = Dbg:dbg()
   dbg.start("List(...)")
   local mt = MT:mt()

   local totalA = mt:list("userName","any")
   if (#totalA < 1) then
      local dbg = Dbg:dbg()
      LmodWarning("No modules installed\n")
      return
   end

   local wanted = {}
   for i,v in ipairs{...} do
      wanted[i] = v
   end


   local msg     = "Currently Loaded Modules"
   local activeA = mt:list("short","active")
   local a       = {}
   local msg2    = ":"

   if (#wanted == 0) then
      wanted[1] = ".*"
   else
      msg2 = " Matching: " .. table.concat(wanted," or ")
   end

   io.stderr:write("\n",msg,msg2,"\n")
   local k = 0
   local legendT = {}
   for i = 1, #activeA do
      local mname = MName:new("mt",activeA[i])
      local sn    = mname:sn()
      local m = mt:fullName(sn)
      for j = 1, #wanted do
         local p = wanted[j]
         if (m:find(p,1,true) or m:find(p)) then
            k = k + 1
            a[#a + 1] = mt:list_property(k, sn, "short", legendT)
         end
      end
   end

   if (k == 0) then
      io.stderr:write("  None found.\n")
   else
      local ct = ColumnTable:new{tbl=a, gap=0, len=length}
      io.stderr:write(ct:build_tbl(),"\n")
   end

   if (next(legendT)) then
      local term_width = TermWidth()
      io.stderr:write("\n  Where:\n")
      a = {}
      for k, v in pairsByKeys(legendT) do
         a[#a+1] = { "   " .. k ..":", v}
      end
      local bt = BeautifulTbl:new{tbl=a, column = term_width-1}
      io.stderr:write(bt:build_tbl(),"\n")
   end
   a = {}
   k = 0

   local k = 0
   for i = 1, #totalA do
      local v = totalA[i]
      dbg.print("inactive check v: ",v.name,"\n")
      if (not mt:have(v.sn,"active")) then
         local name = v.name
         for j = 1, #wanted do
            local p = wanted[j]
            if (name:find(p,1,true) or name:find(p)) then
               k       = k + 1
               a[#a+1] = {"  " .. tostring(k).. ")" , name}
            end
         end
      end
   end

   if (#a > 0) then
      io.stderr:write("\nInactive Modules",msg2,"\n")
      local ct = ColumnTable:new{tbl=a,gap=0}
      io.stderr:write(ct:build_tbl(),"\n")
   end
   dbg.fini("List")
end

function activateWarning()
   s_haveWarnings = true
end

function deactivateWarning()
   s_haveWarnings = false
end

function haveWarnings()
   return s_haveWarnings
end

function setWarningFlag()
   s_warning = true
end
function getWarningFlag()
   return s_warning
end


function readCacheFile(lastUpdateEpoch, cacheType, cacheFileA, moduleDirT, moduleT)

   local dbg        = Dbg:dbg()
   dbg.start("readCacheFile(lastUpdateEpoch, cacheType, cacheFileA, moduleDirT, moduleT)")
   local mt         = MT:mt()
   ancient = mt:getRebuildTime() or ancient

   local dirsRead = 0

   for i = 1,#cacheFileA do
      local f = cacheFileA[i].file

      if (not isFile(f)) then
         dbg.print("non-existant cacheFile: ",f,"\n")
      else
         dbg.print("cacheFile found: ",f,"\n")
         local attr   = lfs.attributes(f)

         -- Check Time

         local diff         = attr.modification - lastUpdateEpoch
         local buildModuleT = diff < 0  -- rebuild when older than lastUpdateEpoch
         dbg.print("timeDiff: ",diff," buildModuleT: ", buildModuleT,"\n")

         if (not buildModuleT) then
         
            -- Check for matching default MODULEPATH.
            assert(loadfile(f))()
            
            local version = (rawget(_G,"moduleT") or {}).version or 0

            dbg.print("version: ",version,"\n")
            if (version < Cversion) then
               dbg.print("Ignoring old style cache file!\n")
            else
               for k, v in pairs(_G.moduleT) do
                  if ( k:sub(1,1) == '/' ) then
                     local dirTime = moduleDirT[k] or -1
                     if (attr.modification > dirTime) then
                        dbg.print("saving directory: ",k," from cache file: f\n")
                        moduleDirT[k] = attr.modification
                        moduleT[k]    = v
                        dirsRead      = dirsRead + 1
                     end
                  else
                     moduleT[k] = moduleT[k] or v
                  end
               end
            end
         end
      end
   end
   dbg.fini("readCacheFile")
   return dirsRead
end

s_moduleDirT = {}
s_moduleT    = {}

function getModuleT(fast)

   local dbg        = Dbg:dbg()
   local mt         = MT:mt()
   local HOME       = os.getenv("HOME") or ""
   local cacheDir   = pathJoin(HOME,".lmod.d",".cache")
   local masterTbl  = masterTbl()
   local usrCacheFileA = {
      { file = pathJoin(cacheDir,   "moduleT.lua"),     fileT = "your"  },
   }
   local userModuleTFN = pathJoin(cacheDir,"moduleT.lua")

   dbg.start("getModuleT(fast=", fast,")")

   local mcp_old = mcp
   mcp           = MasterControl.build("spider")
   dbg.print("Setting mpc to ", mcp:name(),"\n")
   
   local lastUpdateEpoch = epoch() - ancient

   local t = {}
   hook.apply("parse_updateFn", updateSystemFn, t)

   lastUpdateEpoch = t.lastUpdateEpoch or lastUpdateEpoch
   local hostType  = t.hostType or ""

   local sysCacheFileA = {}      
   for d in sysCacheDirs:split(":") do
      if (hostType ~= "") then
         sysCacheFileA[#sysCacheFileA+1] =
            { file = pathJoin(d, hostType, "moduleT.lua"), fileT = "system"}
         sysCacheFileA[#sysCacheFileA+1] =
            { file = pathJoin(d, hostType, "moduleT.old.lua"), fileT = "system"}
      end
      sysCacheFileA[#sysCacheFileA+1] =
         { file = pathJoin(d, "moduleT.lua"),     fileT = "system"}
      sysCacheFileA[#sysCacheFileA+1] = 
         { file = pathJoin(d, "moduleT.old.lua"), fileT = "system"}
   end

   local baseMpath = mt:getBaseMPATH()
   if (baseMpath == nil) then
     LmodError("The Env Variable: \"", DfltModPath, "\" is not set\n")
   end

   ---------------------------------------------------------------------------
   -- Since this function can get called many time, we need to only recompute
   -- Directories we have not yet seen

   for path in baseMpath:split(":") do
      s_moduleDirT[path] = s_moduleDirT[path] or -1
   end

   local buildModuleT = true
   local moduleTFN    = nil

   -----------------------------------------------------------------------------
   -- Read system cache file if it exists and is not out-of-date.

   local sysDirsRead = 0
   if (not masterTbl.checkSyntax) then
      sysDirsRead = readCacheFile(lastUpdateEpoch, "system", sysCacheFileA,
                                  s_moduleDirT, s_moduleT)
   end
   
   ------------------------------------------------------------------------
   -- Read user cache file if it exists and is not out-of-date.

   local usrDirsRead = readCacheFile(epoch() - ancient, "user", usrCacheFileA, s_moduleDirT, s_moduleT)
   
   ------------------------------------------------------------------------
   -- Find all the directories not read in yet.

   local moduleDirA = {}
   for k,v in pairs(s_moduleDirT) do
      if (v < 0) then
         dbg.print("rebuilding cache for directory: ",k,"\n")
         moduleDirA[#moduleDirA+1] = k
      end
   end

   local buildModuleT = (#moduleDirA > 0)
   local userModuleT  = {}
   local dirsRead     = sysDirsRead + usrDirsRead

   dbg.print("buildModuleT: ",buildModuleT,"\n")

   ------------------------------------------------------------
   -- Do not build cache if fast is required and no cache files
   -- have been found.
   
   if (dirsRead == 0 and fast) then
      mcp = mcp_old
      dbg.print("Resetting mpc to ", mcp:name(),"\n")
      dbg.fini("getModuleT")
      return nil
   end


   if (buildModuleT) then
      local errRtn  = LmodError
      local message = LmodMessage
      LmodError     = dbg.quiet
      LmodMessage   = dbg.quiet
      local short   = mt:getShortTime()
      local prtRbMsg = ((not masterTbl.expert) and (not masterTbl.initial) and
                        ((not short) or (short > shortTime)))
      dbg.print("short: ", short, " shortTime: ", shortTime,"\n")

      if (prtRbMsg) then
         io.stderr:write("Rebuilding cache file, please wait ...")
      end

      local t1 = epoch()
      Spider.findAllModules(moduleDirA, userModuleT)
      local t2 = epoch()
      if (prtRbMsg) then
         io.stderr:write(" done.\n\n")
      end
      LmodError    = errRtn
      LmodMessage  = message
      dbg.print("t2-t1: ",t2-t1, " shortTime: ", shortTime, "\n")

      local r = {}
      hook.apply("writeCache",r)


      if (t2 - t1 < shortTime or r.dontWriteCache) then
         ancient = shortLifeCache

         ------------------------------------------------------------------------
         -- This is a bit of a hack.  Lmod needs to know the time it takes to
         -- build the cache and it needs to store it in the ModuleTable.  The
         -- trouble is with regression testing.  The module table is only written
         -- out when it value changes.  We do not want a new module written out
         -- if the only thing that has changed is the slight variation that it
         -- took to build the cache between Lmod command runs during a regression
         -- test.  So if the old time is with-in a factor of 2 old time then
         -- keep the old time.

         local newShortTime = t2-t1
         if (short and 2*short > newShortTime) then
            newShortTime = short
         end
         mt:setRebuildTime(ancient, newShortTime)
      else
         mkdir_recursive(cacheDir)
         local s0 = "-- Date: " .. os.date("%c",os.time()) .. "\n"
         local s1 = "ancient = " .. tostring(math.floor(ancient)) .."\n"
         local s2 = serializeTbl{name="moduleT",      value=userModuleT,
                                 indent=true}
         local f  = io.open(userModuleTFN,"w")
         if (f) then
            f:write(s0,s1,s2)
            f:close()
         end
         dbg.print("Wrote: ",userModuleTFN,"\n")
         local buildT   = t2-t1
         local ancient2 = math.min(buildT * 120, ancient)

         mt:setRebuildTime(ancient2, buildT)
      end
      for k, v in pairs(userModuleT) do
         s_moduleT[k] = userModuleT[k]
      end

   else
      ancient = _G.ancient or ancient
      mt:setRebuildTime(ancient, false)
   end

   -- remove user cache file if old
   if (isFile(userModuleTFN)) then
      local attr   = lfs.attributes(userModuleTFN)
      local diff   = os.time() - attr.modification
      if (diff > ancient) then 
         posix.unlink(userModuleTFN);
         dbg.print("Deleted: ",userModuleTFN,"\n")
      end
   end

   mcp = mcp_old
   dbg.print("Resetting mpc to ", mcp:name(),"\n")
   dbg.fini("getModuleT")
   return s_moduleT
end
