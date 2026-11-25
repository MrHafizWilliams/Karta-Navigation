-- ============================================================================
-- Karta Navigation Platform — osm2pgsql Flex Output Configuration
-- Extracts MY/SG/BN POIs, Road Speed Limits, Lane Guidance, Speed Cameras,
-- OSM Toll Nodes, and Admin Level 2 Boundaries into staging schema `osm_stage`.
-- ============================================================================

local json = nil
pcall(function() json = require('dkjson') end)

-- Minimal safe JSON serializer fallback (osm2pgsql bundles lua without external rocks)
local function escape_json_str(s)
    return s:gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
end

local function encode_json(tbl)
    if tbl == nil then return '{}' end
    local parts = {}
    for k, v in pairs(tbl) do
        if v ~= nil and v ~= '' then
            local ks = '"' .. escape_json_str(tostring(k)) .. '"'
            local vs
            if type(v) == 'number' then
                vs = tostring(v)
            elseif type(v) == 'boolean' then
                vs = v and 'true' or 'false'
            else
                vs = '"' .. escape_json_str(tostring(v)) .. '"'
            end
            parts[#parts + 1] = ks .. ':' .. vs
        end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

-- ============================================================================
-- STAGING TABLES (managed by osm2pgsql; merged into spatial/tolls/geo via SQL)
-- ============================================================================
local pois_table = osm2pgsql.define_table({
    name = 'pois',
    schema = 'osm_stage',
    ids = { type = 'any', id_column = 'osm_id', type_column = 'osm_type' },
    columns = {
        { column = 'name',           type = 'text', not_null = true },
        { column = 'name_localized', type = 'jsonb' },
        { column = 'category',       type = 'text', not_null = true },
        { column = 'subcategory',    type = 'text' },
        { column = 'brand',          type = 'text' },
        { column = 'address',        type = 'jsonb' },
        { column = 'opening_hours',  type = 'text' },
        { column = 'ev_metadata',    type = 'jsonb' },
        { column = 'tags',           type = 'jsonb' },
        { column = 'geom',           type = 'point', projection = 4326, not_null = true },
    }
})

local roads_table = osm2pgsql.define_table({
    name = 'road_segments',
    schema = 'osm_stage',
    ids = { type = 'way', id_column = 'way_id' },
    columns = {
        { column = 'name',             type = 'text' },
        { column = 'ref',              type = 'text' },
        { column = 'highway_class',    type = 'text', not_null = true },
        { column = 'oneway',           type = 'int2' },
        { column = 'maxspeed_fwd_kmh', type = 'int2' },
        { column = 'maxspeed_bwd_kmh', type = 'int2' },
        { column = 'maxspeed_source',  type = 'text' },
        { column = 'lanes_total',      type = 'int2' },
        { column = 'lanes_fwd',        type = 'int2' },
        { column = 'lanes_bwd',        type = 'int2' },
        { column = 'turn_lanes_fwd',   type = 'text' }, -- pipe-delimited raw string, split in SQL merge
        { column = 'turn_lanes_bwd',   type = 'text' },
        { column = 'hgv_prohibited',   type = 'bool' },
        { column = 'is_toll',          type = 'bool' },
        { column = 'is_bridge',        type = 'bool' },
        { column = 'is_tunnel',        type = 'bool' },
        { column = 'surface',          type = 'text' },
        { column = 'geom',             type = 'linestring', projection = 4326, not_null = true },
    }
})

local speed_zones_table = osm2pgsql.define_table({
    name = 'speed_zones',
    schema = 'osm_stage',
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'zone_type',   type = 'text', not_null = true },
        { column = 'road_name',   type = 'text' },
        { column = 'limit_kmh',   type = 'int2', not_null = true },
        { column = 'heading_deg', type = 'int2' },
        { column = 'geom',        type = 'point', projection = 4326, not_null = true },
    }
})

local toll_nodes_table = osm2pgsql.define_table({
    name = 'osm_toll_nodes',
    schema = 'osm_stage',
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'name',          type = 'text' },
        { column = 'operator_name', type = 'text' },
        { column = 'highway_ref',   type = 'text' },
        { column = 'barrier_type',  type = 'text' },
        { column = 'tags',          type = 'jsonb' },
        { column = 'geom',          type = 'point', projection = 4326, not_null = true },
    }
})

local admin_table = osm2pgsql.define_table({
    name = 'osm_admin_boundaries',
    schema = 'osm_stage',
    ids = { type = 'relation', id_column = 'osm_id' },
    columns = {
        { column = 'iso_a2',      type = 'text' },
        { column = 'name',        type = 'text' },
        { column = 'admin_level', type = 'int2' },
        { column = 'geom',        type = 'multipolygon', projection = 4326, not_null = true },
    }
})

-- ============================================================================
-- TAG PARSING HELPERS
-- ============================================================================
local ROUTABLE_HIGHWAYS = {
    motorway = true, motorway_link = true,
    trunk = true, trunk_link = true,
    primary = true, primary_link = true,
    secondary = true, secondary_link = true,
    tertiary = true, tertiary_link = true,
    unclassified = true, residential = true,
    living_street = true, service = true,
}

