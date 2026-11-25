import 'package:karta_navigation_core/karta_navigation_core.dart';

/// Generates Karta's MapLibre Style v8 specifications for both
/// Obsidian Night Mode (`#0D0F12`) and High-Glare Tropical Daylight Mode (`#F5F2EB`),
/// complete with 3D extruded buildings (`hide_3d` landmark fidelity), highland relief
/// shading echoing Karta's mountain crest, and split minor/major street labels for
/// speed-adaptive decluttering above 60 km/h.
abstract final class KartaMapStyleBuilder {
  static Map<String, dynamic> build({
    required String pmtilesUrl,
    KartaVisualMode mode = KartaVisualMode.obsidianNight,
    String schema = 'openmaptiles',
    bool enable3DBuildings = true,
  }) {
    final isDay = mode == KartaVisualMode.tropicalDaylight;
    final isProtomaps = schema == 'protomaps';

    final buildingSourceLayer = isProtomaps ? 'buildings' : 'building';
    final roadSourceLayer = isProtomaps ? 'roads' : 'transportation';
    final roadLabelLayer = isProtomaps ? 'roads' : 'transportation_name';
    final placeSourceLayer = isProtomaps ? 'places' : 'place';
    final boundarySourceLayer = isProtomaps ? 'boundaries' : 'boundary';

    final minorFilter = isProtomaps
        ? <dynamic>['in', 'kind', 'minor_road', 'other', 'path']
        : <dynamic>['in', 'class', 'minor', 'service', 'track', 'path', 'street', 'residential', 'unclassified', 'living_street', 'pedestrian', 'busway', 'raceway', 'minor_construction'];
    final secondaryFilter = isProtomaps
        ? <dynamic>['in', 'kind', 'medium_road']
        : <dynamic>['in', 'class', 'secondary', 'tertiary', 'secondary_link', 'tertiary_link', 'secondary_construction', 'tertiary_construction'];
    final primaryFilter = isProtomaps
        ? <dynamic>['in', 'kind', 'major_road']
        : <dynamic>['in', 'class', 'primary', 'trunk', 'primary_link', 'trunk_link', 'primary_construction', 'trunk_construction'];
    final highwayFilter = isProtomaps
        ? <dynamic>['==', 'kind', 'highway']
        : <dynamic>['in', 'class', 'motorway', 'motorway_link', 'motorway_construction'];
    final countryBoundaryFilter = isProtomaps
        ? <dynamic>['==', 'kind', 'country']
        : <dynamic>['all', <dynamic>['==', 'admin_level', 2], <dynamic>['!=', 'maritime', 1]];
    final minorLabelFilter = isProtomaps
        ? <dynamic>['in', 'kind', 'minor_road', 'other', 'path']
        : <dynamic>['in', 'class', 'minor', 'service', 'track', 'path', 'street', 'residential', 'unclassified', 'living_street', 'pedestrian', 'tertiary'];
    final majorLabelFilter = isProtomaps
        ? <dynamic>['in', 'kind', 'highway', 'major_road', 'medium_road']
        : <dynamic>['in', 'class', 'motorway', 'trunk', 'primary', 'secondary'];

    return <String, dynamic>{
      'version': 8,
      'name': isDay
          ? 'Karta Tropical Daylight 3D Automotive v1'
          : 'Karta Dark 3D Automotive v1',
      'light': <String, dynamic>{
        'anchor': 'viewport',
        'color': isDay ? '#FFFDF5' : '#E8F4F2',
        'intensity': isDay ? 0.56 : 0.58,
        'position': isDay ? <double>[1.25, 195, 52] : <double>[1.4, 215, 38],
      },
      'sources': <String, dynamic>{
        'karta_basemap': <String, dynamic>{
          'type': 'vector',
          'url': pmtilesUrl.endsWith('.json')
              ? pmtilesUrl
              : (pmtilesUrl.startsWith('pmtiles://') ? pmtilesUrl : 'pmtiles://$pmtilesUrl'),
          'attribution': 'OpenStreetMap contributors | Karta Navigation',
        },
      },
      'glyphs': 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
      'layers': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'background',
          'type': 'background',
          'paint': <String, dynamic>{
            'background-color': isDay ? '#F5F2EB' : '#0D0F12',
          },
        },
        if (isProtomaps)
          <String, dynamic>{
            'id': 'earth',
            'type': 'fill',
            'source': 'karta_basemap',
            'source-layer': 'earth',
            'paint': <String, dynamic>{
              'fill-color': isDay ? '#EFECE3' : '#141820',
            },
          }
        else ...<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'landcover_highland',
            'type': 'fill',
            'source': 'karta_basemap',
            'source-layer': 'landcover',
            'filter': <dynamic>['in', 'class', 'wood', 'rock', 'grass', 'wetland'],
            'paint': <String, dynamic>{
              'fill-color': isDay ? '#DCE8DF' : '#111E1B',
              'fill-opacity': isDay ? 0.82 : 0.78,
            },
          },
          <String, dynamic>{
            'id': 'park',
            'type': 'fill',
            'source': 'karta_basemap',
            'source-layer': 'park',
            'paint': <String, dynamic>{
              'fill-color': isDay ? '#D4E6D9' : '#132622',
              'fill-opacity': 0.88,
            },
          },
        ],
        <String, dynamic>{
          'id': 'water',
          'type': 'fill',
          'source': 'karta_basemap',
          'source-layer': 'water',
          'paint': <String, dynamic>{
            'fill-color': isDay ? '#C9E0EA' : '#070B12',
          },
        },
        if (isDay)
          <String, dynamic>{
            'id': 'roads_minor_casing',
            'type': 'line',
            'source': 'karta_basemap',
            'source-layer': roadSourceLayer,
            'minzoom': 11,
            'filter': minorFilter,
            'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
            'paint': <String, dynamic>{
              'line-color': '#C7C2B7',
              'line-width': <dynamic>[
                'interpolate',
                <dynamic>['exponential', 1.5],
                <dynamic>['zoom'],
                11,
                1.4,
                15,
                5.4,
                18,
                13.0,
              ],
            },
          },
        <String, dynamic>{
          'id': 'roads_minor',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': roadSourceLayer,
          'minzoom': 11,
          'filter': minorFilter,
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': isDay ? '#FFFFFF' : '#252E3B',
            'line-width': <dynamic>[
              'interpolate',
              <dynamic>['exponential', 1.5],
              <dynamic>['zoom'],
              11,
              0.7,
              15,
              3.8,
              18,
              10.5,
            ],
          },
        },
        if (isDay)
          <String, dynamic>{
            'id': 'roads_secondary_casing',
            'type': 'line',
            'source': 'karta_basemap',
            'source-layer': roadSourceLayer,
            'minzoom': 8,
            'filter': secondaryFilter,
            'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
            'paint': <String, dynamic>{
              'line-color': '#9AA6B3',
              'line-width': <dynamic>[
                'interpolate',
                <dynamic>['exponential', 1.5],
                <dynamic>['zoom'],
                8,
                1.8,
                14,
                6.8,
                17,
                15.8,
              ],
            },
          },
        <String, dynamic>{
          'id': 'roads_secondary',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': roadSourceLayer,
          'minzoom': 8,
          'filter': secondaryFilter,
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': isDay ? '#FFFDF8' : '#324052',
            'line-width': <dynamic>[
              'interpolate',
              <dynamic>['exponential', 1.5],
              <dynamic>['zoom'],
              8,
              0.8,
              14,
              4.5,
              17,
              12.5,
            ],
          },
        },
        if (isDay)
          <String, dynamic>{
            'id': 'roads_primary_casing',
            'type': 'line',
            'source': 'karta_basemap',
            'source-layer': roadSourceLayer,
            'minzoom': 6,
            'filter': primaryFilter,
            'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
            'paint': <String, dynamic>{
              'line-color': '#647486',
              'line-width': <dynamic>[
                'interpolate',
                <dynamic>['exponential', 1.5],
                <dynamic>['zoom'],
                6,
                2.2,
                14,
                8.6,
                17,
                18.6,
              ],
            },
          },
        <String, dynamic>{
          'id': 'roads_primary',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': roadSourceLayer,
          'minzoom': 6,
          'filter': primaryFilter,
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': isDay ? '#FCEFD8' : '#42556B',
            'line-width': <dynamic>[
              'interpolate',
              <dynamic>['exponential', 1.5],
              <dynamic>['zoom'],
              6,
              1.0,
              14,
              6.0,
              17,
              15.0,
            ],
          },
        },
        <String, dynamic>{
          'id': 'aeroway_runway',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': isProtomaps ? 'transit' : 'aeroway',
          'minzoom': 10,
          'filter': <dynamic>['in', isProtomaps ? 'kind' : 'class', 'runway', 'taxiway'],
          'paint': <String, dynamic>{
            'line-color': isDay ? '#C8D0D8' : '#2C3745',
            'line-width': <dynamic>['interpolate', <dynamic>['linear'], <dynamic>['zoom'], 10, 1.5, 15, 10],
          },
        },
        <String, dynamic>{
          'id': 'roads_motorway_casing',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': roadSourceLayer,
          'filter': highwayFilter,
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': isDay ? '#163834' : '#090B0E',
            'line-width': <dynamic>[
              'interpolate',
              <dynamic>['exponential', 1.5],
              <dynamic>['zoom'],
              5,
              isDay ? 3.0 : 2.4,
              12,
              isDay ? 8.2 : 6.6,
              17,
              isDay ? 21.0 : 18.0,
            ],
          },
        },
        <String, dynamic>{
          'id': 'roads_motorway',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': roadSourceLayer,
          'filter': highwayFilter,
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': isDay ? '#2F756F' : '#5B9A94',
            'line-opacity': isDay ? 0.94 : 0.86,
            'line-width': <dynamic>[
              'interpolate',
              <dynamic>['exponential', 1.5],
              <dynamic>['zoom'],
              5,
              1.4,
              12,
              4.6,
              17,
              15.0,
            ],
          },
        },
        <String, dynamic>{
          'id': 'buildings_footprint',
          'type': 'fill',
          'source': 'karta_basemap',
          'source-layer': buildingSourceLayer,
          'minzoom': 12.0,
          'paint': <String, dynamic>{
            'fill-color': isDay ? '#E5E1D7' : '#1A2029',
            'fill-outline-color': isDay ? '#C4BFB3' : '#2B3544',
            'fill-opacity': 0.88,
          },
        },
        if (enable3DBuildings)
          <String, dynamic>{
            'id': 'buildings_3d',
            'type': 'fill-extrusion',
            'source': 'karta_basemap',
            'source-layer': buildingSourceLayer,
            'minzoom': 13.0,
            'filter': <dynamic>['!=', <dynamic>['get', 'hide_3d'], true],
            'paint': <String, dynamic>{
              'fill-extrusion-color': <dynamic>[
                'interpolate',
                <dynamic>['linear'],
                <dynamic>['coalesce', <dynamic>['get', 'render_height'], <dynamic>['get', 'height'], 16],
                0,
                isDay ? '#E7E4DC' : '#1D242E',
                45,
                isDay ? '#D9E0DE' : '#263240',
                120,
                isDay ? '#C3D4D2' : '#314552',
                250,
                isDay ? '#97BCB8' : '#41686B',
                420,
                isDay ? '#2F756F' : '#5B9A94',
              ],
              'fill-extrusion-height': <dynamic>[
                'interpolate',
                <dynamic>['linear'],
                <dynamic>['zoom'],
                13.0,
                0,
                13.8,
                <dynamic>['coalesce', <dynamic>['get', 'render_height'], <dynamic>['get', 'height'], 16],
              ],
              'fill-extrusion-base': <dynamic>[
                'interpolate',
                <dynamic>['linear'],
                <dynamic>['zoom'],
                13.0,
                0,
                13.8,
                <dynamic>[
                  'coalesce',
                  <dynamic>['get', 'render_min_height'],
                  <dynamic>['get', 'min_height'],
                  0,
                ],
              ],
              'fill-extrusion-opacity': isDay ? 0.92 : 0.94,
              'fill-extrusion-vertical-gradient': true,
            },
          },
        <String, dynamic>{
          'id': 'boundaries_country',
          'type': 'line',
          'source': 'karta_basemap',
          'source-layer': boundarySourceLayer,
          'filter': countryBoundaryFilter,
          'paint': <String, dynamic>{
            'line-color': isDay ? '#455362' : '#8E96A0',
            'line-dasharray': <double>[4, 2],
            'line-width': isDay ? 1.7 : 1.5,
          },
        },
        if (!isProtomaps)
          <String, dynamic>{
            'id': 'mountain_peaks_label',
            'type': 'symbol',
            'source': 'karta_basemap',
            'source-layer': 'mountain_peak',
            'minzoom': 9,
            'layout': <String, dynamic>{
              'text-field': <dynamic>[
                'concat',
                '▲ ',
                <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
              ],
              'text-font': <String>['Noto Sans Regular'],
              'text-size': 10.5,
            },
            'paint': <String, dynamic>{
              'text-color': isDay ? '#485958' : '#72B8B1',
              'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
              'text-halo-width': 1.7,
            },
          },
        <String, dynamic>{
          'id': 'water_name',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': isProtomaps ? 'water' : 'water_name',
          'minzoom': 8,
          'layout': <String, dynamic>{
            'text-field': <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
            'text-font': <String>['Noto Sans Regular'],
            'text-size': <dynamic>['interpolate', <dynamic>['linear'], <dynamic>['zoom'], 8, 10.5, 14, 13.0],
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#2F6C85' : '#5E8CA3',
            'text-halo-color': isDay ? '#D9EDF5' : '#070B12',
            'text-halo-width': 1.5,
          },
        },
        if (!isProtomaps)
          <String, dynamic>{
            'id': 'building_housenumber',
            'type': 'symbol',
            'source': 'karta_basemap',
            'source-layer': 'housenumber',
            'minzoom': 16.0,
            'layout': <String, dynamic>{
              'text-field': <dynamic>['get', 'housenumber'],
              'text-font': <String>['Noto Sans Regular'],
              'text-size': 10.0,
            },
            'paint': <String, dynamic>{
              'text-color': isDay ? '#4A5563' : '#7D8794',
              'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
              'text-halo-width': 1.2,
            },
          },
        <String, dynamic>{
          'id': 'roads_label_minor',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': roadLabelLayer,
          'minzoom': 12.5,
          'filter': minorLabelFilter,
          'layout': <String, dynamic>{
            'symbol-placement': 'line',
            'text-field': <dynamic>[
              'coalesce',
              <dynamic>['get', 'name:en'],
              <dynamic>['get', 'name'],
              <dynamic>['get', 'ref'],
            ],
            'text-font': <String>['Noto Sans Regular'],
            'text-size': 11.0,
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#4A5563' : '#8E96A0',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': isDay ? 1.8 : 1.5,
            'text-opacity': 0.92,
          },
        },
        <String, dynamic>{
          'id': 'roads_label_major',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': roadLabelLayer,
          'minzoom': 9,
          'filter': majorLabelFilter,
          'layout': <String, dynamic>{
            'symbol-placement': 'line',
            'text-field': <dynamic>[
              'coalesce',
              <dynamic>['get', 'name:en'],
              <dynamic>['get', 'name'],
              <dynamic>['get', 'ref'],
            ],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': 12.5,
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#11161C' : '#CBD5E0',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': isDay ? 2.0 : 1.8,
          },
        },
        <String, dynamic>{
          'id': 'roads_shield_expressway',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': roadLabelLayer,
          'minzoom': 7,
          'filter': <dynamic>[
            'all',
            <dynamic>['has', 'ref'],
            <dynamic>['in', isProtomaps ? 'kind' : 'class', 'motorway', 'highway', 'trunk'],
          ],
          'layout': <String, dynamic>{
            'symbol-placement': 'line',
            'symbol-spacing': 260,
            'icon-image': 'karta-shield-expressway',
            'icon-text-fit': 'both',
            'icon-text-fit-padding': <double>[2.5, 6, 2.5, 6],
            'text-field': <dynamic>['get', 'ref'],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': 10.5,
            'text-rotation-alignment': 'viewport',
            'text-pitch-alignment': 'viewport',
          },
          'paint': <String, dynamic>{
            'text-color': '#F4F6F8',
          },
        },
        <String, dynamic>{
          'id': 'roads_shield_federal',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': roadLabelLayer,
          'minzoom': 9,
          'filter': <dynamic>[
            'all',
            <dynamic>['has', 'ref'],
            <dynamic>['in', isProtomaps ? 'kind' : 'class', 'primary', 'secondary', 'major_road'],
          ],
          'layout': <String, dynamic>{
            'symbol-placement': 'line',
            'symbol-spacing': 280,
            'icon-image': 'karta-shield-federal',
            'icon-text-fit': 'both',
            'icon-text-fit-padding': <double>[2.5, 6, 2.5, 6],
            'text-field': <dynamic>['get', 'ref'],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': 10.0,
            'text-rotation-alignment': 'viewport',
            'text-pitch-alignment': 'viewport',
          },
          'paint': <String, dynamic>{
            'text-color': '#F4F6F8',
          },
        },
        <String, dynamic>{
          'id': 'aerodrome_label',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': isProtomaps ? 'pois' : 'aerodrome_label',
          'minzoom': 9,
          'layout': <String, dynamic>{
            'icon-image': 'karta-poi-airport',
            'icon-size': 0.85,
            'text-field': <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': 11.5,
            'text-offset': <double>[0, 1.35],
            'text-anchor': 'top',
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#1D4ED8' : '#7BC4FF',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': 1.8,
          },
        },
        <String, dynamic>{
          'id': 'poi_landmarks',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': isProtomaps ? 'pois' : 'poi',
          'minzoom': 12.0,
          'layout': <String, dynamic>{
            'icon-image': <dynamic>[
              'match',
              <dynamic>['coalesce', <dynamic>['get', isProtomaps ? 'kind' : 'class'], 'landmark'],
              'fuel', 'karta-poi-fuel',
              'charging_station', 'karta-poi-ev',
              'restaurant', 'karta-poi-food',
              'cafe', 'karta-poi-cafe',
              'fast_food', 'karta-poi-food',
              'hospital', 'karta-poi-health',
              'clinic', 'karta-poi-health',
              'pharmacy', 'karta-poi-health',
              'hotel', 'karta-poi-hotel',
              'lodging', 'karta-poi-hotel',
              'school', 'karta-poi-school',
              'university', 'karta-poi-school',
              'college', 'karta-poi-school',
              'bank', 'karta-poi-bank',
              'atm', 'karta-poi-bank',
              'park', 'karta-poi-park',
              'garden', 'karta-poi-park',
              'shop', 'karta-poi-shop',
              'mall', 'karta-poi-shop',
              'supermarket', 'karta-poi-shop',
              'railway', 'karta-poi-transit',
              'bus', 'karta-poi-transit',
              'subway', 'karta-poi-transit',
              'place_of_worship', 'karta-poi-worship',
              'parking', 'karta-poi-parking',
              'karta-poi-pin',
            ],
            'icon-size': 0.78,
            'text-field': <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': <dynamic>['interpolate', <dynamic>['linear'], <dynamic>['zoom'], 12, 10.5, 16, 12.0],
            'text-max-width': 9,
            'text-offset': <double>[0, 1.25],
            'text-anchor': 'top',
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#2B3844' : '#DCE4EC',
            'text-halo-color': isDay ? '#FCFBF8' : '#0D0F12',
            'text-halo-width': 1.8,
          },
        },
        <String, dynamic>{
          'id': 'place_suburb_neighbourhood',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': placeSourceLayer,
          'minzoom': 11,
          'filter': <dynamic>[
            'in',
            isProtomaps ? 'kind' : 'class',
            'suburb',
            'neighbourhood',
            'quarter',
            'village',
            'hamlet',
            'locality',
            'isolated_dwelling',
          ],
          'layout': <String, dynamic>{
            'text-field': <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
            'text-font': <String>['Noto Sans Regular'],
            'text-size': <dynamic>['interpolate', <dynamic>['linear'], <dynamic>['zoom'], 11, 10.5, 15, 13.0],
            'text-max-width': 8,
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#4A5563' : '#9AA5B1',
            'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
            'text-halo-width': 1.8,
          },
        },
        <String, dynamic>{
          'id': 'places_label',
          'type': 'symbol',
          'source': 'karta_basemap',
          'source-layer': placeSourceLayer,
          'layout': <String, dynamic>{
            'text-field': <dynamic>['coalesce', <dynamic>['get', 'name:en'], <dynamic>['get', 'name']],
            'text-font': <String>['Open Sans Semibold'],
            'text-size': <dynamic>['interpolate', <dynamic>['linear'], <dynamic>['zoom'], 5, 11.5, 12, 15.5],
            'text-max-width': 8,
          },
          'paint': <String, dynamic>{
            'text-color': isDay ? '#11161C' : '#F4F6F8',
            'text-halo-color': isDay ? '#F5F2EB' : '#0D0F12',
            'text-halo-width': isDay ? 2.1 : 1.8,
          },
        },
      ],
    };
  }
}

/// Backward-compatible alias for Obsidian Night MapLibre style construction.
abstract final class KartaDarkStyleBuilder {
  static Map<String, dynamic> build({
    required String pmtilesUrl,
    String schema = 'openmaptiles',
    bool enable3DBuildings = true,
  }) {
    return KartaMapStyleBuilder.build(
      pmtilesUrl: pmtilesUrl,
      mode: KartaVisualMode.obsidianNight,
      schema: schema,
      enable3DBuildings: enable3DBuildings,
    );
  }
}
