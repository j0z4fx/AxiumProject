--[[
    Arc/src/cache.lua
    Three cache primitives:
      - KeyedCache  : simple key->value store with optional TTL
      - LRUCache    : fixed-capacity least-recently-used eviction
      - ObjectPool  : reusable object pool to avoid GC churn
    No Axium dependencies -- safe to load standalone.
]]

local ArcCache = {}

-- Timestamp: prefer tick(), fall back to os.clock()
local function now()
    if tick then return tick() end
    return os.clock()
end

-- -- KeyedCache ----------------------------------------------------------------
-- Key->value store. Entries expire after ttl seconds if ttl is provided.

local KeyedCache = {}
KeyedCache.__index = KeyedCache

--[[
    Creates a new KeyedCache.
    defaultTTL : optional number of seconds before entries expire (nil = never)
]]
function ArcCache.newKeyedCache(defaultTTL)
    return setmetatable({
        _store      = {},   -- [key] -> { value, expiresAt }
        _defaultTTL = defaultTTL,
        _hits       = 0,
        _misses     = 0,
    }, KeyedCache)
end

-- Stores value under key. ttl overrides defaultTTL for this entry (nil = inherit)
function KeyedCache:set(key, value, ttl)
    local t = ttl or self._defaultTTL
    self._store[key] = {
        value     = value,
        expiresAt = t and (now() + t) or nil,
    }
end

-- Returns value for key, or nil if missing/expired. Updates hit/miss counters.
function KeyedCache:get(key)
    local entry = self._store[key]
    if not entry then
        self._misses = self._misses + 1
        return nil
    end
    if entry.expiresAt and now() > entry.expiresAt then
        self._store[key] = nil
        self._misses = self._misses + 1
        return nil
    end
    self._hits = self._hits + 1
    return entry.value
end

-- Returns true if key exists and has not expired
function KeyedCache:has(key)
    return self:get(key) ~= nil
end

-- Removes key from cache
function KeyedCache:delete(key)
    self._store[key] = nil
end

-- Removes all expired entries; returns count removed
function KeyedCache:purgeExpired()
    local t   = now()
    local removed = 0
    for k, entry in pairs(self._store) do
        if entry.expiresAt and t > entry.expiresAt then
            self._store[k] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Clears all entries
function KeyedCache:clear()
    self._store = {}
end

-- Returns { size, hits, misses, hitRate }
function KeyedCache:stats()
    local total = self._hits + self._misses
    return {
        size    = ArcCache._tableSize(self._store),
        hits    = self._hits,
        misses  = self._misses,
        hitRate = total > 0 and (self._hits / total) or 0,
    }
end

-- -- LRUCache ------------------------------------------------------------------
-- Fixed-capacity cache. Least-recently-used entry is evicted when full.
-- Implemented as a doubly-linked list + hash table for O(1) get/set.

local LRUCache = {}
LRUCache.__index = LRUCache

-- Internal: moves node to head (most recently used)
local function lruMoveToHead(cache, node)
    if node == cache._head then return end
    -- detach
    if node.prev then node.prev.next = node.next end
    if node.next then node.next.prev = node.prev end
    if node == cache._tail then cache._tail = node.prev end
    -- attach at head
    node.prev       = nil
    node.next       = cache._head
    if cache._head then cache._head.prev = node end
    cache._head     = node
    if not cache._tail then cache._tail = node end
end

-- Internal: removes tail (least recently used)
local function lruEvictTail(cache)
    local tail = cache._tail
    if not tail then return end
    if tail.prev then
        tail.prev.next = nil
        cache._tail    = tail.prev
    else
        cache._head = nil
        cache._tail = nil
    end
    cache._map[tail.key] = nil
    cache._size = cache._size - 1
    return tail.key, tail.value
end

--[[
    Creates a new LRUCache.
    capacity : maximum number of entries before eviction (must be >= 1)
]]
function ArcCache.newLRUCache(capacity)
    assert(type(capacity) == "number" and capacity >= 1,
        "Arc.cache.newLRUCache: capacity must be a number >= 1")
    return setmetatable({
        _capacity = capacity,
        _map      = {},     -- [key] -> node
        _head     = nil,    -- most recently used
        _tail     = nil,    -- least recently used
        _size     = 0,
        _hits     = 0,
        _misses   = 0,
        _evictions = 0,
    }, LRUCache)
end

-- Returns value for key, or nil if not present. Promotes entry to MRU position.
function LRUCache:get(key)
    local node = self._map[key]
    if not node then
        self._misses = self._misses + 1
        return nil
    end
    lruMoveToHead(self, node)
    self._hits = self._hits + 1
    return node.value
end

-- Stores key->value. Evicts LRU entry if at capacity.
function LRUCache:set(key, value)
    local node = self._map[key]
    if node then
        node.value = value
        lruMoveToHead(self, node)
        return
    end
    -- Evict if full
    if self._size >= self._capacity then
        lruEvictTail(self)
        self._evictions = self._evictions + 1
    end
    -- Insert new node at head
    local newNode = { key = key, value = value, prev = nil, next = self._head }
    if self._head then self._head.prev = newNode end
    self._head = newNode
    if not self._tail then self._tail = newNode end
    self._map[key] = newNode
    self._size     = self._size + 1