local DEFAULT_SPEED_KMH = {
    motorway = 110, motorway_link = 70,
    trunk = 90, trunk_link = 60,
    primary = 80, primary_link = 50,
    secondary = 70, secondary_link = 50,
    tertiary = 60, tertiary_link = 40,
    unclassified = 50, residential = 40,
    living_street = 30, service = 25,
}

local NAMED_SPEED_DEFAULTS = {
    ['MY:motorway'] = 110, ['MY:trunk'] = 90, ['MY:urban'] = 60, ['MY:rural'] = 90,
    ['SG:expressway'] = 90, ['SG:urban'] = 50,
    ['BN:motorway'] = 100, ['BN:urban'] = 50,
}

local function parse_maxspeed(val)
    if not val then return nil end
    if NAMED_SPEED_DEFAULTS[val] then
        return NAMED_SPEED_DEFAULTS[val]
    end
    local num, unit = val:match('^(%d+)%s*(%a*)$')
    if not num then return nil end
    local n = tonumber(num)
    if not n or n <= 0 or n > 200 then return nil end
    if unit == 'mph' then
        return math.floor(n * 1.60934 + 0.5)
    end
    return n
end

local function parse_int(val)
    if not val then return nil end
    local n = tonumber(val:match('^%d+$'))
    if n and n > 0 and n < 30 then return n end
    return nil
end

local function parse_oneway(tags)
    local ow = tags.oneway
    if ow == 'yes' or ow == '1' or ow == 'true' then return 1 end
    if ow == '-1' or ow == 'reverse' then return -1 end
    if ow == 'no' or ow == '0' or ow == 'false' then return 0 end
    if tags.highway == 'motorway' or tags.junction == 'roundabout' then return 1 end
    return 0
end

local function classify_poi(tags)
    local a = tags.amenity
    if a == 'fuel' then return 'fuel', 'petrol_station' end
    if a == 'charging_station' then return 'ev_charging', 'ev_charger' end
    if a == 'parking' then return 'parking', tags.parking or 'surface' end
    if a == 'hospital' or a == 'clinic' or a == 'pharmacy' then return 'healthcare', a end
    if a == 'restaurant' or a == 'cafe' or a == 'fast_food' or a == 'food_court' then return 'food', a end
    if a == 'bank' or a == 'atm' then return 'finance', a end
    if a == 'place_of_worship' then return 'worship', tags.religion or 'general' end
    if a == 'police' or a == 'fire_station' then return 'emergency', a end
    if a == 'bus_station' or a == 'ferry_terminal' then return 'transit', a end

    if tags.highway == 'services' or tags.highway == 'rest_area' then
        return 'rest_area', tags.highway
    end
    if tags.railway == 'station' or tags.railway == 'subway_entrance' or tags.public_transport == 'station' then
        return 'transit', tags.station or tags.railway or 'station'
    end
    if tags.shop == 'mall' or tags.shop == 'supermarket' or tags.shop == 'convenience' or tags.shop == 'department_store' then
        return 'shopping', tags.shop
    end
    if tags.tourism == 'hotel' or tags.tourism == 'attraction' or tags.tourism == 'museum' or tags.tourism == 'viewpoint' then
        return 'tourism', tags.tourism
    end
    if tags.aeroway == 'aerodrome' or tags.aeroway == 'terminal' then
        return 'airport', tags.aeroway
    end
    return nil, nil
end

local function build_poi_row(tags, geom)
    local category, subcategory = classify_poi(tags)
    if not category then return nil end

    local name = tags.name or tags['name:en'] or tags['name:ms'] or tags.brand or tags.operator
    if not name or name == '' then return nil end

    local name_loc = {}
    if tags['name:ms'] then name_loc.ms = tags['name:ms'] end
    if tags['name:en'] then name_loc.en = tags['name:en'] end
    if tags['name:zh'] then name_loc.zh = tags['name:zh'] end

    local address = {}
    if tags['addr:street'] then address.street = tags['addr:street'] end
    if tags['addr:postcode'] then address.postcode = tags['addr:postcode'] end
    if tags['addr:city'] then address.city = tags['addr:city'] end
    if tags['addr:state'] then address.state = tags['addr:state'] end

    local ev_meta = nil
    if category == 'ev_charging' then
        ev_meta = {}
        if tags.capacity then ev_meta.capacity = tags.capacity end
        if tags['socket:type2'] then ev_meta.type2 = tags['socket:type2'] end
        if tags['socket:type2_combo'] then ev_meta.ccs2 = tags['socket:type2_combo'] end
        if tags['socket:chademo'] then ev_meta.chademo = tags['socket:chademo'] end
        if tags['socket:type2_combo:output'] then ev_meta.ccs2_output = tags['socket:type2_combo:output'] end
        if tags.operator then ev_meta.operator = tags.operator end
    end

    local slim_tags = {}
    for _, key in ipairs({ 'operator', 'network', 'phone', 'website', 'cuisine', 'fuel:diesel', 'fuel:octane_95', 'fuel:octane_97', 'fee', 'wheelchair' }) do
        if tags[key] then slim_tags[key] = tags[key] end
    end

    return {
        name = name,
        name_localized = encode_json(name_loc),
        category = category,
        subcategory = subcategory,
        brand = tags.brand or tags.operator,
        address = encode_json(address),
        opening_hours = tags.opening_hours,
        ev_metadata = ev_meta and encode_json(ev_meta) or nil,
        tags = encode_json(slim_tags),
        geom = geom,
    }
