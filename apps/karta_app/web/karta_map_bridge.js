/**
 * Karta 3D MapLibre GL JS + PMTiles / TileJSON + Dual Lighting (Obsidian Night /
 * High-Glare Tropical Daylight) + Animated Directional Route Chevrons +
 * Speed-Adaptive Label Decluttering + WebGL2 3D Vehicle Custom Layer Bridge.
 */
(function () {
  'use strict';

  let protocolRegistered = false;
  let sharedPmtilesProtocol = null;
  const instances = new Map();
  const CHEVRON_FRAMES = 8;

  function ensurePmtilesProtocol() {
    if (protocolRegistered) return;
    if (window.maplibregl && window.pmtiles) {
      sharedPmtilesProtocol = new window.pmtiles.Protocol();
      window.maplibregl.addProtocol('pmtiles', sharedPmtilesProtocol.tile);
      protocolRegistered = true;
    }
  }

  function hexToRgbNorm(hex) {
    const clean = (hex || '#5B9A94').replace('#', '');
    const num = parseInt(clean.length === 3 ? clean.split('').map(c => c + c).join('') : clean, 16);
    if (Number.isNaN(num)) return [0.357, 0.604, 0.580];
    return [((num >> 16) & 255) / 255, ((num >> 8) & 255) / 255, (num & 255) / 255];
  }

  function lerpAngleDeg(from, to, t) {
    const delta = ((to - from + 540) % 360) - 180;
    return (from + delta * t + 360) % 360;
  }

  /**
   * Resolves the best live vector tile source for Karta:
   * 1. Probes `go-pmtiles serve` TileJSON (`http://host:8081/my-sg-bn-full.json`),
   *    which serves fast `/{z}/{x}/{y}.mvt` vector tiles with exact `vector_layers`.
   * 2. Falls back to direct `pmtiles://` HTTP range-request protocol if hosting
   *    raw `.pmtiles` archives on static storage / CDN.
   */
  async function resolveVectorSource(inputUrl) {
    const cleanHttpUrl = inputUrl.replace(/^pmtiles:\/\//, '');
    const tileJsonUrl = cleanHttpUrl.endsWith('.json')
      ? cleanHttpUrl
      : cleanHttpUrl.replace(/\.pmtiles$/i, '.json');

    try {
      const resp = await fetch(tileJsonUrl, { method: 'GET', mode: 'cors' });
      if (resp.ok) {
        const meta = await resp.json();
        const layers = Array.isArray(meta.vector_layers)
          ? meta.vector_layers.map(l => l.id)
          : [];
        const schema = (layers.includes('buildings') || layers.includes('roads'))
          ? 'protomaps'
          : 'openmaptiles';
        const tileTemplate = Array.isArray(meta.tiles) && meta.tiles.length > 0
          ? meta.tiles[0]
          : tileJsonUrl.replace(/\.json$/i, '/{z}/{x}/{y}.mvt');
        const minzoom = typeof meta.minzoom === 'number' ? meta.minzoom : 0;
        const maxzoom = typeof meta.maxzoom === 'number' ? meta.maxzoom : 14;
        console.info('[KartaMapBridge] Connected to live PMTiles TileJSON:', tileJsonUrl, 'schema=' + schema, 'zoom=' + minzoom + '-' + maxzoom, 'layers=' + layers.length);
        const directSource = {
          type: 'vector',
          tiles: Array.isArray(meta.tiles) && meta.tiles.length > 0 ? meta.tiles : [tileTemplate],
          minzoom,
          maxzoom,
          scheme: meta.scheme || 'xyz',
          attribution: meta.attribution || 'OpenStreetMap contributors | Karta Navigation'
        };
        if (Array.isArray(meta.bounds) && meta.bounds.length === 4) {
          directSource.bounds = meta.bounds;
        }
        return {
          schema,
          tileTemplate,
          pmtilesArchive: null,
          sourceConfig: directSource
        };
      }
    } catch (e) {
      console.warn('[KartaMapBridge] TileJSON probe failed, falling back to pmtiles:// protocol:', e);
    }

    try {
      const archive = new window.pmtiles.PMTiles(cleanHttpUrl);
      const meta = await archive.getMetadata();
      const layers = (meta && Array.isArray(meta.vector_layers))
        ? meta.vector_layers.map(l => l.id)
        : [];
      const schema = (layers.includes('buildings') || layers.includes('roads'))
        ? 'protomaps'
        : 'openmaptiles';
      return {
        schema,
        tileTemplate: null,
        pmtilesArchive: archive,
        sourceConfig: {
          type: 'vector',
          url: 'pmtiles://' + cleanHttpUrl,
          attribution: 'OpenStreetMap contributors | Karta Navigation'
        }
      };
    } catch (e) {
      console.warn('[KartaMapBridge] PMTiles archive probe warning:', e);
      return {
        schema: 'openmaptiles',
        tileTemplate: tileJsonUrl.replace(/\.json$/i, '/{z}/{x}/{y}.mvt'),
        pmtilesArchive: null,
        sourceConfig: {
          type: 'vector',
          url: tileJsonUrl
        }
      };
    }
  }

  /**
   * Builds either Obsidian Night Mode or High-Glare Tropical Daylight Mode MapLibre Style v8.
   * Both include subtle highland/mountain relief shading echoing Karta's dual-peak logo crest,
   * 3D extruded buildings (`hide_3d` landmark fidelity), and split minor/major street labels
   * enabling speed-adaptive decluttering above 60 km/h.
   */
  function buildMapStyle(sourceConfig, schema, enable3D, lightingMode) {
    const isDay = lightingMode === 'day';
    const isProtomaps = schema === 'protomaps';
    const bldgLayer = isProtomaps ? 'buildings' : 'building';
    const roadLayer = isProtomaps ? 'roads' : 'transportation';
    const roadLabelLayer = isProtomaps ? 'roads' : 'transportation_name';
    const placeLayer = isProtomaps ? 'places' : 'place';
    const boundaryLayer = isProtomaps ? 'boundaries' : 'boundary';

    const minorFilter = isProtomaps
      ? ['in', 'kind', 'minor_road', 'other', 'path']
      : ['in', 'class', 'minor', 'service', 'track', 'path', 'street', 'residential', 'unclassified', 'living_street', 'pedestrian', 'busway', 'raceway', 'minor_construction'];
    const secFilter = isProtomaps
      ? ['in', 'kind', 'medium_road']
      : ['in', 'class', 'secondary', 'tertiary', 'secondary_link', 'tertiary_link', 'secondary_construction', 'tertiary_construction'];
    const priFilter = isProtomaps
      ? ['in', 'kind', 'major_road']
      : ['in', 'class', 'primary', 'trunk', 'primary_link', 'trunk_link', 'primary_construction', 'trunk_construction'];
    const hwyFilter = isProtomaps
      ? ['==', 'kind', 'highway']
      : ['in', 'class', 'motorway', 'motorway_link', 'motorway_construction'];
    const otherRoadFilter = isProtomaps
      ? ['!in', 'kind', 'highway', 'major_road', 'medium_road', 'minor_road', 'other', 'path', 'rail', 'ferry']
      : ['!in', 'class', 'motorway', 'motorway_link', 'motorway_construction', 'trunk', 'trunk_link', 'trunk_construction', 'primary', 'primary_link', 'primary_construction', 'secondary', 'secondary_link', 'secondary_construction', 'tertiary', 'tertiary_link', 'tertiary_construction', 'minor', 'minor_construction', 'service', 'track', 'path', 'street', 'residential', 'unclassified', 'living_street', 'pedestrian', 'busway', 'raceway', 'rail', 'transit', 'ferry'];
    const countryFilter = isProtomaps
      ? ['==', 'kind', 'country']
      : ['all', ['==', 'admin_level', 2], ['!=', 'maritime', 1]];
    const stateFilter = isProtomaps
      ? ['==', 'kind', 'region']
      : ['all', ['==', 'admin_level', 4], ['!=', 'maritime', 1]];
    const minorLabelFilter = isProtomaps
      ? ['in', 'kind', 'minor_road', 'other', 'path']
      : ['in', 'class', 'minor', 'service', 'track', 'path', 'street', 'residential', 'unclassified', 'living_street', 'pedestrian', 'tertiary'];
    const majorLabelFilter = isProtomaps
      ? ['in', 'kind', 'highway', 'major_road', 'medium_road']
      : ['in', 'class', 'motorway', 'trunk', 'primary', 'secondary'];

    const baseLayers = [
      { id: 'background', type: 'background', paint: { 'background-color': isDay ? '#F5F2EB' : '#0D0F12' } }
    ];

    if (isProtomaps) {
      baseLayers.push(
        { id: 'earth', type: 'fill', source: 'karta_basemap', 'source-layer': 'earth', paint: { 'fill-color': isDay ? '#EFECE3' : '#141820' } },
        { id: 'park', type: 'fill', source: 'karta_basemap', 'source-layer': 'landuse', filter: ['in', 'kind', 'park', 'forest', 'nature_reserve', 'garden'], paint: { 'fill-color': isDay ? '#D4E6D9' : '#12221F', 'fill-opacity': 0.88 } }
      );
    } else {
      // Subtle topographic highland / mountain relief shading echoing Karta's crest
      baseLayers.push(
        {
          id: 'landcover_highland',
          type: 'fill',
          source: 'karta_basemap',
          'source-layer': 'landcover',
          filter: ['in', 'class', 'wood', 'rock', 'sand', 'grass', 'wetland'],
          paint: {
            'fill-color': isDay
              ? ['match', ['get', 'class'], 'rock', '#DDD9CE', 'wood', '#DCE8DF', 'wetland', '#D3E5E3', '#E3EEE5']
              : ['match', ['get', 'class'], 'rock', '#1B212A', 'wood', '#111E1B', 'wetland', '#0F1C20', '#101A18'],
            'fill-opacity': isDay ? 0.84 : 0.78
          }
        },
        {
          id: 'landuse_urban',
          type: 'fill',
          source: 'karta_basemap',
          'source-layer': 'landuse',
          filter: ['in', 'class', 'residential', 'commercial', 'industrial', 'retail', 'suburb'],
          paint: { 'fill-color': isDay ? '#EFECE3' : '#141921', 'fill-opacity': isDay ? 0.72 : 0.80 }
        },
        {
          id: 'park',
          type: 'fill',
          source: 'karta_basemap',
          'source-layer': 'park',
          paint: { 'fill-color': isDay ? '#D4E6D9' : '#132622', 'fill-opacity': 0.90 }
        }
      );
    }

    baseLayers.push(
      { id: 'water', type: 'fill', source: 'karta_basemap', 'source-layer': 'water', paint: { 'fill-color': isDay ? '#C9E0EA' : '#070B12' } },
      { id: 'water_outline', type: 'line', source: 'karta_basemap', 'source-layer': 'water', paint: { 'line-color': isDay ? '#94B8C8' : '#152536', 'line-width': isDay ? 1.15 : 1.0 } },
      {
        id: 'waterway', type: 'line', source: 'karta_basemap', 'source-layer': isProtomaps ? 'water' : 'waterway',
        paint: { 'line-color': isDay ? '#AED0DF' : '#0C1622', 'line-width': ['interpolate', ['linear'], ['zoom'], 9, 0.8, 16, 4.0] }
      }
    );

    if (isDay) {
      // Bold high-glare road casings for midday tropical sunlight readability
      baseLayers.push(
        {
          id: 'roads_minor_casing', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 10, filter: minorFilter,
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#BFC5CD', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 10, 1.3, 15, 5.6, 18, 13.5] }
        }
      );
    }

    baseLayers.push(
      {
        id: 'roads_other', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 11, filter: otherRoadFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#F3F4F6' : '#232B38', 'line-width': ['interpolate', ['exponential', 1.4], ['zoom'], 11, 0.8, 16, 4.2] }
      },
      {
        id: 'roads_minor', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 10, filter: minorFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#FFFFFF' : '#2A3443', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 10, 0.7, 15, 4.0, 18, 11.0] }
      }
    );

    if (isDay) {
      baseLayers.push(
        {
          id: 'roads_secondary_casing', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 8, filter: secFilter,
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#9AA6B3', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 8, 1.8, 14, 6.8, 17, 15.8] }
        }
      );
    }

    baseLayers.push(
      {
        id: 'roads_secondary', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 8, filter: secFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#FFFDF8' : '#324052', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 8, 0.8, 14, 4.5, 17, 12.5] }
      }
    );

    if (isDay) {
      baseLayers.push(
        {
          id: 'roads_primary_casing', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 6, filter: priFilter,
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#647486', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 6, 2.2, 14, 8.6, 17, 18.6] }
        }
      );
    }

    baseLayers.push(
      {
        id: 'roads_primary', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, minzoom: 6, filter: priFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#FCEFD8' : '#42556B', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 6, 1.0, 14, 6.0, 17, 15.0] }
      },
      {
        id: 'roads_motorway_casing', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, filter: hwyFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#163834' : '#090B0E', 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 5, isDay ? 3.0 : 2.4, 12, isDay ? 8.2 : 6.6, 17, isDay ? 21.0 : 18.0] }
      },
      {
        id: 'roads_motorway', type: 'line', source: 'karta_basemap', 'source-layer': roadLayer, filter: hwyFilter,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#2F756F' : '#5B9A94', 'line-opacity': isDay ? 0.94 : 0.86, 'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 5, 1.4, 12, isDay ? 5.0 : 4.2, 17, isDay ? 15.6 : 14.0] }
      },
      {
        id: 'buildings_footprint', type: 'fill', source: 'karta_basemap', 'source-layer': bldgLayer, minzoom: 12.0,
        paint: { 'fill-color': isDay ? '#E5E1D7' : '#1A2029', 'fill-outline-color': isDay ? '#C4BFB3' : '#2B3544', 'fill-opacity': 0.90 }
      },
      {
        id: 'buildings_3d', type: 'fill-extrusion', source: 'karta_basemap', 'source-layer': bldgLayer, minzoom: 13.5,
        filter: ['!=', ['get', 'hide_3d'], true],
        layout: { visibility: enable3D ? 'visible' : 'none' },
        paint: {
          'fill-extrusion-color': isDay
            ? [
                'interpolate', ['linear'],
                ['min', ['to-number', ['coalesce', ['get', 'render_height'], ['get', 'height'], 14], 14], 460],
                0, '#E7E4DC',
                35, '#D9E0DE',
                90, '#C3D4D2',
                180, '#97BCB8',
                320, '#5B9A94',
                450, '#2F756F'
              ]
            : [
                'interpolate', ['linear'],
                ['min', ['to-number', ['coalesce', ['get', 'render_height'], ['get', 'height'], 16], 16], 460],
                0, '#1D242E',
                35, '#263240',
                90, '#314552',
                180, '#41686B',
                320, '#5B9A94',
                450, '#78C2BA'
              ],
          'fill-extrusion-height': [
            'interpolate', ['linear'], ['zoom'],
            13.5, 0,
            14.2, ['min', ['to-number', ['coalesce', ['get', 'render_height'], ['get', 'height'], 14], 14], 460]
          ],
          'fill-extrusion-base': [
            'interpolate', ['linear'], ['zoom'],
            13.5, 0,
            14.2, ['min', ['to-number', ['coalesce', ['get', 'render_min_height'], ['get', 'min_height'], 0], 0], 420]
          ],
          'fill-extrusion-opacity': isDay ? 0.88 : 0.92,
          'fill-extrusion-vertical-gradient': true
        }
      },
      {
        id: 'boundaries_state', type: 'line', source: 'karta_basemap', 'source-layer': boundaryLayer, minzoom: 5, filter: stateFilter,
        paint: { 'line-color': isDay ? '#94A0AD' : '#3E4754', 'line-dasharray': [3, 3], 'line-width': 1.1 }
      },
      {
        id: 'boundaries_country', type: 'line', source: 'karta_basemap', 'source-layer': boundaryLayer, filter: countryFilter,
        paint: { 'line-color': isDay ? '#455362' : '#8E96A0', 'line-dasharray': [4, 2], 'line-width': isDay ? 1.7 : 1.5 }
      }
    );

    if (!isProtomaps) {
      baseLayers.push(
        {
          id: 'water_name',
          type: 'symbol',
          source: 'karta_basemap',
          'source-layer': 'water_name',
          minzoom: 7,
          layout: {
            'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']],
            'text-font': ['Noto Sans Regular'],
            'text-size': ['interpolate', ['linear'], ['zoom'], 7, 10.5, 14, 13.5],
            'text-max-width': 7
          },
          paint: {
            'text-color': isDay ? '#2F6C85' : '#5E8CA3',
            'text-halo-color': isDay ? '#D9EDF5' : '#070B12',
            'text-halo-width': 1.5
          }
        },
        {
          id: 'aeroway_runway',
          type: 'line',
          source: 'karta_basemap',
          'source-layer': 'aeroway',
          minzoom: 10,
          paint: {
            'line-color': isDay ? '#C9C4B8' : '#283240',
            'line-width': ['interpolate', ['linear'], ['zoom'], 10, 2, 15, 14]
          }
        },
        {
          id: 'aerodrome_label',
          type: 'symbol',
          source: 'karta_basemap',
          'source-layer': 'aerodrome_label',
          minzoom: 9,
          layout: {
            'icon-image': 'karta-poi-airport',
            'icon-size': 0.85,
            'icon-anchor': 'bottom',
            'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name'], ['get', 'iata']],
            'text-font': ['Open Sans Semibold'],
            'text-size': ['interpolate', ['linear'], ['zoom'], 9, 10.5, 14, 13.0],
            'text-offset': [0, 0.35],
            'text-anchor': 'top',
            'text-max-width': 10
          },
          paint: {
            'text-color': isDay ? '#1C5DB0' : '#85B8F8',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': 1.9
          }
        },
        {
          id: 'building_housenumber',
          type: 'symbol',
          source: 'karta_basemap',
          'source-layer': 'housenumber',
          minzoom: 16.0,
          layout: {
            'text-field': ['get', 'housenumber'],
            'text-font': ['Noto Sans Regular'],
            'text-size': 10.0
          },
          paint: {
            'text-color': isDay ? '#4A5563' : '#7D8794',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': 1.3
          }
        },
        {
          id: 'mountain_peaks_label',
          type: 'symbol',
          source: 'karta_basemap',
          'source-layer': 'mountain_peak',
          minzoom: 9,
          layout: {
            'text-field': [
              'case',
              ['has', 'ele'],
              ['concat', '▲ ', ['coalesce', ['get', 'name:en'], ['get', 'name']], '\n', ['to-string', ['get', 'ele']], 'm'],
              ['concat', '▲ ', ['coalesce', ['get', 'name:en'], ['get', 'name']]]
            ],
            'text-font': ['Noto Sans Regular'],
            'text-size': ['interpolate', ['linear'], ['zoom'], 9, 9.5, 13, 11.5],
            'text-max-width': 8
          },
          paint: {
            'text-color': isDay ? '#485958' : '#74C4BC',
            'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
            'text-halo-width': 1.7
          }
        }
      );
    }

    const poiClassExpr = isProtomaps ? ['get', 'kind'] : ['coalesce', ['get', 'subclass'], ['get', 'class']];
    const poiIconMatch = [
      'match',
      poiClassExpr,
      ['restaurant', 'fast_food', 'food_court', 'ice_cream', 'bakery', 'bar', 'pub', 'biergarten', 'food'], 'karta-poi-food',
      ['cafe', 'coffee', 'tea'], 'karta-poi-cafe',
      ['mall', 'supermarket', 'department_store', 'convenience', 'shop', 'clothes', 'marketplace', 'shopping', 'retail'], 'karta-poi-shop',
      ['fuel', 'gas_station', 'petrol'], 'karta-poi-fuel',
      ['charging_station', 'ev_charging', 'ev'], 'karta-poi-ev',
      ['hospital', 'clinic', 'doctors', 'dentist', 'pharmacy', 'healthcare'], 'karta-poi-health',
      ['station', 'railway', 'subway', 'bus_station', 'bus_stop', 'ferry_terminal', 'transit', 'tram_stop', 'monorail'], 'karta-poi-transit',
      ['airport', 'aerodrome', 'heliport'], 'karta-poi-airport',
      ['park', 'garden', 'nature_reserve', 'playground', 'beach', 'zoo', 'stadium', 'pitch', 'golf_course'], 'karta-poi-park',
      ['attraction', 'museum', 'monument', 'memorial', 'castle', 'viewpoint', 'tower', 'artwork', 'theme_park', 'gallery', 'landmark', 'tourism'], 'karta-poi-landmark',
      ['place_of_worship', 'mosque', 'temple', 'church', 'shrine'], 'karta-poi-worship',
      ['hotel', 'motel', 'hostel', 'guest_house', 'resort', 'lodging'], 'karta-poi-hotel',
      ['parking', 'bicycle_parking'], 'karta-poi-parking',
      ['bank', 'atm', 'bureau_de_change'], 'karta-poi-bank',
      ['school', 'university', 'college', 'library', 'kindergarten', 'education'], 'karta-poi-school',
      'karta-poi-pin'
    ];

    const cleanRefExpr = [
      'let', 'raw', ['upcase', ['to-string', ['coalesce', ['get', 'ref'], '']]],
      [
        'let', 'sep', ['index-of', ';', ['var', 'raw']],
        ['case', ['>', ['var', 'sep'], 0], ['slice', ['var', 'raw'], 0, ['var', 'sep']], ['var', 'raw']]
      ]
    ];
    const sgExpresswayRefs = ['CTE', 'PIE', 'AYE', 'ECP', 'SLE', 'BKE', 'KJE', 'TPE', 'KPE', 'MCE', 'NSC'];
    const myNumericFirstChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const shieldSizeSuffixExpr = [
      'case',
      ['<=', ['length', cleanRefExpr], 2], 'sm',
      ['==', ['length', cleanRefExpr], 3], 'md',
      ['==', ['length', cleanRefExpr], 4], 'lg',
      'xl'
    ];
    const shieldPrefixExpr = [
      'case',
      ['in', cleanRefExpr, ['literal', sgExpresswayRefs]], 'karta-shield-sg-exp-',
      ['==', ['slice', cleanRefExpr, 0, 2], 'AH'], 'karta-shield-asean-',
      ['==', ['slice', cleanRefExpr, 0, 1], 'E'], 'karta-shield-my-exp-',
      [
        'any',
        ['in', ['slice', cleanRefExpr, 0, 1], ['literal', myNumericFirstChars]],
        ['==', ['slice', cleanRefExpr, 0, 2], 'FT']
      ], 'karta-shield-my-fed-',
      'karta-shield-my-state-'
    ];
    const shieldTextColorExpr = [
      'case',
      [
        'any',
        ['in', cleanRefExpr, ['literal', sgExpresswayRefs]],
        ['==', ['slice', cleanRefExpr, 0, 2], 'AH']
      ], '#FFFFFF',
      '#11161C'
    ];

    baseLayers.push(
      {
        id: 'roads_label_minor',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': roadLabelLayer,
        minzoom: 12.2,
        filter: minorLabelFilter,
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 260,
          'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name'], ['get', 'ref']],
          'text-font': ['Noto Sans Regular'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 12.2, 10.0, 16, 12.2]
        },
        paint: {
          'text-color': isDay ? '#4A5563' : '#9AA6B4',
          'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
          'text-halo-width': isDay ? 1.8 : 1.5,
          'text-opacity': 0.94,
          'text-opacity-transition': { duration: 380 }
        }
      },
      {
        id: 'roads_label_major',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': roadLabelLayer,
        minzoom: 9,
        filter: majorLabelFilter,
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 300,
          'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name'], ['get', 'ref']],
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 9, 10.5, 16, 13.5]
        },
        paint: {
          'text-color': isDay ? '#11161C' : '#DCE4EC',
          'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
          'text-halo-width': isDay ? 2.0 : 1.8
        }
      },
      {
        id: 'roads_shield_expressway',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': roadLabelLayer,
        minzoom: 6.5,
        filter: ['all', hwyFilter, ['has', 'ref']],
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 280,
          'icon-image': ['concat', shieldPrefixExpr, shieldSizeSuffixExpr],
          'icon-size': ['interpolate', ['linear'], ['zoom'], 6.5, 0.86, 12, 0.96, 15, 1.04],
          'icon-rotation-alignment': 'viewport',
          'icon-pitch-alignment': 'viewport',
          'text-field': cleanRefExpr,
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 6.5, 9.4, 12, 10.4, 15, 11.2],
          'text-offset': [0, 0.04],
          'text-rotation-alignment': 'viewport',
          'text-pitch-alignment': 'viewport'
        },
        paint: {
          'text-color': shieldTextColorExpr
        }
      },
      {
        id: 'roads_shield_federal',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': roadLabelLayer,
        minzoom: 8.5,
        filter: ['all', ['any', priFilter, secFilter], ['has', 'ref']],
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 340,
          'icon-image': ['concat', shieldPrefixExpr, shieldSizeSuffixExpr],
          'icon-size': ['interpolate', ['linear'], ['zoom'], 8.5, 0.84, 13, 0.94, 16, 1.0],
          'icon-rotation-alignment': 'viewport',
          'icon-pitch-alignment': 'viewport',
          'text-field': cleanRefExpr,
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 8.5, 9.0, 13, 10.0, 16, 10.6],
          'text-offset': [0, 0.04],
          'text-rotation-alignment': 'viewport',
          'text-pitch-alignment': 'viewport'
        },
        paint: {
          'text-color': shieldTextColorExpr
        }
      },
      {
        id: 'poi_landmarks',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': isProtomaps ? 'pois' : 'poi',
        minzoom: 12.2,
        layout: {
          'icon-image': poiIconMatch,
          'icon-size': ['interpolate', ['linear'], ['zoom'], 12.2, 0.58, 15.5, 0.78, 18, 0.92],
          'icon-anchor': 'bottom',
          'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']],
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 12.2, 10.0, 16, 12.0],
          'text-offset': [0, 0.25],
          'text-anchor': 'top',
          'text-max-width': 9,
          'text-optional': true
        },
        paint: {
          'text-color': isDay ? '#22303C' : '#DCE4EC',
          'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
          'text-halo-width': 1.8,
          'icon-opacity': 0.96,
          'text-opacity': 0.95,
          'icon-opacity-transition': { duration: 320 },
          'text-opacity-transition': { duration: 320 }
        }
      },
      {
        id: 'place_suburb_neighbourhood',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': placeLayer,
        minzoom: 10.5,
        filter: isProtomaps
          ? ['in', 'kind', 'neighbourhood', 'locality', 'village', 'hamlet']
          : ['in', 'class', 'suburb', 'neighbourhood', 'quarter', 'village', 'hamlet', 'locality', 'isolated_dwelling'],
        layout: {
          'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']],
          'text-font': ['Noto Sans Regular'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 10.5, 10.5, 15, 13.0],
          'text-max-width': 8
        },
        paint: {
          'text-color': isDay ? '#4A5563' : '#A4B0BD',
          'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
          'text-halo-width': 1.9
        }
      },
      {
        id: 'places_label',
        type: 'symbol',
        source: 'karta_basemap',
        'source-layer': placeLayer,
        filter: isProtomaps
          ? ['in', 'kind', 'country', 'region', 'city', 'town']
          : ['in', 'class', 'country', 'state', 'province', 'city', 'town'],
        layout: {
          'text-field': ['coalesce', ['get', 'name:en'], ['get', 'name']],
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 5, 11.5, 12, 16.0],
          'text-max-width': 8
        },
        paint: {
          'text-color': isDay ? '#11161C' : '#F4F6F8',
          'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
          'text-halo-width': isDay ? 2.1 : 1.8
        }
      }
    );

    return {
      version: 8,
      name: isDay ? 'Karta Tropical Daylight 3D Automotive v1' : 'Karta Dark 3D Automotive v1',
      light: {
        anchor: 'viewport',
        color: isDay ? '#FFFDF5' : '#E8F4F2',
        intensity: isDay ? 0.56 : 0.58,
        position: isDay ? [1.25, 195, 52] : [1.4, 215, 38]
      },
      sources: {
        karta_basemap: sourceConfig
      },
      glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
      layers: baseLayers
    };
  }

  /**
   * Generates 8 horizontally shifted directional chevron sprites (`karta-chevron-0`..`7`)
   * so MapLibre's `symbol-placement: 'line'` renders silky, forward-flowing luminous
   * directional chevrons along any active route with zero GeoJSON reallocation.
   */
  function registerChevronSprites(map, isDay) {
    const w = 64;
    const h = 28;
    for (let f = 0; f < CHEVRON_FRAMES; f++) {
      const id = 'karta-chevron-' + f;
      if (map.hasImage(id)) {
        map.removeImage(id);
      }
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) continue;

      const phaseX = 12 + (f / CHEVRON_FRAMES) * 40;
      const cy = h / 2;

      ctx.clearRect(0, 0, w, h);
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      // Subtle trailing shadow chevron for high-speed motion feel
      ctx.strokeStyle = isDay ? 'rgba(255, 255, 255, 0.35)' : 'rgba(232, 252, 249, 0.32)';
      ctx.lineWidth = 3.2;
      ctx.beginPath();
      ctx.moveTo(phaseX - 10, cy - 5.5);
      ctx.lineTo(phaseX - 4, cy);
      ctx.lineTo(phaseX - 10, cy + 5.5);
      ctx.stroke();

      // Primary crisp luminous chevron
      ctx.strokeStyle = isDay ? '#FFFFFF' : '#F4FFFD';
      ctx.shadowColor = isDay ? 'rgba(16, 43, 40, 0.65)' : 'rgba(116, 207, 198, 0.9)';
      ctx.shadowBlur = 4;
      ctx.lineWidth = 4.0;
      ctx.beginPath();
      ctx.moveTo(phaseX - 3.5, cy - 6.5);
      ctx.lineTo(phaseX + 4.5, cy);
      ctx.lineTo(phaseX - 3.5, cy + 6.5);
      ctx.stroke();

      const imgData = ctx.getImageData(0, 0, w, h);
      map.addImage(id, imgData, { pixelRatio: 2 });
    }
  }

  /**
   * Generates crisp 2x HTML5 Canvas Google Maps-style categorized POI/landmark pin sprites
   * and authentic official Malaysian JKR/LLM pointed-top-and-bottom hexagonal route shields,
   * Singapore LTA expressway shields, and ASEAN Highway shields.
   */
  function registerGoogleStyleSprites(map, isDay) {
    function traceRoundedPolygon(ctx, pts, radius) {
      const n = pts.length;
      ctx.beginPath();
      for (let i = 0; i < n; i++) {
        const prev = pts[(i - 1 + n) % n];
        const curr = pts[i];
        const next = pts[(i + 1) % n];
        const v1x = prev[0] - curr[0], v1y = prev[1] - curr[1];
        const v2x = next[0] - curr[0], v2y = next[1] - curr[1];
        const len1 = Math.hypot(v1x, v1y) || 1;
        const len2 = Math.hypot(v2x, v2y) || 1;
        const r = Math.min(radius, len1 * 0.34, len2 * 0.34);
        const sx = curr[0] + (v1x / len1) * r;
        const sy = curr[1] + (v1y / len1) * r;
        const ex = curr[0] + (v2x / len2) * r;
        const ey = curr[1] + (v2y / len2) * r;
        if (i === 0) ctx.moveTo(sx, sy);
        else ctx.lineTo(sx, sy);
        ctx.quadraticCurveTo(curr[0], curr[1], ex, ey);
      }
      ctx.closePath();
    }

    function jkrHexVertices(cx, cy, halfW, halfH, roofDrop) {
      return [
        [cx, cy - halfH],
        [cx + halfW, cy - halfH + roofDrop],
        [cx + halfW, cy + halfH - roofDrop],
        [cx, cy + halfH],
        [cx - halfW, cy + halfH - roofDrop],
        [cx - halfW, cy - halfH + roofDrop]
      ];
    }

    function addMalaysianJkrHexShield(id, w, h, opts) {
      if (map.hasImage(id)) map.removeImage(id);
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.clearRect(0, 0, w, h);

      const cx = w / 2;
      const cy = h / 2;
      const padX = opts.outerHaloWidth > 0 ? 5.5 : 4.0;
      const padY = opts.outerHaloWidth > 0 ? 4.5 : 3.5;
      const halfW = cx - padX;
      const halfH = cy - padY;
      const roofDrop = Math.round(halfH * 0.42);
      const outerPts = jkrHexVertices(cx, cy, halfW, halfH, roofDrop);

      // Subtle ground shadow so yellow JKR shields stay crisp on bright Day roads
      ctx.save();
      ctx.shadowColor = isDay ? 'rgba(17, 22, 28, 0.34)' : 'rgba(0, 0, 0, 0.72)';
      ctx.shadowBlur = 4.5;
      ctx.shadowOffsetY = 1.5;
      traceRoundedPolygon(ctx, outerPts, 3.6);
      ctx.fillStyle = opts.fill;
      ctx.fill();
      ctx.restore();

      // Optional subtle outer halo (LLM Emerald Green on Expressways, subtle JKR Blue/Slate edge on Federal/State)
      if (opts.outerStroke) {
        traceRoundedPolygon(ctx, outerPts, 3.6);
        ctx.lineWidth = opts.outerHaloWidth || 2.0;
        ctx.strokeStyle = opts.outerStroke;
        ctx.stroke();
      }

      // Authentic Malaysian JKR yellow outer margin -> bold black inner hexagonal border
      const inset = opts.innerInset || 4.0;
      const innerHalfW = Math.max(8, halfW - inset);
      const innerHalfH = Math.max(8, halfH - inset);
      const innerRoofDrop = Math.round(innerHalfH * 0.42);
      const innerPts = jkrHexVertices(cx, cy, innerHalfW, innerHalfH, innerRoofDrop);
      traceRoundedPolygon(ctx, innerPts, 2.4);
      ctx.lineWidth = opts.innerBorderWidth || 3.0;
      ctx.strokeStyle = opts.innerBorder || '#11161C';
      ctx.stroke();

      map.addImage(id, ctx.getImageData(0, 0, w, h), { pixelRatio: 2 });
    }

    function addRoundedRectShield(id, w, h, fill, innerBorder, outerStroke) {
      if (map.hasImage(id)) map.removeImage(id);
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.clearRect(0, 0, w, h);

      function traceRRect(x, y, rw, rh, r) {
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + rw - r, y);
        ctx.quadraticCurveTo(x + rw, y, x + rw, y + r);
        ctx.lineTo(x + rw, y + rh - r);
        ctx.quadraticCurveTo(x + rw, y + rh, x + rw - r, y + rh);
        ctx.lineTo(x + r, y + rh);
        ctx.quadraticCurveTo(x, y + rh, x, y + rh - r);
        ctx.lineTo(x, y + r);
        ctx.quadraticCurveTo(x, y, x + r, y);
        ctx.closePath();
      }

      ctx.save();
      ctx.shadowColor = isDay ? 'rgba(17, 22, 28, 0.30)' : 'rgba(0, 0, 0, 0.65)';
      ctx.shadowBlur = 4;
      ctx.shadowOffsetY = 1.5;
      traceRRect(3, 4, w - 6, h - 8, 9);
      ctx.fillStyle = fill;
      ctx.fill();
      ctx.restore();

      if (outerStroke) {
        traceRRect(3, 4, w - 6, h - 8, 9);
        ctx.lineWidth = 1.6;
        ctx.strokeStyle = outerStroke;
        ctx.stroke();
      }

      traceRRect(6.5, 7.5, w - 13, h - 15, 6);
      ctx.lineWidth = 2.4;
      ctx.strokeStyle = innerBorder;
      ctx.stroke();

      map.addImage(id, ctx.getImageData(0, 0, w, h), { pixelRatio: 2 });
    }

    // Pre-sized 2x authentic shields (sm: 1-2 chars, md: 3 chars, lg: 4 chars, xl: 5+ chars)
    // Zero stretching distortion on angled Malaysian JKR hexagonal borders.
    const hexSizes = [
      { key: 'sm', w: 62, h: 56 },
      { key: 'md', w: 76, h: 58 },
      { key: 'lg', w: 92, h: 60 },
      { key: 'xl', w: 110, h: 60 }
    ];
    const rectSizes = [
      { key: 'sm', w: 58, h: 42 },
      { key: 'md', w: 74, h: 44 },
      { key: 'lg', w: 88, h: 44 },
      { key: 'xl', w: 106, h: 46 }
    ];

    for (const sz of hexSizes) {
      // Malaysian Expressway (LLM / JKR): Yellow hexagon + bold black inner border + LLM Emerald Green outer rim
      addMalaysianJkrHexShield('karta-shield-my-exp-' + sz.key, sz.w, sz.h, {
        fill: '#FFD100',
        innerBorder: '#11161C',
        innerBorderWidth: 3.1,
        innerInset: 4.4,
        outerStroke: '#006B44',
        outerHaloWidth: 2.8
      });
      // Malaysian Federal Route (JKR): Iconic JKR Yellow hexagon + bold black inner border + crisp JKR Blue edge
      addMalaysianJkrHexShield('karta-shield-my-fed-' + sz.key, sz.w, sz.h, {
        fill: '#FFD100',
        innerBorder: '#11161C',
        innerBorderWidth: 3.0,
        innerInset: 3.8,
        outerStroke: '#0B3D6B',
        outerHaloWidth: 1.6
      });
      // Malaysian State Route (JKR): Authentic JKR Yellow hexagon + crisp black inner border (e.g. P15, B15, J32)
      addMalaysianJkrHexShield('karta-shield-my-state-' + sz.key, sz.w - 4, sz.h - 4, {
        fill: '#FFE14D',
        innerBorder: '#11161C',
        innerBorderWidth: 2.7,
        innerInset: 3.5,
        outerStroke: '#222A33',
        outerHaloWidth: 1.3
      });
    }

    for (const sz of rectSizes) {
      // Singapore LTA Expressway (CTE, PIE, AYE, ECP, SLE, etc.): Emerald green rounded shield + white inner border
      addRoundedRectShield('karta-shield-sg-exp-' + sz.key, sz.w, sz.h, '#006B44', '#FFFFFF', '#083B27');
      // ASEAN Highway (AH2, AH18, AH150): Royal blue shield + white inner border
      addRoundedRectShield('karta-shield-asean-' + sz.key, sz.w, sz.h, '#003DA5', '#FFFFFF', '#06204F');
    }

    // Legacy compatibility aliases
    addMalaysianJkrHexShield('karta-shield-expressway', 76, 58, {
      fill: '#FFD100',
      innerBorder: '#11161C',
      innerBorderWidth: 3.1,
      innerInset: 4.4,
      outerStroke: '#006B44',
      outerHaloWidth: 2.8
    });
    addMalaysianJkrHexShield('karta-shield-federal', 76, 58, {
      fill: '#FFD100',
      innerBorder: '#11161C',
      innerBorderWidth: 3.0,
      innerInset: 3.8,
      outerStroke: '#0B3D6B',
      outerHaloWidth: 1.6
    });

    const poiSpecs = [
      { id: 'karta-poi-food',     bg: '#EA580C', glyph: 'food' },
      { id: 'karta-poi-cafe',     bg: '#B45309', glyph: 'cafe' },
      { id: 'karta-poi-shop',     bg: '#2563EB', glyph: 'shop' },
      { id: 'karta-poi-fuel',     bg: '#0D9488', glyph: 'fuel' },
      { id: 'karta-poi-ev',       bg: '#16A34A', glyph: 'ev' },
      { id: 'karta-poi-health',   bg: '#DC2626', glyph: 'health' },
      { id: 'karta-poi-transit',  bg: '#0284C7', glyph: 'transit' },
      { id: 'karta-poi-airport',  bg: '#1D4ED8', glyph: 'airport' },
      { id: 'karta-poi-park',     bg: '#15803D', glyph: 'park' },
      { id: 'karta-poi-landmark', bg: '#7C3AED', glyph: 'landmark' },
      { id: 'karta-poi-worship',  bg: '#0F766E', glyph: 'worship' },
      { id: 'karta-poi-hotel',    bg: '#DB2777', glyph: 'hotel' },
      { id: 'karta-poi-parking',  bg: '#3B82F6', glyph: 'parking' },
      { id: 'karta-poi-bank',     bg: '#475569', glyph: 'bank' },
      { id: 'karta-poi-school',   bg: '#6366F1', glyph: 'school' },
      { id: 'karta-poi-pin',      bg: '#5B9A94', glyph: 'pin' }
    ];

    for (const spec of poiSpecs) {
      if (map.hasImage(spec.id)) map.removeImage(spec.id);
      const w = 44, h = 52;
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) continue;
      ctx.clearRect(0, 0, w, h);

      const cx = w / 2, cy = 20, rad = 16;
      // Subtle shadow
      ctx.save();
      ctx.shadowColor = isDay ? 'rgba(17, 22, 28, 0.30)' : 'rgba(0, 0, 0, 0.65)';
      ctx.shadowBlur = 5;
      ctx.shadowOffsetY = 2;
      // Teardrop pin silhouette
      ctx.beginPath();
      ctx.arc(cx, cy, rad, Math.PI * 0.22, Math.PI * 0.78, true);
      ctx.lineTo(cx, h - 4);
      ctx.closePath();
      ctx.fillStyle = spec.bg;
      ctx.fill();
      ctx.restore();

      // Crisp white border
      ctx.beginPath();
      ctx.arc(cx, cy, rad, Math.PI * 0.22, Math.PI * 0.78, true);
      ctx.lineTo(cx, h - 4);
      ctx.closePath();
      ctx.lineWidth = 2.6;
      ctx.strokeStyle = '#FFFFFF';
      ctx.stroke();

      // Crisp inner white icon glyph
      ctx.fillStyle = '#FFFFFF';
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2.2;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      switch (spec.glyph) {
        case 'health': // Medical cross
          ctx.fillRect(cx - 2.5, cy - 7.5, 5, 15);
          ctx.fillRect(cx - 7.5, cy - 2.5, 15, 5);
          break;
        case 'food': // Fork & knife simplified
          ctx.beginPath();
          ctx.moveTo(cx - 4, cy - 7); ctx.lineTo(cx - 4, cy + 7);
          ctx.moveTo(cx - 6.5, cy - 7); ctx.lineTo(cx - 6.5, cy - 1);
          ctx.moveTo(cx - 1.5, cy - 7); ctx.lineTo(cx - 1.5, cy - 1);
          ctx.moveTo(cx + 4.5, cy - 7); ctx.lineTo(cx + 4.5, cy + 7);
          ctx.stroke();
          break;
        case 'cafe': // Cup
          ctx.strokeRect(cx - 5.5, cy - 4, 9, 8.5);
          ctx.beginPath();
          ctx.arc(cx + 4.5, cy, 3, -Math.PI / 2, Math.PI / 2);
          ctx.stroke();
          break;
        case 'shop': // Shopping bag
          ctx.strokeRect(cx - 6, cy - 3, 12, 10);
          ctx.beginPath();
          ctx.arc(cx, cy - 3, 3.5, Math.PI, 0);
          ctx.stroke();
          break;
        case 'fuel': // Fuel pump
          ctx.fillRect(cx - 5.5, cy - 6, 8, 12.5);
          ctx.fillStyle = spec.bg;
          ctx.fillRect(cx - 3.5, cy - 4, 4, 3.5);
          ctx.fillStyle = '#FFFFFF';
          ctx.beginPath();
          ctx.moveTo(cx + 3.5, cy - 3); ctx.lineTo(cx + 6.5, cy); ctx.lineTo(cx + 6.5, cy + 5);
          ctx.stroke();
          break;
        case 'ev': // Lightning bolt
          ctx.beginPath();
          ctx.moveTo(cx + 1.5, cy - 8);
          ctx.lineTo(cx - 5, cy + 0.5);
          ctx.lineTo(cx + 0.5, cy + 0.5);
          ctx.lineTo(cx - 1.5, cy + 8);
          ctx.lineTo(cx + 5, cy - 0.5);
          ctx.lineTo(cx - 0.5, cy - 0.5);
          ctx.closePath();
          ctx.fill();
          break;
        case 'transit': // Train/bus front
          ctx.strokeRect(cx - 5.5, cy - 6.5, 11, 11);
          ctx.fillRect(cx - 3.5, cy - 4.5, 7, 4);
          ctx.beginPath();
          ctx.arc(cx - 3, cy + 2, 1.3, 0, Math.PI * 2);
          ctx.arc(cx + 3, cy + 2, 1.3, 0, Math.PI * 2);
          ctx.fill();
          break;
        case 'airport': // Airplane
          ctx.beginPath();
          ctx.moveTo(cx, cy - 8); ctx.lineTo(cx, cy + 7.5);
          ctx.moveTo(cx - 7.5, cy - 1); ctx.lineTo(cx + 7.5, cy - 1);
          ctx.moveTo(cx - 3.5, cy + 5.5); ctx.lineTo(cx + 3.5, cy + 5.5);
          ctx.stroke();
          break;
        case 'park': // Tree
          ctx.beginPath();
          ctx.moveTo(cx, cy - 8);
          ctx.lineTo(cx - 6.5, cy + 2.5);
          ctx.lineTo(cx + 6.5, cy + 2.5);
          ctx.closePath();
          ctx.fill();
          ctx.fillRect(cx - 1.5, cy + 2.5, 3, 5);
          break;
        case 'landmark': // Star
          ctx.beginPath();
          for (let i = 0; i < 5; i++) {
            const a1 = -Math.PI / 2 + (i * 2 * Math.PI) / 5;
            const a2 = a1 + Math.PI / 5;
            const x1 = cx + Math.cos(a1) * 7.5, y1 = cy + Math.sin(a1) * 7.5;
            const x2 = cx + Math.cos(a2) * 3.2, y2 = cy + Math.sin(a2) * 3.2;
            if (i === 0) ctx.moveTo(x1, y1); else ctx.lineTo(x1, y1);
            ctx.lineTo(x2, y2);
          }
          ctx.closePath();
          ctx.fill();
          break;
        case 'worship': // Crescent / dome
          ctx.beginPath();
          ctx.arc(cx, cy - 0.5, 6.2, Math.PI, 0);
          ctx.lineTo(cx + 6.2, cy + 6);
          ctx.lineTo(cx - 6.2, cy + 6);
          ctx.closePath();
          ctx.fill();
          ctx.beginPath();
          ctx.moveTo(cx, cy - 8.5); ctx.lineTo(cx, cy - 5.5);
          ctx.stroke();
          break;
        case 'hotel': // Bed
          ctx.beginPath();
          ctx.moveTo(cx - 7, cy + 5); ctx.lineTo(cx - 7, cy - 4);
          ctx.moveTo(cx - 7, cy + 2); ctx.lineTo(cx + 7, cy + 2);
          ctx.moveTo(cx + 7, cy + 5); ctx.lineTo(cx + 7, cy - 1);
          ctx.stroke();
          ctx.fillRect(cx - 4.5, cy - 2.5, 4, 3);
          break;
        case 'parking': // P letter
          ctx.font = 'bold 15px sans-serif';
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText('P', cx, cy + 0.5);
          break;
        case 'bank': // Columns / $
          ctx.fillRect(cx - 7, cy + 4.5, 14, 2.2);
          ctx.beginPath();
          ctx.moveTo(cx - 7, cy - 2.5); ctx.lineTo(cx, cy - 7.5); ctx.lineTo(cx + 7, cy - 2.5);
          ctx.closePath(); ctx.fill();
          ctx.fillRect(cx - 5, cy - 2, 2.2, 6);
          ctx.fillRect(cx - 1.1, cy - 2, 2.2, 6);
          ctx.fillRect(cx + 2.8, cy - 2, 2.2, 6);
          break;
        case 'school': // Graduation cap
          ctx.beginPath();
          ctx.moveTo(cx, cy - 6.5); ctx.lineTo(cx + 8, cy - 2); ctx.lineTo(cx, cy + 2.5); ctx.lineTo(cx - 8, cy - 2);
          ctx.closePath(); ctx.fill();
          ctx.fillRect(cx - 4.5, cy + 2, 9, 3.5);
          break;
        default: // Pin dot
          ctx.beginPath();
          ctx.arc(cx, cy, 5.2, 0, Math.PI * 2);
          ctx.fill();
          break;
      }

      map.addImage(spec.id, ctx.getImageData(0, 0, w, h), { pixelRatio: 2 });
    }
  }

  function poiSpriteIdForCategory(cat) {
    const c = String(cat || '').toLowerCase();
    if (c.includes('food') || c.includes('restaur') || c.includes('dining') || c.includes('fast')) return 'karta-poi-food';
    if (c.includes('cafe') || c.includes('coffee')) return 'karta-poi-cafe';
    if (c.includes('shop') || c.includes('mall') || c.includes('retail') || c.includes('market')) return 'karta-poi-shop';
    if (c.includes('ev') || c.includes('charg')) return 'karta-poi-ev';
    if (c.includes('fuel') || c.includes('petrol') || c.includes('gas') || c.includes('r&r') || c.includes('rest')) return 'karta-poi-fuel';
    if (c.includes('hosp') || c.includes('clinic') || c.includes('health') || c.includes('pharm')) return 'karta-poi-health';
    if (c.includes('transit') || c.includes('station') || c.includes('mrt') || c.includes('lrt') || c.includes('bus') || c.includes('rail')) return 'karta-poi-transit';
    if (c.includes('airp') || c.includes('klia') || c.includes('changi')) return 'karta-poi-airport';
    if (c.includes('park') || c.includes('garden') || c.includes('nature') || c.includes('beach')) return 'karta-poi-park';
    if (c.includes('mosque') || c.includes('temple') || c.includes('church') || c.includes('worship')) return 'karta-poi-worship';
    if (c.includes('hotel') || c.includes('resort') || c.includes('lodg')) return 'karta-poi-hotel';
    if (c.includes('park')) return 'karta-poi-parking';
    if (c.includes('bank') || c.includes('atm')) return 'karta-poi-bank';
    if (c.includes('school') || c.includes('univ') || c.includes('college') || c.includes('edu')) return 'karta-poi-school';
    if (c.includes('land') || c.includes('tower') || c.includes('attract') || c.includes('museum') || c.includes('tourism')) return 'karta-poi-landmark';
    return 'karta-poi-pin';
  }

  function ensureChevronAnimator(state) {
    if (state.chevronTimer) return;
    state.chevronTimer = window.setInterval(() => {
      if (!state.map || !state.styleLoaded || !state.hasActiveRoute) return;
      if (!state.map.getLayer('karta-route-primary-chevrons')) return;
      state.chevronFrame = (state.chevronFrame + 1) % CHEVRON_FRAMES;
      try {
        state.map.setLayoutProperty(
          'karta-route-primary-chevrons',
          'icon-image',
          'karta-chevron-' + state.chevronFrame
        );
      } catch (_) {
        // Ignore transient style swap window
      }
    }, 105);
  }

  /**
   * Generates crisp 2D navigation arrow / puck sprite (`karta-nav-puck-2d`)
   * replacing the old 3D WebGL mesh. Never mutates WebGL state and stays razor-sharp
   * in both Obsidian Night and Tropical Daylight modes.
   */
  function register2DNavArrowSprite(map, vehicleStyle, isDay) {
    const id = 'karta-nav-puck-2d';
    if (map.hasImage(id)) map.removeImage(id);

    const size = 96;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const cx = size / 2;
    const cy = size / 2;
    const accent = (vehicleStyle && vehicleStyle.accentHex) || '#5B9A94';
    const avatar = (vehicleStyle && vehicleStyle.avatar) || 'karta_pin_3d';

    ctx.clearRect(0, 0, size, size);

    // Subtle soft ground shadow
    ctx.save();
    ctx.shadowColor = isDay ? 'rgba(17, 22, 28, 0.32)' : 'rgba(0, 0, 0, 0.65)';
    ctx.shadowBlur = 12;
    ctx.shadowOffsetY = 3;

    // Outer white navigation puck circle
    ctx.beginPath();
    ctx.arc(cx, cy, 32, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
    ctx.restore();

    // Subtle outer border ring
    ctx.beginPath();
    ctx.arc(cx, cy, 32, 0, Math.PI * 2);
    ctx.lineWidth = 3.5;
    ctx.strokeStyle = isDay ? 'rgba(17, 22, 28, 0.14)' : 'rgba(255, 255, 255, 0.28)';
    ctx.stroke();

    // Inner colored directional arrow pointing North (0 deg; rotated via icon-rotate)
    ctx.save();
    ctx.fillStyle = avatar === 'stealth_sedan' ? '#1A73E8' : accent;
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 2.5;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    if (avatar === 'gt_coupe') {
      // Sharp sport chevron
      ctx.moveTo(cx, cy - 22);
      ctx.lineTo(cx + 18, cy + 16);
      ctx.lineTo(cx, cy + 7);
      ctx.lineTo(cx - 18, cy + 16);
    } else if (avatar === 'touring_moto') {
      // Slim agile dart
      ctx.moveTo(cx, cy - 23);
      ctx.lineTo(cx + 13, cy + 17);
      ctx.lineTo(cx, cy + 10);
      ctx.lineTo(cx - 13, cy + 17);
    } else {
      // Clean Google Maps / Waze-style 2D navigation chevron arrow
      ctx.moveTo(cx, cy - 21);
      ctx.lineTo(cx + 17, cy + 15);
      ctx.lineTo(cx, cy + 8.5);
      ctx.lineTo(cx - 17, cy + 15);
    }
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    map.addImage(id, ctx.getImageData(0, 0, size, size), { pixelRatio: 2 });
  }

  /**
   * Generates crisp 2D white-with-teal/blue-border triangular turn arrowheads
   * rendered at the tip of every on-map road-snapped turn direction arrow.
   */
  function registerTurnArrowheadSprites(map, isDay) {
    const specs = [
      { id: 'karta-turn-arrowhead', stroke: isDay ? '#0B5FA5' : '#0E7490', scale: 1.0 },
      { id: 'karta-turn-arrowhead-active', stroke: isDay ? '#0369A1' : '#14B8A6', scale: 1.12 }
    ];
    for (const sp of specs) {
      if (map.hasImage(sp.id)) map.removeImage(sp.id);
      const w = 52;
      const h = 52;
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) continue;

      const cx = w / 2;
      const cy = h / 2;
      ctx.clearRect(0, 0, w, h);
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(sp.scale, sp.scale);
      ctx.shadowColor = 'rgba(0, 0, 0, 0.35)';
      ctx.shadowBlur = 4;
      ctx.beginPath();
      ctx.moveTo(0, -16);
      ctx.lineTo(15, 11);
      ctx.lineTo(0, 6);
      ctx.lineTo(-15, 11);
      ctx.closePath();
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      ctx.lineWidth = 4.2;
      ctx.lineJoin = 'round';
      ctx.strokeStyle = sp.stroke;
      ctx.stroke();
      ctx.restore();

      map.addImage(sp.id, ctx.getImageData(0, 0, w, h), { pixelRatio: 2 });
    }
  }

  function update2DNavArrowSource(state, lat, lon, bearing, visible) {
    const map = state.map;
    if (!map) return;
    const arrowSrc = map.getSource('karta-nav-arrow-2d');
    if (arrowSrc) {
      arrowSrc.setData({
        type: 'FeatureCollection',
        features: visible
          ? [{
              type: 'Feature',
              properties: { bearing: bearing || 0 },
              geometry: { type: 'Point', coordinates: [lon, lat] }
            }]
          : []
      });
    }
    const haloSrc = map.getSource('karta-vehicle-halo');
    if (haloSrc) {
      haloSrc.setData({
        type: 'FeatureCollection',
        features: (visible && state.vehicleStyle.showHaloRing)
          ? [{ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [lon, lat] } }]
          : []
      });
    }
  }

  function startNavArrowAnimation(state) {
    if (state.navArrowRaf) return;
    const step = () => {
      state.navArrowRaf = null;
      if (!state.map || !state.styleLoaded || !state.vehicleVisible || !state.vehiclePose) return;
      const now = performance.now();
      const elapsed = Math.min(1, (now - state.vehicleInterpStart) / 220);
      const t = elapsed * elapsed * (3 - 2 * elapsed);
      const lat = state.vehiclePrev.lat + (state.vehiclePose.lat - state.vehiclePrev.lat) * t;
      const lon = state.vehiclePrev.lon + (state.vehiclePose.lon - state.vehiclePrev.lon) * t;
      const bearing = lerpAngleDeg(state.vehiclePrev.bearing, state.vehiclePose.bearing, t);
      update2DNavArrowSource(state, lat, lon, bearing, true);
      if (elapsed < 1) {
        state.navArrowRaf = window.requestAnimationFrame(step);
      }
    };
    state.navArrowRaf = window.requestAnimationFrame(step);
  }

  function addOverlaySourcesAndLayers(state) {
    const map = state.map;
    if (!map) return;

    const isDay = state.lightingMode === 'day';
    const emptyFC = { type: 'FeatureCollection', features: [] };

    registerChevronSprites(map, isDay);
    registerGoogleStyleSprites(map, isDay);
    register2DNavArrowSprite(map, state.vehicleStyle, isDay);
    registerTurnArrowheadSprites(map, isDay);

    if (!map.getSource('karta-routes-alt')) {
      map.addSource('karta-routes-alt', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-routes-alt-casing',
        type: 'line',
        source: 'karta-routes-alt',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#475569' : '#1E293B', 'line-width': 9.2, 'line-opacity': isDay ? 0.72 : 0.78 }
      });
      map.addLayer({
        id: 'karta-routes-alt-line',
        type: 'line',
        source: 'karta-routes-alt',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#94A3B8' : '#64748B', 'line-width': 6.0, 'line-opacity': isDay ? 0.90 : 0.85 }
      });
    }

    if (!map.getSource('karta-routes-tollfree')) {
      map.addSource('karta-routes-tollfree', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-routes-tollfree-line',
        type: 'line',
        source: 'karta-routes-tollfree',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#168755' : '#42B883', 'line-width': 5.0, 'line-dasharray': [2, 1.5], 'line-opacity': 0.88 }
      });
    }

    if (!map.getSource('karta-route-primary')) {
      map.addSource('karta-route-primary', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-route-primary-outer-glow',
        type: 'line',
        source: 'karta-route-primary',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': isDay ? '#0EA5E9' : '#2DD4BF',
          'line-width': 22,
          'line-opacity': isDay ? 0.22 : 0.26,
          'line-blur': 8
        }
      });
      map.addLayer({
        id: 'karta-route-primary-glow',
        type: 'line',
        source: 'karta-route-primary',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': isDay ? '#0284C7' : '#5EEAD4',
          'line-width': 15,
          'line-opacity': isDay ? 0.30 : 0.35,
          'line-blur': 3
        }
      });
      map.addLayer({
        id: 'karta-route-primary-casing',
        type: 'line',
        source: 'karta-route-primary',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#0B3B3A' : '#082026', 'line-width': 13.0 }
      });
      map.addLayer({
        id: 'karta-route-primary-line',
        type: 'line',
        source: 'karta-route-primary',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDay ? '#0F766E' : '#2DD4BF', 'line-width': 8.2 }
      });
      map.addLayer({
        id: 'karta-route-primary-chevrons',
        type: 'symbol',
        source: 'karta-route-primary',
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 58,
          'icon-image': 'karta-chevron-' + state.chevronFrame,
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'icon-size': ['interpolate', ['linear'], ['zoom'], 6, 0.58, 13, 0.82, 17, 0.96]
        },
        paint: {
          'icon-opacity': 0.96
        }
      });
    }

    if (!map.getSource('karta-traffic-segments')) {
      map.addSource('karta-traffic-segments', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-traffic-segments-line',
        type: 'line',
        source: 'karta-traffic-segments',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': [
            'match',
            ['get', 'severity'],
            'blocked', '#E5534B',
            'heavy', '#EF4444',
            'moderate', '#F59E0B',
            '#22C55E'
          ],
          'line-width': 8.2,
          'line-opacity': 0.95
        }
      });
    }

    // Google Maps / Waze-style curved 2D white-with-teal/blue-border turn direction arrows
    if (!map.getSource('karta-turn-arrows-shaft')) {
      map.addSource('karta-turn-arrows-shaft', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-turn-arrows-casing',
        type: 'line',
        source: 'karta-turn-arrows-shaft',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': ['case', ['==', ['get', 'isActive'], true], (isDay ? '#0369A1' : '#14B8A6'), (isDay ? '#0B5FA5' : '#0E7490')],
          'line-width': ['case', ['==', ['get', 'isActive'], true], 13.5, 10.5],
          'line-opacity': ['case', ['==', ['get', 'isActive'], true], 0.98, 0.86]
        }
      });
      map.addLayer({
        id: 'karta-turn-arrows-fill',
        type: 'line',
        source: 'karta-turn-arrows-shaft',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#FFFFFF',
          'line-width': ['case', ['==', ['get', 'isActive'], true], 7.4, 5.5],
          'line-opacity': ['case', ['==', ['get', 'isActive'], true], 1.0, 0.92]
        }
      });
    }

    if (!map.getSource('karta-turn-arrows-tips')) {
      map.addSource('karta-turn-arrows-tips', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-turn-arrows-tip-symbols',
        type: 'symbol',
        source: 'karta-turn-arrows-tips',
        layout: {
          'icon-image': ['case', ['==', ['get', 'isActive'], true], 'karta-turn-arrowhead-active', 'karta-turn-arrowhead'],
          'icon-rotate': ['get', 'bearingDeg'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'icon-size': ['interpolate', ['linear'], ['zoom'], 10, 0.55, 14, 0.85, 17, 1.05]
        },
        paint: {
          'icon-opacity': ['case', ['==', ['get', 'isActive'], true], 1.0, 0.90]
        }
      });
    }

    if (!map.getSource('karta-carpool-corridor')) {
      map.addSource('karta-carpool-corridor', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-carpool-corridor-line',
        type: 'line',
        source: 'karta-carpool-corridor',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#5294E2',
          'line-width': 5.0,
          'line-dasharray': [2, 1.5],
          'line-opacity': 0.88
        }
      });
    }

    if (!map.getSource('karta-carpool-zones')) {
      map.addSource('karta-carpool-zones', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-carpool-zones-ring',
        type: 'circle',
        source: 'karta-carpool-zones',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, 14, 15, 42],
          'circle-color': isDay ? '#2F756F' : '#5B9A94',
          'circle-opacity': 0.22,
          'circle-stroke-color': isDay ? '#2F756F' : '#72B8B1',
          'circle-stroke-width': 2
        }
      });
    }

    if (!map.getSource('karta-pois')) {
      map.addSource('karta-pois', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-pois-icons',
        type: 'symbol',
        source: 'karta-pois',
        layout: {
          'icon-image': ['coalesce', ['get', 'iconSprite'], 'karta-poi-pin'],
          'icon-size': ['interpolate', ['linear'], ['zoom'], 9, 0.55, 13, 0.78, 16, 0.94],
          'icon-anchor': 'bottom',
          'icon-allow-overlap': false,
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Semibold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10.0, 15, 12.0],
          'text-offset': [0, 0.25],
          'text-anchor': 'top',
          'text-max-width': 10,
          'text-optional': true
        },
        paint: {
          'text-color': isDay ? '#11161C' : '#F4F6F8',
          'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
          'text-halo-width': 2.0,
          'icon-opacity': 0.98,
          'text-opacity': 0.96
        }
      });
      map.on('click', 'karta-pois-icons', (e) => {
        const feats = map.queryRenderedFeatures(e.point, { layers: ['karta-pois-icons'] });
        if (!feats || !feats.length) return;
        const poiId = Number(feats[0].properties && feats[0].properties.id);
        if (Number.isFinite(poiId) && typeof state.onPoiPinTap === 'function') {
          e.originalEvent && e.originalEvent.stopPropagation && e.originalEvent.stopPropagation();
          state.poiClickHandledAt = performance.now();
          state.onPoiPinTap(poiId);
        }
      });
      map.on('mouseenter', 'karta-pois-icons', () => {
        map.getCanvas().style.cursor = 'pointer';
      });
      map.on('mouseleave', 'karta-pois-icons', () => {
        map.getCanvas().style.cursor = '';
      });
    }

    if (!map.getSource('karta-user-accuracy')) {
      map.addSource('karta-user-accuracy', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-user-accuracy-ring',
        type: 'circle',
        source: 'karta-user-accuracy',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, 14, 15, 34, 18, 64],
          'circle-color': '#2D7FF9',
          'circle-opacity': 0.14,
          'circle-stroke-color': '#2D7FF9',
          'circle-stroke-width': 1.5,
          'circle-stroke-opacity': 0.35
        }
      });
    }

    if (!map.getSource('karta-hazards-source')) {
      map.addSource('karta-hazards-source', {
        type: 'geojson',
        data: emptyFC,
        cluster: true,
        clusterMaxZoom: 12,
        clusterRadius: 48,
        clusterProperties: {
          maxRank: ['max', ['get', 'severityRank']]
        }
      });
      map.addLayer({
        id: 'karta-hazard-clusters-halo',
        type: 'circle',
        source: 'karta-hazards-source',
        filter: ['has', 'point_count'],
        paint: {
          'circle-color': [
            'step',
            ['coalesce', ['get', 'maxRank'], 1],
            '#F5A623',
            2, '#5A9DF0',
            3, '#FF5A52'
          ],
          'circle-opacity': isDay ? 0.22 : 0.28,
          'circle-radius': ['step', ['get', 'point_count'], 22, 5, 26, 15, 32]
        }
      });
      map.addLayer({
        id: 'karta-hazard-clusters',
        type: 'circle',
        source: 'karta-hazards-source',
        filter: ['has', 'point_count'],
        paint: {
          'circle-color': [
            'step',
            ['coalesce', ['get', 'maxRank'], 1],
            '#D98A12',
            2, '#347CE0',
            3, '#E0443E'
          ],
          'circle-radius': ['step', ['get', 'point_count'], 15, 5, 18, 15, 22],
          'circle-stroke-width': 2.2,
          'circle-stroke-color': isDay ? '#FCFBF8' : '#0D0F12'
        }
      });
      map.addLayer({
        id: 'karta-hazard-cluster-count',
        type: 'symbol',
        source: 'karta-hazards-source',
        filter: ['has', 'point_count'],
        layout: {
          'text-field': ['get', 'point_count_abbreviated'],
          'text-font': ['Open Sans Semibold'],
          'text-size': 12
        },
        paint: {
          'text-color': '#FFFFFF'
        }
      });
      map.on('click', 'karta-hazard-clusters', (e) => {
        const feats = map.queryRenderedFeatures(e.point, { layers: ['karta-hazard-clusters'] });
        if (!feats || !feats.length) return;
        const clusterId = feats[0].properties.cluster_id;
        const src = map.getSource('karta-hazards-source');
        if (!src || typeof src.getClusterExpansionZoom !== 'function') return;
        src.getClusterExpansionZoom(clusterId, (err, zoomVal) => {
          if (err) return;
          map.easeTo({
            center: feats[0].geometry.coordinates,
            zoom: (zoomVal || 13) + 0.6,
            duration: 420,
            essential: true
          });
        });
      });
      map.on('mouseenter', 'karta-hazard-clusters', () => {
        map.getCanvas().style.cursor = 'pointer';
      });
      map.on('mouseleave', 'karta-hazard-clusters', () => {
        map.getCanvas().style.cursor = '';
      });
    }

    if (!map.getSource('karta-vehicle-halo')) {
      map.addSource('karta-vehicle-halo', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-vehicle-halo-ring',
        type: 'circle',
        source: 'karta-vehicle-halo',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 12, 12, 17, 26],
          'circle-color': state.vehicleStyle.accentHex || '#5B9A94',
          'circle-opacity': 0.24,
          'circle-stroke-color': state.vehicleStyle.accentHex || '#5B9A94',
          'circle-stroke-width': 2.0,
          'circle-stroke-opacity': 0.78
        }
      });
    }

    if (!map.getSource('karta-nav-arrow-2d')) {
      map.addSource('karta-nav-arrow-2d', { type: 'geojson', data: emptyFC });
      map.addLayer({
        id: 'karta-nav-arrow-2d-layer',
        type: 'symbol',
        source: 'karta-nav-arrow-2d',
        layout: {
          'icon-image': 'karta-nav-puck-2d',
          'icon-rotate': ['get', 'bearing'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'icon-size': Math.max(0.65, Math.min(1.4, (state.vehicleStyle.scale || 1.0) * 0.92))
        },
        paint: {
          'icon-opacity': 0.98
        }
      });
    }

    ensureChevronAnimator(state);
  }

  function applyDeclutterInternal(state) {
    const map = state.map;
    if (!map || !state.styleLoaded) return;
    const declutter = !!state.declutterMinor;
    if (map.getLayer('roads_label_minor')) {
      map.setPaintProperty('roads_label_minor', 'text-opacity', declutter ? 0.0 : 0.94);
    }
    if (map.getLayer('poi_landmarks')) {
      map.setPaintProperty('poi_landmarks', 'icon-opacity', declutter ? 0.45 : 0.96);
      map.setPaintProperty('poi_landmarks', 'text-opacity', declutter ? 0.0 : 0.95);
    }
    if (map.getLayer('karta-pois-icons')) {
      map.setPaintProperty('karta-pois-icons', 'icon-opacity', declutter ? 0.55 : 0.98);
      map.setPaintProperty('karta-pois-icons', 'text-opacity', declutter ? 0.0 : 0.96);
    }
  }

  function applyPendingData(state) {
    if (!state.map || !state.styleLoaded) return;
    if (state.pendingRoutes) updateRoutesInternal(state, state.pendingRoutes, false);
    if (state.pendingTurnArrows) updateTurnArrowsInternal(state, state.pendingTurnArrows);
    if (state.pendingSavedPlaces) updateSavedPlacesInternal(state, state.pendingSavedPlaces);
    if (state.pendingPois) updatePoisInternal(state, state.pendingPois);
    updateGantriesInternal(state, []);
    if (state.pendingHazards) updateHazardsInternal(state, state.pendingHazards);
    if (state.pendingTraffic) updateTrafficInternal(state, state.pendingTraffic);
    if (state.pendingFuelPins) updateFuelPinsInternal(state, state.pendingFuelPins);
    if (state.pendingCarpool !== undefined) updateCarpoolInternal(state, state.pendingCarpool);
    if (state.pendingUserLocation) updateUserLocationInternal(state, state.pendingUserLocation);
    if (state.pendingDroppedPin) updateDroppedPinInternal(state, state.pendingDroppedPin);
    if (state.vehicleVisible && state.vehiclePose) {
      update2DNavArrowSource(
        state,
        state.vehiclePose.lat,
        state.vehiclePose.lon,
        state.vehiclePose.bearing,
        true
      );
    }
    applyDeclutterInternal(state);
  }

  function updateTurnArrowsInternal(state, arrows) {
    const map = state.map;
    if (!map) return;
    const shaftSrc = map.getSource('karta-turn-arrows-shaft');
    const tipsSrc = map.getSource('karta-turn-arrows-tips');
    if (!shaftSrc || !tipsSrc) return;

    const list = Array.isArray(arrows) ? arrows : [];
    const shaftFeatures = [];
    const tipFeatures = [];

    list.forEach((a) => {
      if (!a || !Array.isArray(a.shaft) || a.shaft.length < 2) return;
      shaftFeatures.push({
        type: 'Feature',
        properties: { isActive: !!a.isActive, maneuverType: a.maneuverType || 0 },
        geometry: { type: 'LineString', coordinates: a.shaft }
      });
      if (Number.isFinite(a.tipLon) && Number.isFinite(a.tipLat)) {
        tipFeatures.push({
          type: 'Feature',
          properties: { isActive: !!a.isActive, bearingDeg: Number(a.bearingDeg) || 0 },
          geometry: { type: 'Point', coordinates: [a.tipLon, a.tipLat] }
        });
      }
    });

    shaftSrc.setData({ type: 'FeatureCollection', features: shaftFeatures });
    tipsSrc.setData({ type: 'FeatureCollection', features: tipFeatures });
  }

  function updateSavedPlacesInternal(state, places) {
    const map = state.map;
    if (!map) return;
    (state.savedPlaceMarkers || []).forEach(m => m.remove());
    state.savedPlaceMarkers = [];
    const list = Array.isArray(places) ? places : [];
    const iconForCat = (cat) => {
      switch (String(cat || '').toLowerCase()) {
        case 'home': return '⌂';
        case 'work': return '◈';
        case 'landmark': return '⚑';
        default: return '★';
      }
    };
    list.forEach((p) => {
      if (!p || !Number.isFinite(p.lat) || !Number.isFinite(p.lon)) return;
      const el = document.createElement('div');
      el.className = 'karta-saved-pin';
      const safeName = String(p.name || 'Saved').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      el.innerHTML = `<span class="karta-saved-pin-icon">${iconForCat(p.category)}</span><span>${safeName}</span>`;
      const marker = new window.maplibregl.Marker({ element: el, anchor: 'bottom' })
        .setLngLat([p.lon, p.lat])
        .addTo(map);
      state.savedPlaceMarkers.push(marker);
    });
  }

  function updateRoutesInternal(state, data, animateReveal = true) {
    const map = state.map;
    if (!map || !map.getSource('karta-route-primary')) return;

    if (state.routeRevealRaf) {
      window.cancelAnimationFrame(state.routeRevealRaf);
      state.routeRevealRaf = null;
    }

    const routes = data.routes || [];
    const selIdx = data.selectedIndex || 0;
    const tfIdx = data.tollFreeIndex;

    const primaryFeatures = [];
    const altFeatures = [];
    const tfFeatures = [];

    routes.forEach((coords, idx) => {
      if (!coords || coords.length < 2) return;
      const feat = {
        type: 'Feature',
        properties: { routeIndex: idx },
        geometry: { type: 'LineString', coordinates: coords }
      };
      if (idx === selIdx) {
        primaryFeatures.push(feat);
      } else if (tfIdx !== null && tfIdx !== undefined && idx === tfIdx) {
        tfFeatures.push(feat);
      } else {
        altFeatures.push(feat);
      }
    });

    state.hasActiveRoute = primaryFeatures.length > 0;
    map.getSource('karta-routes-alt').setData({ type: 'FeatureCollection', features: altFeatures });
    map.getSource('karta-routes-tollfree').setData({ type: 'FeatureCollection', features: tfFeatures });

    // Smooth animated route draw-in reveal from Start -> Destination
    if (animateReveal && primaryFeatures.length === 1 && primaryFeatures[0].geometry.coordinates.length >= 4) {
      const fullCoords = primaryFeatures[0].geometry.coordinates;
      const totalPts = fullCoords.length;
      const startTime = performance.now();
      const durationMs = 620;
      const tickReveal = (now) => {
        const rawT = Math.min(1, (now - startTime) / durationMs);
        // Smooth easeOutCubic
        const eased = 1 - Math.pow(1 - rawT, 3);
        const count = Math.max(2, Math.round(totalPts * eased));
        const slice = count >= totalPts ? fullCoords : fullCoords.slice(0, count);
        const src = state.map && state.map.getSource('karta-route-primary');
        if (src) {
          src.setData({
            type: 'FeatureCollection',
            features: [{
              type: 'Feature',
              properties: { routeIndex: selIdx },
              geometry: { type: 'LineString', coordinates: slice }
            }]
          });
        }
        if (rawT < 1 && state.styleLoaded) {
          state.routeRevealRaf = window.requestAnimationFrame(tickReveal);
        } else {
          state.routeRevealRaf = null;
        }
      };
      state.routeRevealRaf = window.requestAnimationFrame(tickReveal);
    } else {
      map.getSource('karta-route-primary').setData({ type: 'FeatureCollection', features: primaryFeatures });
    }

    // Update road-snapped curved 2D turn arrows if bundled with route payload
    if (Array.isArray(data.turnArrows)) {
      state.pendingTurnArrows = data.turnArrows;
      updateTurnArrowsInternal(state, data.turnArrows);
    }

    // Update Start / Destination pins
    state.stopMarkers.forEach(m => m.remove());
    state.stopMarkers = [];

    (data.stops || []).forEach(stop => {
      const el = document.createElement('div');
      el.className = 'karta-stop-marker';
      const dotColor = stop.role === 'origin' ? '#22C55E' : (stop.role === 'destination' ? '#E5534B' : '#5B9A94');
      const safeLabel = String(stop.label || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      el.innerHTML = `<span class="karta-stop-dot" style="background:${dotColor}"></span><span>${safeLabel}</span>`;
      const marker = new window.maplibregl.Marker({ element: el, anchor: 'bottom' })
        .setLngLat([stop.lon, stop.lat])
        .addTo(map);
      state.stopMarkers.push(marker);
    });

    // Update Google Maps / Waze-style interactive ETA / delta callout bubbles on routes
    (state.routeCalloutMarkers || []).forEach(m => m.remove());
    state.routeCalloutMarkers = [];

    if (!state.vehicleVisible) {
      (data.callouts || []).forEach(c => {
        if (!c || !Number.isFinite(c.lat) || !Number.isFinite(c.lon)) return;
        const hostEl = document.createElement('div');
        hostEl.className = 'karta-route-callout-host';
        const el = document.createElement('div');
        el.className = 'karta-route-callout' + (c.isSelected ? ' karta-route-callout-selected' : '');
        const safeTitle = String(c.label || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const safeSub = String(c.sublabel || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        el.innerHTML =
          `<div class="karta-route-callout-title">${safeTitle}</div>` +
          (safeSub ? `<div class="karta-route-callout-sub">${safeSub}</div>` : '');
        el.addEventListener('click', (ev) => {
          ev.stopPropagation();
          if (typeof state.onRouteCalloutTap === 'function') {
            state.onRouteCalloutTap(Number(c.routeIndex) || 0);
          }
        });
        hostEl.appendChild(el);
        const marker = new window.maplibregl.Marker({ element: hostEl, anchor: 'bottom', offset: [0, -8] })
          .setLngLat([c.lon, c.lat])
          .addTo(map);
        state.routeCalloutMarkers.push(marker);
      });
    }
  }

  function updatePoisInternal(state, pois) {
    const map = state.map;
    if (!map || !map.getSource('karta-pois')) return;
    const features = (pois || []).map(p => ({
      type: 'Feature',
      properties: {
        id: p.id,
        name: p.name,
        category: p.category || 'landmark',
        iconSprite: poiSpriteIdForCategory(p.category)
      },
      geometry: { type: 'Point', coordinates: [p.lon, p.lat] }
    }));
    map.getSource('karta-pois').setData({ type: 'FeatureCollection', features });
  }

  function updateGantriesInternal(state, _gantries) {
    // Toll gantry map boxes ("TOL RM", "ERP $", "BN B$") are permanently removed.
    (state.gantryMarkers || []).forEach(m => m.remove());
    state.gantryMarkers = [];
  }

  function updateUserLocationInternal(state, loc) {
    const map = state.map;
    if (!map) return;
    const accSrc = map.getSource('karta-user-accuracy');
    if (!loc || !loc.visible || !Number.isFinite(loc.lat) || !Number.isFinite(loc.lon)) {
      if (state.userLocationMarker) {
        state.userLocationMarker.remove();
        state.userLocationMarker = null;
      }
      if (accSrc) accSrc.setData({ type: 'FeatureCollection', features: [] });
      return;
    }

    if (accSrc) {
      accSrc.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          properties: { accuracy: loc.accuracyMeters || 15 },
          geometry: { type: 'Point', coordinates: [loc.lon, loc.lat] }
        }]
      });
    }

    if (!state.userLocationMarker) {
      const el = document.createElement('div');
      el.className = 'karta-user-location-marker';
      el.innerHTML =
        '<div class="karta-user-location-pulse"></div>' +
        '<div class="karta-user-location-cone"></div>' +
        '<div class="karta-user-location-dot"></div>';
      state.userLocationMarker = new window.maplibregl.Marker({ element: el, anchor: 'center' })
        .setLngLat([loc.lon, loc.lat])
        .addTo(map);
    } else {
      state.userLocationMarker.setLngLat([loc.lon, loc.lat]);
    }

    const markerEl = state.userLocationMarker.getElement();
    const cone = markerEl ? markerEl.querySelector('.karta-user-location-cone') : null;
    if (cone) {
      if (typeof loc.headingDeg === 'number' && loc.headingDeg >= 0) {
        cone.style.display = 'block';
        cone.style.transform = `translate(-50%, -50%) rotate(${loc.headingDeg}deg)`;
      } else {
        cone.style.display = 'none';
      }
    }
  }

  function updateDroppedPinInternal(state, pin) {
    const map = state.map;
    if (!map) return;
    if (state.droppedPinMarker) {
      state.droppedPinMarker.remove();
      state.droppedPinMarker = null;
    }
    if (!pin || !pin.visible || !Number.isFinite(pin.lat) || !Number.isFinite(pin.lon)) {
      return;
    }
    const el = document.createElement('div');
    el.className = 'karta-dropped-pin';
    const labelHtml = pin.label
      ? `<div class="karta-dropped-pin-label">${String(pin.label).replace(/</g, '&lt;').replace(/>/g, '&gt;')}</div>`
      : '';
    el.innerHTML =
      '<div class="karta-dropped-pin-head"><div class="karta-dropped-pin-core"></div></div>' +
      labelHtml;
    state.droppedPinMarker = new window.maplibregl.Marker({ element: el, anchor: 'bottom' })
      .setLngLat([pin.lon, pin.lat])
      .addTo(map);
  }

  function scheduleEmitViewportBounds(state) {
    if (!state || !state.map) return;
    if (state.viewportTimer) window.clearTimeout(state.viewportTimer);
    state.viewportTimer = window.setTimeout(() => {
      if (!state.map || typeof state.onViewportChanged !== 'function') return;
      try {
        const b = state.map.getBounds();
        if (!b) return;
        state.onViewportChanged(
          b.getWest(),
          b.getSouth(),
          b.getEast(),
          b.getNorth(),
          state.map.getZoom()
        );
      } catch (_) {}
    }, 320);
  }

  function hazardColorForCategory(cat) {
    switch (cat) {
      case 'police': return '#5294E2';
      case 'accident': return '#E5534B';
      case 'pothole': return '#E6A23C';
      case 'hidden_vehicle': return '#F59E0B';
      case 'road_debris': return '#A855F7';
      case 'road_closure': return '#EF4444';
      default: return '#E5534B';
    }
  }

  function hazardGlyphForCategory(cat) {
    switch (cat) {
      case 'police': return 'POL';
      case 'accident': return 'ACC';
      case 'pothole': return 'POT';
      case 'hidden_vehicle': return 'VEH';
      case 'road_debris': return 'DEB';
      case 'road_closure': return 'CLS';
      default: return '!';
    }
  }

  function scheduleSyncUnclusteredHazards(state) {
    if (!state || state.hazardSyncScheduled) return;
    state.hazardSyncScheduled = true;
    window.requestAnimationFrame(() => {
      state.hazardSyncScheduled = false;
      syncUnclusteredHazardMarkers(state);
    });
  }

  function syncUnclusteredHazardMarkers(state) {
    const map = state.map;
    if (!map || !state.styleLoaded || !map.getSource('karta-hazards-source')) return;
    if (!state.hazardMarkerMap) state.hazardMarkerMap = new Map();
    if (!state.seenHazardIds) state.seenHazardIds = new Set();

    const features = map.querySourceFeatures('karta-hazards-source');
    const visibleUnclustered = new Map();

    // At zoom >= 12.2 or when source hasn't indexed yet, also respect raw pendingHazards if unclustered
    if (features && features.length > 0) {
      features.forEach(f => {
        if (f.properties && f.properties.cluster) return;
        const id = f.properties && f.properties.id;
        if (!id) return;
        if (!visibleUnclustered.has(id)) {
          visibleUnclustered.set(id, {
            id,
            category: f.properties.category,
            label: f.properties.label,
            roadRef: f.properties.roadRef,
            confirmations: f.properties.confirmations,
            onRoute: !!f.properties.onRoute,
            lon: f.geometry.coordinates[0],
            lat: f.geometry.coordinates[1]
          });
        }
      });
    } else if (map.getZoom() >= 12.0 && Array.isArray(state.pendingHazards)) {
      state.pendingHazards.slice(0, 60).forEach(h => {
        visibleUnclustered.set(h.id, h);
      });
    }

    // Remove markers that became clustered or expired
    state.hazardMarkerMap.forEach((marker, id) => {
      if (!visibleUnclustered.has(id)) {
        const el = marker.getElement();
        if (el) el.classList.add('karta-hazard-exit');
        window.setTimeout(() => marker.remove(), 160);
        state.hazardMarkerMap.delete(id);
      }
    });

    // Add or update visible unclustered pins cleanly without flickering existing markers
    visibleUnclustered.forEach((h, id) => {
      const existing = state.hazardMarkerMap.get(id);
      if (existing) {
        existing.setLngLat([h.lon, h.lat]);
        return;
      }
      const color = hazardColorForCategory(h.category);
      const isNewDrop = !state.seenHazardIds.has(id);
      state.seenHazardIds.add(id);

      const wrapper = document.createElement('div');
      wrapper.className = 'karta-hazard-wrapper' + (isNewDrop ? ' karta-hazard-drop-enter' : '');
      wrapper.style.color = color;

      const pin = document.createElement('div');
      pin.className = 'karta-hazard-pin' + (h.onRoute ? ' karta-hazard-onroute' : '');
      pin.style.borderColor = color;
      pin.innerHTML = `<span class="karta-hazard-dot" style="background:${color}"></span><span>${hazardGlyphForCategory(h.category)}</span>`;
      pin.title = `${h.label || h.category}${h.roadRef ? ' · ' + h.roadRef : ''} (${h.confirmations || 1}x)`;
      wrapper.appendChild(pin);

      if (isNewDrop) {
        const sonar = document.createElement('span');
        sonar.className = 'karta-hazard-sonar';
        wrapper.appendChild(sonar);
        window.setTimeout(() => {
          sonar.remove();
          wrapper.classList.remove('karta-hazard-drop-enter');
        }, 760);
      }

      wrapper.addEventListener('click', (ev) => {
        ev.stopPropagation();
        if (typeof state.onHazardPinTap === 'function') {
          state.onHazardPinTap(String(id));
        }
      });

      const marker = new window.maplibregl.Marker({ element: wrapper, anchor: 'center' })
        .setLngLat([h.lon, h.lat])
        .addTo(map);
      state.hazardMarkerMap.set(id, marker);
    });
  }

  function updateHazardsInternal(state, hazards) {
    const map = state.map;
    if (!map) return;
    const list = Array.isArray(hazards) ? hazards.slice(0, 80) : [];
    const src = map.getSource('karta-hazards-source');
    if (src) {
      const features = list.map(h => ({
        type: 'Feature',
        properties: {
          id: String(h.id),
          category: h.category,
          label: h.label || h.category,
          severity: h.severity || 'medium',
          severityRank: Number(h.severityRank) || (h.category === 'road_closure' || h.category === 'accident' ? 3 : (h.category === 'police' ? 2 : 1)),
          confirmations: Number(h.confirmations) || 1,
          roadRef: h.roadRef || '',
          onRoute: !!h.onRoute
        },
        geometry: { type: 'Point', coordinates: [h.lon, h.lat] }
      }));
      src.setData({ type: 'FeatureCollection', features });
      scheduleSyncUnclusteredHazards(state);
    }
  }

  function updateTrafficInternal(state, payload) {
    const map = state.map;
    if (!map || !map.getSource('karta-traffic-segments')) return;
    const pts = (payload && payload.route) || [];
    const segs = (payload && payload.segments) || [];
    if (pts.length < 2 || segs.length === 0) {
      map.getSource('karta-traffic-segments').setData({ type: 'FeatureCollection', features: [] });
      return;
    }

    const features = [];
    segs.forEach(seg => {
      if (seg.severity === 'free') return;
      const startIdx = Math.max(0, Math.floor(seg.startFraction * (pts.length - 1)));
      const endIdx = Math.min(pts.length - 1, Math.max(startIdx + 1, Math.ceil(seg.endFraction * (pts.length - 1))));
      const slice = pts.slice(startIdx, endIdx + 1);
      if (slice.length >= 2) {
        features.push({
          type: 'Feature',
          properties: { severity: seg.severity, speedKmh: seg.speedKmh },
          geometry: { type: 'LineString', coordinates: slice }
        });
      }
    });
    map.getSource('karta-traffic-segments').setData({ type: 'FeatureCollection', features });
  }

  function updateFuelPinsInternal(state, stations) {
    (state.fuelMarkers || []).forEach(m => m.remove());
    state.fuelMarkers = [];
    if (!state.map) return;

    // Sort cheapest first so it always receives priority and elevated z-index
    const ordered = (stations || []).slice(0, 12).sort((a, b) => {
      if (a.cheapest && !b.cheapest) return -1;
      if (!a.cheapest && b.cheapest) return 1;
      return (a.priceMinor || 0) - (b.priceMinor || 0);
    });

    ordered.slice(0, 8).forEach(st => {
      const el = document.createElement('div');
      el.className = 'karta-fuel-pill' + (st.cheapest ? ' karta-fuel-cheapest' : '');
      const brandShort = (st.brand || st.name || 'FUEL').split(' ')[0].toUpperCase().slice(0, 8);
      const gradeShort = st.grade ? String(st.grade).toUpperCase() : '';
      if (st.cheapest) {
        el.innerHTML =
          `<span class="karta-fuel-best-tag">★ BEST</span>` +
          (gradeShort ? `<span class="karta-fuel-grade">${gradeShort}</span>` : '') +
          `<span class="karta-fuel-price">${st.price}</span>`;
      } else {
        const deltaHtml = st.deltaFormatted
          ? `<span class="karta-fuel-delta">(${st.deltaFormatted})</span>`
          : '';
        el.innerHTML =
          `<span class="karta-fuel-brand">${brandShort}</span>` +
          `<span class="karta-fuel-price">${st.price}</span>` +
          deltaHtml;
      }
      el.title = `${st.name || brandShort} · ${gradeShort} ${st.price}${st.cheapest ? ' (Cheapest along route)' : ''}`;
      el.addEventListener('click', (ev) => {
        ev.stopPropagation();
        if (typeof state.onFuelPinTap === 'function') {
          state.onFuelPinTap(Number(st.id));
        }
      });
      const marker = new window.maplibregl.Marker({ element: el, anchor: 'bottom' })
        .setLngLat([st.lon, st.lat])
        .addTo(state.map);
      if (st.cheapest && marker.getElement()) {
        marker.getElement().style.zIndex = '6';
      }
      state.fuelMarkers.push(marker);
    });
  }

  function updateCarpoolInternal(state, overlay) {
    const map = state.map;
    if (!map) return;
    const corrSrc = map.getSource('karta-carpool-corridor');
    const zoneSrc = map.getSource('karta-carpool-zones');
    if (!overlay) {
      if (corrSrc) corrSrc.setData({ type: 'FeatureCollection', features: [] });
      if (zoneSrc) zoneSrc.setData({ type: 'FeatureCollection', features: [] });
      return;
    }
    if (corrSrc && overlay.corridor && overlay.corridor.length >= 2) {
      corrSrc.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          properties: {},
          geometry: { type: 'LineString', coordinates: overlay.corridor }
        }]
      });
    }
    if (zoneSrc && overlay.originZone && overlay.destZone) {
      zoneSrc.setData({
        type: 'FeatureCollection',
        features: [
          { type: 'Feature', properties: { role: 'pickup' }, geometry: { type: 'Point', coordinates: [overlay.originZone.lon, overlay.originZone.lat] } },
          { type: 'Feature', properties: { role: 'dropoff' }, geometry: { type: 'Point', coordinates: [overlay.destZone.lon, overlay.destZone.lat] } }
        ]
      });
    }
  }

  function applyLightingToContainer(container, isDay) {
    if (!container) return;
    container.style.backgroundColor = isDay ? '#F5F2EB' : '#0D0F12';
    container.classList.toggle('karta-map-day', isDay);
    if (document.body) {
      document.body.classList.toggle('karta-day', isDay);
    }
  }

  window.KartaMapBridge = {
    async init(containerId, pmtilesUrl, lat, lon, zoom, pitch, onReady, onMapTap, onUserDrag) {
      ensurePmtilesProtocol();
      const container = document.getElementById(containerId);
      if (!container || !window.maplibregl) return;

      const resolved = await resolveVectorSource(pmtilesUrl);
      const initialMode = 'dark';
      const styleObj = buildMapStyle(resolved.sourceConfig, resolved.schema, true, initialMode);

      const state = {
        map: null,
        container,
        styleLoaded: false,
        lightingMode: initialMode,
        declutterMinor: false,
        drivingSpeedKmh: 0,
        hasActiveRoute: false,
        chevronFrame: 0,
        chevronTimer: null,
        sourceConfig: resolved.sourceConfig,
        schema: resolved.schema,
        tileTemplate: resolved.tileTemplate,
        pmtilesArchive: resolved.pmtilesArchive,
        warmedTiles: new Set(),
        prefetchQueue: [],
        prefetchWorkers: 0,
        enable3D: true,
        stopMarkers: [],
        routeCalloutMarkers: [],
        savedPlaceMarkers: [],
        gantryMarkers: [],
        hazardMarkers: [],
        hazardMarkerMap: new Map(),
        seenHazardIds: new Set(),
        hazardSyncScheduled: false,
        onFuelPinTap: null,
        onHazardPinTap: null,
        onPoiPinTap: null,
        onRouteCalloutTap: null,
        onViewportChanged: null,
        poiClickHandledAt: 0,
        viewportTimer: null,
        routeRevealRaf: null,
        navArrowRaf: null,
        isUserInteracting: false,
        userLocationMarker: null,
        droppedPinMarker: null,
        pendingUserLocation: null,
        pendingDroppedPin: null,
        pendingTurnArrows: null,
        pendingSavedPlaces: null,
        fuelMarkers: [],
        pendingRoutes: null,
        pendingPois: null,
        pendingGantries: null,
        pendingHazards: null,
        pendingTraffic: null,
        pendingFuelPins: null,
        pendingCarpool: undefined,
        vehicleVisible: false,
        vehiclePose: { lat, lon, bearing: 0 },
        vehiclePrev: { lat, lon, bearing: 0 },
        vehicleInterpStart: performance.now(),
        vehicleStyle: { avatar: 'karta_pin_3d', accentHex: '#5B9A94', showHaloRing: true, scale: 1.0 }
      };

      const map = new window.maplibregl.Map({
        container,
        style: styleObj,
        center: [lon, lat],
        zoom: zoom || 15.2,
        pitch: Math.min(pitch || 45, 58),
        bearing: -18,
        maxPitch: 60,
        maxTileCacheSize: 256,
        canvasContextAttributes: { antialias: true, stencil: true },
        attributionControl: true
      });

      state.map = map;
      instances.set(containerId, state);

      map.on('styleimagemissing', (e) => {
        if (!e || !e.id) return;
        if (e.id.startsWith('karta-poi-') || e.id.startsWith('karta-shield-')) {
          registerGoogleStyleSprites(map, state.lightingMode === 'day');
        } else if (e.id.startsWith('karta-chevron-')) {
          registerChevronSprites(map, state.lightingMode === 'day');
        } else if (e.id === 'karta-nav-puck-2d') {
          register2DNavArrowSprite(map, state.vehicleStyle, state.lightingMode === 'day');
        } else if (e.id.startsWith('karta-turn-arrowhead')) {
          registerTurnArrowheadSprites(map, state.lightingMode === 'day');
        }
      });

      map.on('error', (e) => {
        console.error('[KartaMapBridge] MapLibre error:', e && e.error ? e.error.message : e);
      });

      map.on('load', () => {
        state.styleLoaded = true;
        addOverlaySourcesAndLayers(state);
        applyPendingData(state);
        if (typeof onReady === 'function') onReady();
        scheduleEmitViewportBounds(state);
      });

      map.on('click', (e) => {
        if (performance.now() - (state.poiClickHandledAt || 0) < 120) return;
        if (typeof onMapTap === 'function') {
          onMapTap(e.lngLat.lat, e.lngLat.lng);
        }
      });

      map.on('dragstart', () => {
        state.isUserInteracting = true;
        if (typeof onUserDrag === 'function') onUserDrag();
      });
      map.on('zoomstart', () => {
        state.isUserInteracting = true;
      });
      map.on('moveend', () => {
        state.isUserInteracting = false;
        scheduleSyncUnclusteredHazards(state);
        scheduleEmitViewportBounds(state);
      });
      map.on('zoomend', () => {
        state.isUserInteracting = false;
        scheduleSyncUnclusteredHazards(state);
      });
      map.on('sourcedata', (ev) => {
        if (ev && ev.sourceId === 'karta-hazards-source' && ev.isSourceLoaded) {
          scheduleSyncUnclusteredHazards(state);
        }
      });

      const ro = new ResizeObserver(() => map.resize());
      ro.observe(container);
      state.resizeObserver = ro;
    },

    setLightingMode(containerId, mode) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      const normalized = mode === 'day' ? 'day' : 'dark';
      const isDay = normalized === 'day';
      applyLightingToContainer(state.container, isDay);

      if (state.lightingMode === normalized && state.styleLoaded) return;
      state.lightingMode = normalized;
      state.styleLoaded = false;

      const styleObj = buildMapStyle(state.sourceConfig, state.schema, state.enable3D, normalized);
      let applied = false;
      const onStyleReady = () => {
        if (applied || !state.map) return;
        applied = true;
        state.styleLoaded = true;
        addOverlaySourcesAndLayers(state);
        applyPendingData(state);
      };
      // Register listener BEFORE setStyle so synchronous inline-object style loads never miss style.load
      state.map.once('style.load', onStyleReady);
      state.map.setStyle(styleObj);
      if (state.map.isStyleLoaded()) {
        window.setTimeout(onStyleReady, 0);
      }
    },

    setDrivingSpeed(containerId, speedKmh, declutterMinor) {
      const state = instances.get(containerId);
      if (!state) return;
      state.drivingSpeedKmh = speedKmh || 0;
      const nextDeclutter = !!declutterMinor;
      if (state.declutterMinor !== nextDeclutter) {
        state.declutterMinor = nextDeclutter;
        applyDeclutterInternal(state);
      }
    },

    easeCamera(containerId, optionsJson) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      const opts = JSON.parse(optionsJson);
      const cam = {
        center: [opts.lon, opts.lat],
        duration: opts.durationMs ?? 550,
        essential: true
      };
      if (opts.zoom !== undefined) cam.zoom = opts.zoom;
      if (opts.pitch !== undefined) cam.pitch = opts.pitch;
      if (opts.bearing !== undefined) cam.bearing = opts.bearing;
      if (opts.padding) cam.padding = opts.padding;
      state.map.easeTo(cam);
    },

    fitBounds(containerId, optionsJson) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      const opts = JSON.parse(optionsJson);
      const minLat = Math.max(-85, Math.min(85, Number(opts.minLat)));
      const maxLat = Math.max(-85, Math.min(85, Number(opts.maxLat)));
      const minLon = Math.max(-180, Math.min(180, Number(opts.minLon)));
      const maxLon = Math.max(-180, Math.min(180, Number(opts.maxLon)));
      if (![minLat, maxLat, minLon, maxLon].every(Number.isFinite)) return;
      const width = state.map.getContainer().clientWidth || 1200;
      const pad = opts.padding || { left: 80, top: 80, right: 80, bottom: 80 };
      const adaptiveLeft = width < 640 ? 40 : (width < 1080 ? Math.min(pad.left, 380) : pad.left);
      state.map.fitBounds(
        [[minLon, minLat], [maxLon, maxLat]],
        {
          padding: { left: adaptiveLeft, top: pad.top, right: pad.right, bottom: pad.bottom },
          duration: 850,
          pitch: state.enable3D ? 42 : 0,
          maxZoom: 15.5
        }
      );
    },

    setRoutes(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const data = JSON.parse(payloadJson);
      state.pendingRoutes = data;
      if (state.styleLoaded) updateRoutesInternal(state, data, true);
    },

    setTurnArrows(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const arrows = JSON.parse(payloadJson);
      state.pendingTurnArrows = arrows;
      if (state.styleLoaded) updateTurnArrowsInternal(state, arrows);
    },

    setSavedPlaces(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const places = JSON.parse(payloadJson);
      state.pendingSavedPlaces = places;
      if (state.styleLoaded) updateSavedPlacesInternal(state, places);
    },

    setPois(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const pois = JSON.parse(payloadJson);
      state.pendingPois = pois;
      if (state.styleLoaded) updatePoisInternal(state, pois);
    },

    setTollGantries(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const gantries = JSON.parse(payloadJson);
      state.pendingGantries = gantries;
      if (state.styleLoaded) updateGantriesInternal(state, gantries);
    },

    setHazards(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const hazards = JSON.parse(payloadJson);
      state.pendingHazards = hazards;
      if (state.styleLoaded) updateHazardsInternal(state, hazards);
    },

    setTrafficSegments(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const payload = JSON.parse(payloadJson);
      state.pendingTraffic = payload;
      if (state.styleLoaded) updateTrafficInternal(state, payload);
    },

    setFuelPins(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const stations = JSON.parse(payloadJson);
      state.pendingFuelPins = stations;
      if (state.styleLoaded) updateFuelPinsInternal(state, stations);
    },

    setCarpoolOverlay(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      const overlay = JSON.parse(payloadJson);
      state.pendingCarpool = overlay;
      if (state.styleLoaded) updateCarpoolInternal(state, overlay);
    },

    setVehiclePose(containerId, lat, lon, bearingDeg, speedKmh, visible) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      const wasVisible = state.vehicleVisible;
      state.vehiclePrev = state.vehiclePose || { lat, lon, bearing: bearingDeg };
      state.vehiclePose = { lat, lon, bearing: bearingDeg, speedKmh };
      state.vehicleInterpStart = performance.now();
      state.vehicleVisible = visible;

      // Hide route preview ETA bubbles while actively driving; restore when exiting navigation
      if (visible && !wasVisible && state.routeCalloutMarkers && state.routeCalloutMarkers.length) {
        state.routeCalloutMarkers.forEach(m => m.remove());
        state.routeCalloutMarkers = [];
      }

      if (!visible) {
        update2DNavArrowSource(state, lat, lon, bearingDeg, false);
        return;
      }
      if (state.styleLoaded) {
        startNavArrowAnimation(state);
      }
    },

    setVehicleCustomization(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state) return;
      state.vehicleStyle = JSON.parse(payloadJson);
      if (state.map && state.styleLoaded) {
        register2DNavArrowSprite(state.map, state.vehicleStyle, state.lightingMode === 'day');
        if (state.map.getLayer('karta-nav-arrow-2d-layer')) {
          state.map.setLayoutProperty(
            'karta-nav-arrow-2d-layer',
            'icon-size',
            Math.max(0.65, Math.min(1.4, (state.vehicleStyle.scale || 1.0) * 0.92))
          );
        }
        if (state.map.getLayer('karta-vehicle-halo-ring')) {
          state.map.setPaintProperty('karta-vehicle-halo-ring', 'circle-color', state.vehicleStyle.accentHex);
          state.map.setPaintProperty('karta-vehicle-halo-ring', 'circle-stroke-color', state.vehicleStyle.accentHex);
        }
        state.map.triggerRepaint();
      }
    },

    set3DBuildings(containerId, enabled) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      state.enable3D = enabled;
      if (state.map.getLayer('buildings_3d')) {
        state.map.setLayoutProperty('buildings_3d', 'visibility', enabled ? 'visible' : 'none');
      }
    },

    async setPmtilesUrl(containerId, pmtilesUrl) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      const resolved = await resolveVectorSource(pmtilesUrl);
      state.sourceConfig = resolved.sourceConfig;
      state.schema = resolved.schema;
      state.tileTemplate = resolved.tileTemplate;
      state.pmtilesArchive = resolved.pmtilesArchive;
      state.warmedTiles.clear();
      state.styleLoaded = false;
      let applied = false;
      const onStyleReady = () => {
        if (applied || !state.map) return;
        applied = true;
        state.styleLoaded = true;
        addOverlaySourcesAndLayers(state);
        applyPendingData(state);
      };
      state.map.once('style.load', onStyleReady);
      state.map.setStyle(buildMapStyle(resolved.sourceConfig, resolved.schema, state.enable3D, state.lightingMode));
      if (state.map.isStyleLoaded()) {
        window.setTimeout(onStyleReady, 0);
      }
    },

    prefetchTiles(containerId, payloadJson) {
      const state = instances.get(containerId);
      if (!state || (!state.tileTemplate && !state.pmtilesArchive)) return;
      let tiles;
      try {
        tiles = JSON.parse(payloadJson);
      } catch (_) {
        return;
      }
      if (!Array.isArray(tiles) || tiles.length === 0) return;

      for (const t of tiles) {
        const key = `${t.z}/${t.x}/${t.y}`;
        if (state.warmedTiles.has(key)) continue;
        state.warmedTiles.add(key);
        if (state.warmedTiles.size > 600) {
          const first = state.warmedTiles.values().next().value;
          if (first) state.warmedTiles.delete(first);
        }
        state.prefetchQueue.push(t);
      }

      const pump = async () => {
        if (state.prefetchWorkers >= 2 || state.isUserInteracting) return;
        state.prefetchWorkers += 1;
        try {
          while (state.prefetchQueue.length > 0 && instances.has(containerId) && !state.isUserInteracting) {
            const tile = state.prefetchQueue.shift();
            if (!tile) break;
            try {
              if (state.pmtilesArchive && typeof state.pmtilesArchive.getZxy === 'function') {
                await state.pmtilesArchive.getZxy(tile.z, tile.x, tile.y);
              } else if (state.tileTemplate) {
                const url = state.tileTemplate
                  .replace('{z}', String(tile.z))
                  .replace('{x}', String(tile.x))
                  .replace('{y}', String(tile.y));
                await fetch(url, { mode: 'cors', cache: 'force-cache', priority: 'low' });
              }
            } catch (_) {
              // Silent best-effort prefetch
            }
          }
        } finally {
          state.prefetchWorkers -= 1;
        }
      };

      const launchCount = Math.min(2 - state.prefetchWorkers, state.prefetchQueue.length);
      for (let i = 0; i < launchCount; i += 1) {
        pump();
      }
    },

    setLookAroundOrbit(containerId, lat, lon, bearingDeg, active) {
      const state = instances.get(containerId);
      if (!state || !state.map) return;
      if (active) {
        state.map.easeTo({
          center: [lon, lat],
          zoom: 18.0,
          pitch: 76,
          bearing: bearingDeg,
          duration: 500,
          essential: true
        });
      } else {
        state.map.easeTo({
          center: [lon, lat],
          zoom: 15.5,
          pitch: state.enable3D ? 56 : 0,
          duration: 500,
          essential: true
        });
      }
    },

    setUserLocation(containerId, lat, lon, headingDeg, accuracyMeters, visible) {
      const state = instances.get(containerId);
      if (!state) return;
      const loc = { lat, lon, headingDeg, accuracyMeters, visible };
      state.pendingUserLocation = loc;
      if (state.styleLoaded) updateUserLocationInternal(state, loc);
    },

    setDroppedPin(containerId, lat, lon, label, visible) {
      const state = instances.get(containerId);
      if (!state) return;
      const pin = { lat, lon, label, visible };
      state.pendingDroppedPin = pin;
      if (state.styleLoaded) updateDroppedPinInternal(state, pin);
    },

    registerPinCallbacks(containerId, onFuelPinTap, onHazardPinTap, onPoiPinTap, onViewportChanged, onRouteCalloutTap) {
      const state = instances.get(containerId);
      if (!state) return;
      state.onFuelPinTap = onFuelPinTap;
      state.onHazardPinTap = onHazardPinTap;
      state.onPoiPinTap = onPoiPinTap;
      state.onViewportChanged = onViewportChanged;
      state.onRouteCalloutTap = onRouteCalloutTap;
      if (state.styleLoaded) scheduleEmitViewportBounds(state);
    },

    destroy(containerId) {
      const state = instances.get(containerId);
      if (!state) return;
      if (state.chevronTimer) window.clearInterval(state.chevronTimer);
      if (state.viewportTimer) window.clearTimeout(state.viewportTimer);
      if (state.routeRevealRaf) window.cancelAnimationFrame(state.routeRevealRaf);
      if (state.navArrowRaf) window.cancelAnimationFrame(state.navArrowRaf);
      if (state.resizeObserver) state.resizeObserver.disconnect();
      state.stopMarkers.forEach(m => m.remove());
      (state.routeCalloutMarkers || []).forEach(m => m.remove());
      (state.savedPlaceMarkers || []).forEach(m => m.remove());
      state.gantryMarkers.forEach(m => m.remove());
      if (state.userLocationMarker) state.userLocationMarker.remove();
      if (state.droppedPinMarker) state.droppedPinMarker.remove();
      (state.hazardMarkers || []).forEach(m => m.remove());
      if (state.hazardMarkerMap) {
        state.hazardMarkerMap.forEach(m => m.remove());
        state.hazardMarkerMap.clear();
      }
      (state.fuelMarkers || []).forEach(m => m.remove());
      if (state.map) state.map.remove();
      instances.delete(containerId);
    }
  };

  // Offline zero-latency Web Audio API harmonic chime synthesizer for
  // hands-free voice reporting and quick-flick radial confirmations.
  let sharedAudioCtx = null;
  function getAudioCtx() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return null;
    if (!sharedAudioCtx) sharedAudioCtx = new AudioCtx();
    if (sharedAudioCtx.state === 'suspended') {
      sharedAudioCtx.resume().catch(() => {});
    }
    return sharedAudioCtx;
  }

  function playToneSequence(notes) {
    try {
      const ctx = getAudioCtx();
      if (!ctx) return;
      const baseTime = ctx.currentTime + 0.01;
      notes.forEach(n => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = n.wave || 'sine';
        osc.frequency.setValueAtTime(n.freq, baseTime + n.delay);
        gain.gain.setValueAtTime(0.0001, baseTime + n.delay);
        gain.gain.exponentialRampToValueAtTime(n.vol || 0.11, baseTime + n.delay + 0.016);
        gain.gain.exponentialRampToValueAtTime(0.0001, baseTime + n.delay + n.dur);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(baseTime + n.delay);
        osc.stop(baseTime + n.delay + n.dur + 0.02);
      });
    } catch (_) {}
  }

  window.KartaAudioChime = {
    play(type) {
      switch (type) {
        case 'listenStart':
          playToneSequence([
            { freq: 523.25, delay: 0.0, dur: 0.08, vol: 0.10, wave: 'sine' },
            { freq: 783.99, delay: 0.065, dur: 0.12, vol: 0.11, wave: 'triangle' }
          ]);
          break;
        case 'intentDetected':
          playToneSequence([
            { freq: 659.25, delay: 0.0, dur: 0.09, vol: 0.10, wave: 'sine' }
          ]);
          break;
        case 'reportConfirmed':
          playToneSequence([
            { freq: 587.33, delay: 0.0, dur: 0.10, vol: 0.12, wave: 'sine' },
            { freq: 880.0, delay: 0.085, dur: 0.17, vol: 0.13, wave: 'triangle' }
          ]);
          break;
        case 'cancelled':
          playToneSequence([
            { freq: 440.0, delay: 0.0, dur: 0.075, vol: 0.08, wave: 'sine' },
            { freq: 329.63, delay: 0.065, dur: 0.11, vol: 0.075, wave: 'sine' }
          ]);
          break;
        default:
          break;
      }
    }
  };
})();