end

-- Returns true if key is present
function LRUCache:has(key)
    return self._map[key] ~= nil
end

-- Removes key; returns true if it existed
function LRUCache:delete(key)
    local node = self._map[key]
    if not node then return false end
    if node.prev then node.prev.next = node.next else self._head = node.next end
    if node.next then node.next.prev = node.prev else self._tail = node.prev end
    self._map[key] = nil
    self._size     = self._size - 1
    return true
end

-- Clears all entries
function LRUCache:clear()
    self._map  = {}
    self._head = nil
    self._tail = nil
    self._size = 0
end

-- Returns { size, capacity, hits, misses, evictions, hitRate }
function LRUCache:stats()
    local total = self._hits + self._misses
    return {
        size      = self._size,
        capacity  = self._capacity,
        hits      = self._hits,
        misses    = self._misses,
        evictions = self._evictions,
        hitRate   = total > 0 and (self._hits / total) or 0,
    }
end

-- Returns ordered array of keys from MRU to LRU
function LRUCache:keys()
    local out  = {}
    local node = self._head
    while node do
        out[#out + 1] = node.key
        node = node.next
    end
    return out
end

-- -- ObjectPool ----------------------------------------------------------------
-- Reusable object pool. Avoids GC pressure from repeated alloc/dealloc.

local ObjectPool = {}
ObjectPool.__index = ObjectPool

--[[
    Creates a new ObjectPool.
    createFn  : function() -> object   -- called when pool is empty
    resetFn   : function(obj) -> obj   -- called before returning object to caller
    maxSize   : optional cap on pool storage (default 64)
]]
function ArcCache.newObjectPool(createFn, resetFn, maxSize)
    assert(type(createFn) == "function",  "Arc.cache.newObjectPool: createFn must be function")
    assert(type(resetFn)  == "function",  "Arc.cache.newObjectPool: resetFn must be function")
    return setmetatable({
        _pool     = {},
        _createFn = createFn,
        _resetFn  = resetFn,
        _maxSize  = maxSize or 64,
        _acquired = 0,
        _released = 0,
        _created  = 0,
    }, ObjectPool)
end

-- Acquires an object from the pool (or creates a new one if empty)
function ObjectPool:acquire()
    local obj
    if #self._pool > 0 then
        obj = table.remove(self._pool)
    else
        obj = self._createFn()
        self._created = self._created + 1
    end
    obj = self._resetFn(obj)
    self._acquired = self._acquired + 1
    return obj
end

-- Returns object back to the pool. Discards if pool is at maxSize.
function ObjectPool:release(obj)
    if #self._pool < self._maxSize then
        table.insert(self._pool, obj)
    end
    self._released = self._released + 1
end

-- Discards all pooled objects
function ObjectPool:clear()
    self._pool = {}
end

-- Returns current number of objects sitting idle in the pool
function ObjectPool:available()
    return #self._pool
end

-- Returns { available, acquired, released, created, maxSize }
function ObjectPool:stats()
    return {
        available = #self._pool,
        acquired  = self._acquired,
        released  = self._released,
        created   = self._created,
        maxSize   = self._maxSize,
    }
end

-- -- Internal helpers ----------------------------------------------------------

function ArcCache._tableSize(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- -- Dev tests -----------------------------------------------------------------

if getgenv().AxiumDevMode then
    local AL = getgenv().AxiumLog
    local passed, failed_count = 0, 0

    local function pass(label)
        passed = passed + 1
        AL.info("Arc", "cache", "test", "PASS  " .. label)
    end

    local function fail(label, got, expected)
        failed_count = failed_count + 1
        AL.error("Arc", "cache", "test",
            string.format("FAIL  %s  |  got=%s  expected=%s",
                label, tostring(got), tostring(expected))
        )
    end

    local function eq(label, got, expected)
        if got == expected then pass(label) else fail(label, got, expected) end
    end

    local function assertTrue(label, v)
        if v then pass(label) else fail(label, tostring(v), "true") end
    end

    local function assertFalse(label, v)
        if not v then pass(label) else fail(label, tostring(v), "false") end
    end

    -- -- KeyedCache tests --------------------------------------------------

    local kc = ArcCache.newKeyedCache()
    kc:set("a", 42)
    eq("KC get hit",     kc:get("a"), 42)
    eq("KC get miss",    kc:get("z"), nil)
    assertTrue("KC has", kc:has("a"))
    kc:delete("a")
    assertFalse("KC delete", kc:has("a"))

    -- TTL expiry -- simulate by setting a tiny TTL and overriding now()
    -- We can't wait real seconds, so test via direct entry manipulation
    local kc2 = ArcCache.newKeyedCache(100)
    kc2:set("x", 1)
    eq("KC TTL set", kc2:get("x"), 1)
    -- Force expiry by backdating the entry
    kc2._store["x"].expiresAt = now() - 1
    eq("KC TTL expired", kc2:get("x"), nil)

    -- purgeExpired
    local kc3 = ArcCache.newKeyedCache()
    kc3:set("live", "yes")
    kc3:set("dead", "no")
    kc3._store["dead"].expiresAt = now() - 1
    local removed = kc3:purgeExpired()
    eq("KC purge count",    removed, 1)
    assertTrue("KC purge kept live", kc3:has("live"))

    -- stats
    local kcs = ArcCache.newKeyedCache()
    kcs:set("k", "v")
    kcs:get("k")   -- hit
    kcs:get("nope") -- miss
    local st = kcs:stats()
    eq("KC stats hits",   st.hits,   1)
    eq("KC stats misses", st.misses, 1)

    -- clear
    kc:set("b", 2)
    kc:clear()
    eq("KC clear", kc:get("b"), nil)

    -- -- LRUCache tests ----------------------------------------------------

    local lru = ArcCache.newLRUCache(3)
    lru:set("a", 1)
    lru:set("b", 2)
    lru:set("c", 3)
    eq("LRU get a", lru:get("a"), 1)
    eq("LRU get b", lru:get("b"), 2)
    eq("LRU get c", lru:get("c"), 3)
    eq("LRU size",  lru._size, 3)

    -- Add 4th: evicts LRU (a was accessed first among b,c,a -- but then b,c accessed after a)
    -- Order after sets: c(MRU)->b->a(LRU). Then get(a) -> a(MRU), get(b) -> b(MRU), get(c) -> c(MRU)
    -- MRU order after gets: c->b->a. LRU = a. Set d evicts a.
    lru:set("d", 4)
    eq("LRU eviction: d present",  lru:get("d"), 4)
    eq("LRU eviction: a gone",     lru:get("a"), nil)
    eq("LRU eviction size stays",  lru._size, 3)

    -- Overwrite existing key
    lru:set("b", 99)
    eq("LRU overwrite", lru:get("b"), 99)
    eq("LRU size unchanged after overwrite", lru._size, 3)

    -- has/delete
    assertTrue("LRU has b",         lru:has("b"))
    assertTrue("LRU delete b",      lru:delete("b"))
    assertFalse("LRU has b after delete", lru:has("b"))
    eq("LRU size after delete",     lru._size, 2)

    -- keys order (MRU->LRU): after deleting b, we have d and c
    -- last get was d (after set), then c was last got before d's set
    -- recheck: set a,b,c -> get a,b,c -> set d(evicts a) -> set b=99 -> get b=99 -> delete b
    -- remaining: d, c. d was set last and b overwrite moved b to head then delete,
    -- actual MRU should be d (last non-deleted access/set)
    local ks = lru:keys()
    eq("LRU keys count", #ks, 2)

    -- stats
    local lsts = lru:stats()
    assertTrue("LRU stats evictions >= 1", lsts.evictions >= 1)

    -- clear
    lru:clear()
    eq("LRU clear size", lru._size, 0)
    eq("LRU clear get",  lru:get("d"), nil)

    -- single capacity edge case
    local lru1 = ArcCache.newLRUCache(1)
    lru1:set("x", 10)
    lru1:set("y", 20)
    eq("LRU cap=1 y",     lru1:get("y"), 20)
    eq("LRU cap=1 x gone", lru1:get("x"), nil)

    -- -- ObjectPool tests --------------------------------------------------

    local createCount = 0
    local pool = ArcCache.newObjectPool(
        function() createCount = createCount + 1; return { id = createCount } end,
        function(obj) obj.used = false; return obj end,
        4
    )

    local o1 = pool:acquire()
    local o2 = pool:acquire()
    eq("Pool created 2", createCount, 2)
    eq("Pool available after 2 acquires", pool:available(), 0)

    pool:release(o1)
    pool:release(o2)
    eq("Pool available after 2 releases", pool:available(), 2)

    -- re-acquire: should reuse, not create
    local o3 = pool:acquire()
    eq("Pool reuse: no new create", createCount, 2)
    eq("Pool reset field", o3.used, false)

    -- maxSize cap: release more than maxSize
    local smallPool = ArcCache.newObjectPool(
        function() return {} end,
        function(o) return o end,
        2
    )
    for _ = 1, 5 do smallPool:release({}) end
    eq("Pool maxSize cap", smallPool:available(), 2)

    -- stats
    local pst = pool:stats()
    assertTrue("Pool stats acquired >= 3", pst.acquired >= 3)
    eq("Pool stats created", pst.created, 2)

    -- Summary
    AL.info("Arc", "cache", "tests", string.format(
        "Suite complete -- %d passed, %d failed", passed, failed_count
    ))
    if failed_count > 0 then
        AL.critical("Arc", "cache", "tests", string.format(
            "%d test(s) FAILED in Arc.cache", failed_count
        ))
    end
end

-- -- Registration --------------------------------------------------------------

local env = getgenv()
env._Axium           = env._Axium or {}
env._Axium.Arc       = env._Axium.Arc or {}
env._Axium.Arc.cache = ArcCache

if env.AxiumLoader then
    env.AxiumLoader.load("Arc.cache", function() end)
end

return ArcCache