end

-- ============================================================================
-- OSM2PGSQL CALLBACKS
-- ============================================================================
function osm2pgsql.process_node(object)
    local tags = object.tags
    if next(tags) == nil then return end

    -- 1. OSM Toll Booths & Overhead Gantries
    if tags.barrier == 'toll_booth' or tags.highway == 'toll_gantry' then
        toll_nodes_table:insert({
            name = tags.name or tags['name:en'] or tags['name:ms'],
            operator_name = tags.operator,
            highway_ref = tags.ref,
            barrier_type = tags.barrier or tags.highway,
            tags = encode_json(tags),
            geom = object:as_point(),
        })
    end

    -- 2. Speed Cameras (MY AWAS / SG TP)
    if tags.highway == 'speed_camera' then
        local spd = parse_maxspeed(tags.maxspeed) or 80
        local heading = tonumber(tags.direction)
        if heading and (heading < 0 or heading > 359) then heading = nil end
        speed_zones_table:insert({
            zone_type = 'awas_camera',
            road_name = tags.name or tags.ref,
            limit_kmh = spd,
            heading_deg = heading,
            geom = object:as_point(),
        })
    end

    -- 3. POIs
    local poi = build_poi_row(tags, object:as_point())
    if poi then
        pois_table:insert(poi)
    end
end

function osm2pgsql.process_way(object)
    local tags = object.tags
    if next(tags) == nil then return end

    -- 1. Routable Roads (Speed Limits & Lane Guidance)
    local hw = tags.highway
    if hw and ROUTABLE_HIGHWAYS[hw] then
        local explicit_spd = parse_maxspeed(tags.maxspeed)
        local fwd_spd = parse_maxspeed(tags['maxspeed:forward']) or explicit_spd
        local bwd_spd = parse_maxspeed(tags['maxspeed:backward']) or explicit_spd
        local spd_src = 'osm'
        if not fwd_spd then
            fwd_spd = DEFAULT_SPEED_KMH[hw]
            spd_src = 'default_class'
        end
        if not bwd_spd then
            bwd_spd = DEFAULT_SPEED_KMH[hw]
        end

        local oneway = parse_oneway(tags)
        local turn_fwd = tags['turn:lanes:forward'] or tags['turn:lanes']
        local turn_bwd = tags['turn:lanes:backward']
        local is_toll = (tags.toll == 'yes' or tags['toll:motorcar'] == 'yes')
        local is_bridge = (tags.bridge ~= nil and tags.bridge ~= 'no')
        local is_tunnel = (tags.tunnel ~= nil and tags.tunnel ~= 'no')
        local hgv_no = (tags.hgv == 'no' or tags.motor_vehicle == 'no')

        roads_table:insert({
            name = tags.name or tags['name:en'] or tags['name:ms'],
            ref = tags.ref,
            highway_class = hw,
            oneway = oneway,
            maxspeed_fwd_kmh = fwd_spd,
            maxspeed_bwd_kmh = bwd_spd,
            maxspeed_source = spd_src,
            lanes_total = parse_int(tags.lanes),
            lanes_fwd = parse_int(tags['lanes:forward']),
            lanes_bwd = parse_int(tags['lanes:backward']),
            turn_lanes_fwd = turn_fwd,
            turn_lanes_bwd = turn_bwd,
            hgv_prohibited = hgv_no,
            is_toll = is_toll,
            is_bridge = is_bridge,
            is_tunnel = is_tunnel,
            surface = tags.surface,
            geom = object:as_linestring(),
        })
    end

    -- 2. Closed-way Polygon POIs (malls, hospitals, R&R areas, stations)
    if object.is_closed then
        local poi = build_poi_row(tags, object:as_polygon():centroid())
        if poi then
            pois_table:insert(poi)
        end
    end
end

function osm2pgsql.process_relation(object)
    local tags = object.tags
    if tags.type == 'boundary' and tags.boundary == 'administrative' and tags.admin_level == '2' then
        local iso = tags['ISO3166-1:alpha2'] or tags['ISO3166-1']
        if iso == 'MY' or iso == 'SG' or iso == 'BN' then
            admin_table:insert({
                iso_a2 = iso,
                name = tags['name:en'] or tags.name,
                admin_level = 2,
                geom = object:as_multipolygon(),
            })
        end
    end
end
