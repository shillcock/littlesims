local NodeType = dmz.object_type.new ("ls_node")
local NodeLinkHandle = dmz.handle.new ("Node_Link")
local SmallState = dmz.definitions.lookup_state ("LS_Small")
local MediumState = dmz.definitions.lookup_state ("LS_Medium")
local LargeState = dmz.definitions.lookup_state ("LS_Large")

local function local_random (min, max, offset)
   local result = 0
   if offset > 0 then
      local range = math.floor ((max - min) / offset)
      result = math.random (0, range - 1)
   end
   return math.floor (result)
end

local function random_position (self)
   local x, y = 0, 0
   local done = false
   while not done do
      x = local_random (self.min.x, self.max.x, self.offset)
      y = local_random (self.min.y, self.max.y, self.offset)
      if not self.grid then self.grid = {} end
      if not self.grid[x] then self.grid[x] = {} end
      if not self.grid[x][y] then
         self.grid[x][y] = true
         done = true
      end
   end
   return dmz.vector.new (
      (x * self.offset) + self.min.x + self.offset,
      0,
      (y * self.offset) + self.min.y + self.offset)
end

local function is_linked (obj1, obj2)
   local sub = dmz.object.sub_links (obj1, NodeLinkHandle)
   if not sub then sub = {} end
   local super = dmz.object.super_links (obj1, NodeLinkHandle)
   if not super then super = {} end
--if super[obj2] or sub[obj2] then print ("already linked") end
   return super[obj2] or sub[obj2]
end

local function find_third_object (self, obj1, obj2)
   local place = math.random (#self.index)
   local result = self.index[place]
   while (result.handle == obj1) or (result.handle == obj2) do
      place = place + 1
      if place > #self.index then place = 1 end
      result = self.index[place]
   end
   return result.handle
end

local function clear_canvas (self)
   for _, obj in ipairs (self.index) do
      dmz.object.destroy (obj.handle)
   end
   self.objects = {}
   self.index = {}
   self.links = {}
   self.grid = nil
end

local function init_smallworld (self)
   for v = 1, self.objectCount, 1 do
      local obj = dmz.object.create (NodeType)
      dmz.object.position (obj, nil, random_position (self))
      dmz.object.state (obj, nil, SmallState)
      self.index[v] = { handle = obj, links = 0 }
      self.objects[obj] = self.index[v]
      dmz.object.activate (obj)
      dmz.object.set_temporary (obj)
   end
   for v = 1, self.linkCount, 1 do
      local obj1 = math.random (self.objectCount)
      local obj2 = math.random (self.objectCount)
      if obj1 ~= obj2 then
         obj1 = self.index[obj1].handle
         obj2 = self.index[obj2].handle

         if not is_linked (obj1, obj2) then
            self.links[#self.links + 1] = dmz.object.link (NodeLinkHandle, obj1, obj2)
         end
      end
   end
end

local function update_smallworld (self)
   local place = math.random (#self.links)
   local link = self.links[place]
   if link then
      local attr, obj1, obj2 = dmz.object.lookup_linked_objects (link)
      if obj1 and obj2 then
         local obj3 = find_third_object (self, obj1, obj2)
         if obj3 then
            local v1 = dmz.object.position (obj1)
            local v2 = dmz.object.position (obj2)
            local v3 = dmz.object.position (obj3)
            if v1 and v2 and v3 then
               local d12 = (v1 - v2):magnitude ()
               local d13 = (v1 - v3):magnitude ()
               local d23 = (v2 - v3):magnitude ()
               if (d12 > d13) or (d12 > d23) then
                  local origLink = link
                  self.links[place] = nil
                  if (d13 < d23) and not is_linked (obj1, obj3) then
                     self.links[place] = dmz.object.link (NodeLinkHandle, obj1, obj3)
--print ("Link 1 and 3", d13, d12, d23)
                  end
                  if not self.links[place] and (d23 < d12) and not is_linked (obj2, obj3) then
--print ("Link 2 and 3", d23, d12, d13)
                     self.links[place] = dmz.object.link (NodeLinkHandle, obj2, obj3)
                  end
                  if not self.links[place] then self.links[place] = origLink
--print ("Link 1 and 2", d12, d23, d13)
                  else dmz.object.unlink (origLink)
                  end
               end
            end
         end
      end
   else self.log:error ("No link found at: " .. place)
   end
end

local function rank_nodes (self)
   table.sort (self.index, function (v1, v2) return v1.links > v2.links end)
   local largeValue = nil
   local mediumValue = nil
   for index, obj in ipairs (self.index) do
      local state = SmallState
      if not largeValue then largeValue = obj.links end
      if obj.links == largeValue then state = LargeState
      elseif not mediumValue then mediumValue = obj.links
      end
      if obj.links == mediumValue then state = MediumState end
      dmz.object.state (obj.handle, nil, state)
   end
end

local function update_time_slice (self, time)
   update_smallworld (self)
   rank_nodes (self)
end

local function link_objects (self, link, attr, super, sub)
   self.objects[super].links = self.objects[super].links + 1
   self.objects[sub].links = self.objects[sub].links + 1
end

local function unlink_objects (self, link, attr, super, sub)
   self.objects[super].links = self.objects[super].links - 1
   self.objects[sub].links = self.objects[sub].links - 1
end


local function start (self)
   self.handle = self.timeSlice:create (update_time_slice, self, self.name)
   local cb = { link_objects = link_objects, unlink_objects = unlink_objects, }
   self.objObs:register (NodeLinkHandle, cb, self)
   init_smallworld (self);
end


local function stop (self)
   if self.handle and self.timeSlice then self.timeSlice:destroy (self.handle) end
end


function new (config, name)
   local self = {
      start_plugin = start,
      stop_plugin = stop,
      name = name,
      log = dmz.log.new ("lua." .. name),
      timeSlice = dmz.time_slice.new (),
      objObs = dmz.object_observer.new (),
      config = config,
      index = {},
      objects = {},
      links = {},
      min = { x = -300, y = -300, },
      max = { x = 280, y = 280, },
      offset = 20,
      objectCount = 50,
      linkCount = 100,
   }

   self.log:info ("Creating plugin: " .. name)
   
   return self
end
