import 'package:flutter/foundation.dart';
import 'package:karta_api_client/karta_api_client.dart';
import 'package:karta_map_engine/karta_map_engine.dart';
import 'package:karta_navigation_core/karta_navigation_core.dart';

/// Category classification for Karta's clickable Southeast Asian landmarks,
/// international airports, sacred religious sites, and major railway stations.
enum KartaPlaceKind {
  historicalLandmark(wireKind: 'historic', filterGroup: 'landmarks'),
  modernLandmark(wireKind: 'modern', filterGroup: 'landmarks'),
  airport(wireKind: 'airport', filterGroup: 'airports'),
  mosque(wireKind: 'mosque', filterGroup: 'worship'),
  temple(wireKind: 'temple', filterGroup: 'worship'),
  church(wireKind: 'church', filterGroup: 'worship'),
  railHub(wireKind: 'rail', filterGroup: 'transit'),
  trainStation(wireKind: 'rail', filterGroup: 'transit');

  const KartaPlaceKind({
    required this.wireKind,
    required this.filterGroup,
  });

  final String wireKind;
  final String filterGroup;
}

/// Curated or vector-resolved Southeast Asian place record displayed in Karta's
/// interactive travel-guide info card when tapped on the map or selected in search.
@immutable
class KartaFeaturedPlace {
  const KartaFeaturedPlace({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.kind,
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.coordinate,
    required this.summary,
    this.established,
    this.iataCode,
    this.icaoCode,
    this.transitAccess,
    this.highlights = const <String>[],
    this.isUnesco = false,
    this.minZoom = 8.5,
  });

  final String id;
  final String name;
  final String shortLabel;
  final KartaPlaceKind kind;
  final String countryCode;
  final String countryName;
  final String city;
  final Coordinate coordinate;
  final String summary;
  final String? established;
  final String? iataCode;
  final String? icaoCode;
  final String? transitAccess;
  final List<String> highlights;
  final bool isUnesco;
  final double minZoom;

  KartaMapFeaturedPin toMapPin() => KartaMapFeaturedPin(
        id: id,
        name: name,
        shortLabel: shortLabel,
        kind: kind.wireKind,
        countryCode: countryCode,
        coordinate: coordinate,
        iataCode: iataCode,
        minZoom: minZoom,
      );
}

/// Curated Southeast Asian guide covering famous tourist landmarks (historical &
/// modern), major international airports, iconic religious places (mosques,
/// temples, pagodas, churches), and key railway hubs across all 11 SEA countries.
abstract final class SeaFeaturedPlacesCatalog {
  static const List<KartaFeaturedPlace> all = <KartaFeaturedPlace>[
    // =========================================================================
    // MALAYSIA (MY)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'my-klcc',
      name: 'Petronas Twin Towers (KLCC)',
      shortLabel: 'Petronas Towers',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Kuala Lumpur',
      coordinate: Coordinate(lat: 3.1579, lon: 101.7116),
      established: '1998',
      transitAccess: 'KLCC LRT Station (Kelana Jaya Line) · Persiaran KLCC MRT',
      highlights: <String>['451.9 m Twin Towers', 'Level 41 Skybridge', 'KLCC Park & Lake Symphony'],
      minZoom: 5.5,
      summary:
          'Standing 451.9 meters tall, the Petronas Twin Towers remain the world\'s tallest twin skyscrapers and Malaysia\'s defining modern architectural icon. Designed by César Pelli with Islamic geometric eight-pointed star floorplans, the towers feature a dramatic double-deck skybridge and Level 86 observation deck.',
    ),
    KartaFeaturedPlace(
      id: 'my-merdeka118',
      name: 'Merdeka 118',
      shortLabel: 'Merdeka 118',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Kuala Lumpur',
      coordinate: Coordinate(lat: 3.1419, lon: 101.7007),
      established: '2024',
      transitAccess: 'Merdeka MRT Station (Kajang Line) · Maharajalela Monorail',
      highlights: <String>['678.9 m Megatall Spire', '2nd Tallest Building on Earth', 'Adjacent to Stadium Merdeka'],
      minZoom: 9.0,
      summary:
          'Rising 678.9 meters above historic Stadium Merdeka, Merdeka 118 is Southeast Asia\'s tallest skyscraper and the second-tallest structure in the world. Its faceted diamond glass facade echoes traditional Malay songket patterns and the outstretched hand of Malaysia\'s independence proclamation.',
    ),
    KartaFeaturedPlace(
      id: 'my-afamosa',
      name: 'A Famosa Fortress',
      shortLabel: 'A Famosa',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Melaka',
      coordinate: Coordinate(lat: 2.1918, lon: 102.2504),
      established: '1511',
      isUnesco: true,
      transitAccess: 'Melaka Sentral Bus Terminal (15 min drive) · St. Paul\'s Hill Walk',
      highlights: <String>['Porta de Santiago Gate', '16th-Century Fortress', 'UNESCO Historic Core'],
      minZoom: 7.8,
      summary:
          'Built in 1511 under Portuguese admiral Afonso de Albuquerque, A Famosa is among the oldest surviving European architectural remains in Southeast Asia. Its famed Porta de Santiago stone gateway sits at the foot of St. Paul\'s Hill in Melaka\'s UNESCO World Heritage historic zone.',
    ),
    KartaFeaturedPlace(
      id: 'my-georgetown',
      name: 'George Town UNESCO Heritage Core',
      shortLabel: 'George Town Heritage',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Penang',
      coordinate: Coordinate(lat: 5.4149, lon: 100.3375),
      established: '1786',
      isUnesco: true,
      transitAccess: 'Penang Ferry Terminal (Swettenham Pier) · Butterworth ETS Rail',
      highlights: <String>['Armenian Street Murals', 'Peranakan Shophouses', 'Clan Jetties'],
      minZoom: 7.5,
      summary:
          'Inscribed as a UNESCO World Heritage Site in 2008, George Town showcases centuries of Malay, Chinese, Indian, and British Straits heritage. Visitors explore restored pastel shophouses, heritage clan jetties, famous street murals, and world-renowned Penang hawker cuisine.',
    ),
    KartaFeaturedPlace(
      id: 'my-penang-hill',
      name: 'Penang Hill (Bukit Bendera)',
      shortLabel: 'Penang Hill',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Penang',
      coordinate: Coordinate(lat: 5.4244, lon: 100.2688),
      established: '1923',
      transitAccess: 'Penang Hill Funicular Railway (Air Itam Lower Station)',
      highlights: <String>['833 m Peak Panorama', 'Historic Funicular Train', 'The Habitat Rainforest Walk'],
      minZoom: 9.5,
      summary:
          'Rising 833 meters above Penang Island, Penang Hill offers cool highland breezes, 130-million-year-old rainforest canopy walks, and sweeping views across George Town and the Penang Bridge. Accessed by one of the steepest funicular railways in the world.',
    ),
    KartaFeaturedPlace(
      id: 'my-kul',
      name: 'Kuala Lumpur International Airport',
      shortLabel: 'KLIA',
      kind: KartaPlaceKind.airport,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Sepang, Selangor',
      coordinate: Coordinate(lat: 2.7456, lon: 101.7072),
      established: '1998',
      iataCode: 'KUL',
      icaoCode: 'WMKK',
      transitAccess: 'KLIA Ekspres High-Speed Rail (28 min nonstop to KL Sentral)',
      highlights: <String>['Terminal 1 & Terminal 2', 'Indoor Jungle Boardwalk', '28-min Express Rail'],
      minZoom: 5.5,
      summary:
          'Malaysia\'s primary international aviation gateway, designed by architect Kisho Kurokawa around the "Airport in the Forest" concept. Linked directly to downtown Kuala Lumpur via the 160 km/h KLIA Ekspres airport rail line.',
    ),
    KartaFeaturedPlace(
      id: 'my-pen',
      name: 'Penang International Airport',
      shortLabel: 'Penang Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Bayan Lepas, Penang',
      coordinate: Coordinate(lat: 5.2972, lon: 100.2769),
      established: '1935',
      iataCode: 'PEN',
      icaoCode: 'WMKP',
      transitAccess: 'Rapid Penang 401E Direct Bus · Upcoming Mutiara LRT Airport Station',
      highlights: <String>['Northern Malaysia Hub', '16 km to George Town', 'Direct ASEAN & East Asia Flights'],
      minZoom: 7.5,
      summary:
          'Serving Penang and northern Peninsular Malaysia, Bayan Lepas Airport is one of Malaysia\'s oldest and busiest aviation hubs, connecting travelers directly to George Town\'s heritage district, Batu Ferringhi beaches, and regional tech corridors.',
    ),
    KartaFeaturedPlace(
      id: 'my-bki',
      name: 'Kota Kinabalu International Airport',
      shortLabel: 'KK Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Kota Kinabalu, Sabah',
      coordinate: Coordinate(lat: 5.9372, lon: 116.0511),
      established: '1945',
      iataCode: 'BKI',
      icaoCode: 'WBKK',
      transitAccess: 'Tanjung Aru Railway Station (Sabah State Railway) nearby',
      highlights: <String>['Borneo Primary Gateway', 'Mount Kinabalu Access', '8 km to Waterfront'],
      minZoom: 6.5,
      summary:
          'The second-busiest airport in Malaysia and the main international gateway to Sabah and Malaysian Borneo, offering rapid access to Mount Kinabalu National Park, Tunku Abdul Rahman Marine Park islands, and Borneo wildlife sanctuaries.',
    ),
    KartaFeaturedPlace(
      id: 'my-masjid-negara',
      name: 'Masjid Negara (National Mosque of Malaysia)',
      shortLabel: 'Masjid Negara',
      kind: KartaPlaceKind.mosque,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Kuala Lumpur',
      coordinate: Coordinate(lat: 3.1418, lon: 101.6918),
      established: '1965',
      transitAccess: 'Kuala Lumpur KTM Station (3 min walk) · Pasar Seni MRT/LRT',
      highlights: <String>['16-Pointed Star Umbrella Dome', '73 m Minaret', '15,000 Capacity'],
      minZoom: 9.2,
      summary:
          'Malaysia\'s iconic National Mosque combines modernist Malay architecture with tranquil reflecting pools and gardens. Its signature pleated blue roof resembles an open royal umbrella symbolizing unity, with a soaring 73-meter minaret beside the heritage KL Railway Station.',
    ),
    KartaFeaturedPlace(
      id: 'my-masjid-putra',
      name: 'Masjid Putra (Putra Mosque)',
      shortLabel: 'Masjid Putra',
      kind: KartaPlaceKind.mosque,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Putrajaya',
      coordinate: Coordinate(lat: 2.9361, lon: 101.6893),
      established: '1999',
      transitAccess: 'Putrajaya Sentral ERL & MRT Putrajaya Line',
      highlights: <String>['Rose-Tinted Granite Dome', '116 m Five-Tier Minaret', 'Putrajaya Lakefront'],
      minZoom: 9.4,
      summary:
          'Constructed from rose-tinted granite along the scenic shores of Putrajaya Lake, Masjid Putra blends Malay, Persian, and Middle Eastern craftsmanship. Its towering 116-meter minaret features five tiers representing the Five Pillars of Islam.',
    ),
    KartaFeaturedPlace(
      id: 'my-masjid-kapitan-keling',
      name: 'Masjid Kapitan Keling',
      shortLabel: 'Kapitan Keling Mosque',
      kind: KartaPlaceKind.mosque,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'George Town, Penang',
      coordinate: Coordinate(lat: 5.4169, lon: 100.3372),
      established: '1801',
      isUnesco: true,
      transitAccess: 'George Town Street of Harmony · Penang Ferry Pier (10 min walk)',
      highlights: <String>['Mughal-Style Yellow Domes', 'Penang\'s Oldest Mosque', 'Street of Harmony Landmark'],
      minZoom: 10.5,
      summary:
          'Founded in 1801 by Indian Muslim traders led by Cauder Mohuddeen, Masjid Kapitan Keling is Penang\'s largest historic mosque. Its gleaming whitewashed arches, Mughal domes, and grand minaret anchor George Town\'s famous Street of Harmony.',
    ),
    KartaFeaturedPlace(
      id: 'my-batu-caves',
      name: 'Batu Caves & Sri Subramaniar Swamy Temple',
      shortLabel: 'Batu Caves',
      kind: KartaPlaceKind.temple,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Gombak, Selangor',
      coordinate: Coordinate(lat: 3.2379, lon: 101.6840),
      established: '1891',
      transitAccess: 'Batu Caves KTM Komuter Terminal (Seremban Line)',
      highlights: <String>['272 Rainbow Steps', '42.7 m Lord Murugan Statue', '400M-Year Limestone Caves'],
      minZoom: 8.8,
      summary:
          'One of the most sacred Hindu shrines outside India, Batu Caves rises inside towering 400-million-year-old limestone cliffs north of Kuala Lumpur. Visitors ascend 272 vividly painted steps past the golden 42.7-meter Lord Murugan statue into the dramatic Cathedral Cave.',
    ),
    KartaFeaturedPlace(
      id: 'my-kek-lok-si',
      name: 'Kek Lok Si Temple',
      shortLabel: 'Kek Lok Si',
      kind: KartaPlaceKind.temple,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Air Itam, Penang',
      coordinate: Coordinate(lat: 5.3995, lon: 100.2737),
      established: '1891',
      transitAccess: 'Rapid Penang 201/203/204 · Near Penang Hill Funicular',
      highlights: <String>['Largest Buddhist Temple in MY', '7-Tier Pagoda of 10,000 Buddhas', '36.5 m Bronze Kuan Yin'],
      minZoom: 9.8,
      summary:
          'Perched on the slopes of Crane Hill in Air Itam, Kek Lok Si is Malaysia\'s largest Buddhist temple complex. Its iconic seven-story Ban Po Thar pagoda harmonizes Chinese, Thai, and Burmese architectural styles beneath a towering bronze Kuan Yin pavilion.',
    ),
    KartaFeaturedPlace(
      id: 'my-christ-church',
      name: 'Christ Church Melaka',
      shortLabel: 'Christ Church',
      kind: KartaPlaceKind.church,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Melaka',
      coordinate: Coordinate(lat: 2.1944, lon: 102.2494),
      established: '1753',
      isUnesco: true,
      transitAccess: 'Dutch Square (Red Square) · Jonker Walk (2 min walk)',
      highlights: <String>['Oldest Functioning Protestant Church in MY', 'Iconic Terracotta-Red Brick', '18th-Century Dutch Heritage'],
      minZoom: 9.6,
      summary:
          'Completed in 1753 during the Dutch era, Christ Church Melaka anchors Melaka\'s vibrant terracotta-red Dutch Square. Built with Dutch bricks shipped as ballast and local laterite blocks, it retains original handmade wooden pews and 18th-century granite tombstones.',
    ),
    KartaFeaturedPlace(
      id: 'my-kl-sentral',
      name: 'KL Sentral Station',
      shortLabel: 'KL Sentral',
      kind: KartaPlaceKind.railHub,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Kuala Lumpur',
      coordinate: Coordinate(lat: 3.1342, lon: 101.6861),
      established: '2001',
      transitAccess: 'KTM ETS · KLIA Ekspres · LRT Kelana Jaya · MRT Muzium Negara · Monorail',
      highlights: <String>['Malaysia\'s Main Rail Interchange', '28-min Nonstop KLIA Ekspres', 'ETS Intercity North–South'],
      minZoom: 9.2,
      summary:
          'Malaysia\'s largest multimodal railway station and primary transit hub, uniting KTM ETS electric intercity trains, KLIA Ekspres airport rail, KTM Komuter, Kelana Jaya LRT, KL Monorail, and Kajang MRT lines under one roof.',
    ),
    KartaFeaturedPlace(
      id: 'my-butterworth-sentral',
      name: 'Butterworth Sentral (Penang Sentral)',
      shortLabel: 'Butterworth Sentral',
      kind: KartaPlaceKind.railHub,
      countryCode: 'MY',
      countryName: 'Malaysia',
      city: 'Butterworth, Penang',
      coordinate: Coordinate(lat: 5.3941, lon: 100.3652),
      established: '2018',
      transitAccess: 'KTM ETS & Komuter Utara · Rapid Ferry to George Town',
      highlights: <String>['Direct Ferry to Penang Island', 'KTM ETS High-Speed to KL & Padang Besar', 'Northern Rail Gateway'],
      minZoom: 9.5,
      summary:
          'Northern Peninsular Malaysia\'s premier rail-and-ferry interchange linking KTM ETS electric trains and Komuter Utara directly to the Penang Island ferry terminal and regional bus concourse.',
    ),

    // =========================================================================
    // SINGAPORE (SG)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'sg-mbs',
      name: 'Marina Bay Sands',
      shortLabel: 'Marina Bay Sands',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Marina Bay',
      coordinate: Coordinate(lat: 1.2834, lon: 103.8607),
      established: '2010',
      transitAccess: 'Bayfront MRT Station (CE1 / DT16 — Circle & Downtown Lines)',
      highlights: <String>['Sands SkyPark Deck', '57th-Floor Infinity Pool', 'ArtScience Museum'],
      minZoom: 6.0,
      summary:
          'Crowned by the cantilevered Sands SkyPark spanning three 55-story towers, Marina Bay Sands is Singapore\'s world-famous waterfront landmark. Its promenade frames nightly Spectra light-and-water shows across Marina Bay.',
    ),
    KartaFeaturedPlace(
      id: 'sg-gardens',
      name: 'Gardens by the Bay',
      shortLabel: 'Gardens by the Bay',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Marina South',
      coordinate: Coordinate(lat: 1.2816, lon: 103.8636),
      established: '2012',
      transitAccess: 'Gardens by the Bay MRT (TE22) · Bayfront MRT (CE1/DT16)',
      highlights: <String>['Supertree Grove Canopy', 'Cloud Forest Indoor Waterfall', 'Flower Dome Conservatory'],
      minZoom: 9.6,
      summary:
          'Spanning 101 hectares of futuristic waterfront parkland, Gardens by the Bay showcases vertical solar-powered Supertrees, the misty Cloud Forest mountain dome, and the world\'s largest columnless glass greenhouse.',
    ),
    KartaFeaturedPlace(
      id: 'sg-sin',
      name: 'Singapore Changi Airport',
      shortLabel: 'Changi Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Changi',
      coordinate: Coordinate(lat: 1.3644, lon: 103.9915),
      established: '1981',
      iataCode: 'SIN',
      icaoCode: 'WSSS',
      transitAccess: 'Changi Airport MRT Station (CG2 — East-West Line)',
      highlights: <String>['Jewel 40 m Rain Vortex', '4 Linked Terminals', 'World\'s Most Awarded Airport'],
      minZoom: 5.5,
      summary:
          'Consistently ranked among the world\'s finest international airports, Changi Airport connects Southeast Asia to over 100 global cities and features Jewel Changi—home to the 40-meter HSBC Rain Vortex indoor waterfall and terraced forest valley.',
    ),
    KartaFeaturedPlace(
      id: 'sg-masjid-sultan',
      name: 'Masjid Sultan (Sultan Mosque)',
      shortLabel: 'Sultan Mosque',
      kind: KartaPlaceKind.mosque,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Kampong Glam',
      coordinate: Coordinate(lat: 1.3023, lon: 103.8590),
      established: '1824',
      transitAccess: 'Bugis MRT Station (EW12 / DT14 — 5 min walk)',
      highlights: <String>['Massive Golden Domes', 'National Monument (1975)', 'Arab Street Heritage District'],
      minZoom: 10.2,
      summary:
          'Constructed originally in 1824 for Sultan Hussein Shah and rebuilt in 1932 in Indo-Saracenic style, Masjid Sultan is the spiritual heart of Singapore\'s Muslim community. Its gleaming golden domes are encircled by bases decorated with glass bottle ends donated by local worshippers.',
    ),
    KartaFeaturedPlace(
      id: 'sg-buddha-tooth',
      name: 'Buddha Tooth Relic Temple & Museum',
      shortLabel: 'Buddha Tooth Temple',
      kind: KartaPlaceKind.temple,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Chinatown',
      coordinate: Coordinate(lat: 1.2815, lon: 103.8443),
      established: '2007',
      transitAccess: 'Maxwell MRT (TE18) · Chinatown MRT (NE4/DT19)',
      highlights: <String>['Tang Dynasty Architecture', 'Sacred Relic Stupa', 'Rooftop Orchid Garden & Prayer Wheel'],
      minZoom: 10.5,
      summary:
          'Modeled after Tang Dynasty Buddhist architecture in the heart of Singapore\'s Chinatown, this crimson-and-gold four-story temple houses a revered sacred tooth relic chamber, museum galleries, and a serene rooftop prayer wheel garden.',
    ),
    KartaFeaturedPlace(
      id: 'sg-st-andrews',
      name: 'St Andrew\'s Cathedral',
      shortLabel: 'St Andrew\'s Cathedral',
      kind: KartaPlaceKind.church,
      countryCode: 'SG',
      countryName: 'Singapore',
      city: 'Civic District',
      coordinate: Coordinate(lat: 1.2923, lon: 103.8522),
      established: '1861',
      transitAccess: 'City Hall MRT Interchange (NS25 / EW13 — direct exit)',
      highlights: <String>['Neo-Gothic White Spire', 'Singapore\'s Largest Cathedral', 'Madras Chunam Plasterwork'],
      minZoom: 10.5,
      summary:
          'Singapore\'s oldest Anglican house of worship and largest cathedral, distinguished by its gleaming white Madras chunam finish, lancet stained-glass windows, and peaceful lawn beside City Hall MRT.',
    ),

    // =========================================================================
    // BRUNEI DARUSSALAM (BN)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'bn-kampong-ayer',
      name: 'Kampong Ayer (Water Village)',
      shortLabel: 'Kampong Ayer',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'BN',
      countryName: 'Brunei Darussalam',
      city: 'Bandar Seri Begawan',
      coordinate: Coordinate(lat: 4.8825, lon: 114.9425),
      established: '10th Century',
      transitAccess: 'Brunei River Water Taxi Jetty (1 min crossing from Waterfront)',
      highlights: <String>['World\'s Largest Water Settlement', '38 km Wooden Boardwalks', 'Cultural & Tourism Gallery'],
      minZoom: 7.5,
      summary:
          'Known historically as the "Venice of the East", Kampong Ayer has thrived above the Brunei River for over a thousand years. Stilted neighborhoods connected by wooden walkways include mosques, schools, clinics, and heritage galleries accessible by river water taxi.',
    ),
    KartaFeaturedPlace(
      id: 'bn-omar-ali',
      name: 'Omar Ali Saifuddien Mosque',
      shortLabel: 'Omar Ali Mosque',
      kind: KartaPlaceKind.mosque,
      countryCode: 'BN',
      countryName: 'Brunei Darussalam',
      city: 'Bandar Seri Begawan',
      coordinate: Coordinate(lat: 4.8895, lon: 114.9392),
      established: '1958',
      transitAccess: 'Central Bus Terminal (5 min walk) · Yayasan Waterfront',
      highlights: <String>['24-Karat Pure Gold Main Dome', 'Ceremonial Stone Barge Lagoon', 'Italian Marble Minarets'],
      minZoom: 6.5,
      summary:
          'Widely celebrated as one of the most breathtaking mosques in Asia-Pacific, Omar Ali Saifuddien Mosque pairs Mughal elegance with Malay craftsmanship. Its pure gold dome and 16th-century royal barge replica glow magnificently across its tranquil artificial lagoon.',
    ),
    KartaFeaturedPlace(
      id: 'bn-jame-asr',
      name: 'Jame\' Asr Hassanil Bolkiah Mosque',
      shortLabel: 'Jame\' Asr Mosque',
      kind: KartaPlaceKind.mosque,
      countryCode: 'BN',
      countryName: 'Brunei Darussalam',
      city: 'Kiarong, Bandar Seri Begawan',
      coordinate: Coordinate(lat: 4.9022, lon: 114.9228),
      established: '1994',
      transitAccess: 'Gadong–Kiulap Main Corridor (10 min from BWN Airport)',
      highlights: <String>['29 Golden Domes', 'Brunei\'s Largest Mosque', 'Illuminated Fountain Gardens'],
      minZoom: 9.2,
      summary:
          'Built to commemorate the 25th year of Sultan Hassanal Bolkiah\'s reign, Brunei\'s largest mosque is crowned with 29 golden domes honoring the nation\'s 29th Sultan and surrounded by serene landscaped gardens.',
    ),
    KartaFeaturedPlace(
      id: 'bn-bwn',
      name: 'Brunei International Airport',
      shortLabel: 'Brunei Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'BN',
      countryName: 'Brunei Darussalam',
      city: 'Berakas, Bandar Seri Begawan',
      coordinate: Coordinate(lat: 4.9442, lon: 114.9283),
      established: '1974',
      iataCode: 'BWN',
      icaoCode: 'WBSB',
      transitAccess: '12 min drive to Bandar Seri Begawan City Centre',
      highlights: <String>['Royal Brunei Airlines Hub', 'Islamic Geometric Terminal', 'Borneo Aviation Hub'],
      minZoom: 6.5,
      summary:
          'Brunei Darussalam\'s sole international aviation hub, welcoming travelers to Bandar Seri Begawan, Ulu Temburong rainforest canopy walkways, and Borneo connections.',
    ),

    // =========================================================================
    // INDONESIA (ID)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'id-monas',
      name: 'Monas (National Monument)',
      shortLabel: 'Monas',
      kind: KartaPlaceKind.modernLandmark,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Central Jakarta',
      coordinate: Coordinate(lat: -6.1754, lon: 106.8272),
      established: '1975',
      transitAccess: 'Stasiun Gambir (KAI Intercity) · Stasiun Juanda (KRL Commuter)',
      highlights: <String>['132 m Obelisk Tower', 'Gold-Foil Independence Flame', 'Panoramic City Observation Deck'],
      minZoom: 6.0,
      summary:
          'Towering 132 meters in the center of Merdeka Square, the National Monument (Monas) commemorates Indonesia\'s struggle for independence. Crowned with a bronze flame coated in 50 kg of gold foil, its elevator lifts visitors to a 360° view of Jakarta.',
    ),
    KartaFeaturedPlace(
      id: 'id-borobudur',
      name: 'Borobudur Temple (Candi Borobudur)',
      shortLabel: 'Borobudur',
      kind: KartaPlaceKind.temple,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Magelang, Central Java',
      coordinate: Coordinate(lat: -7.6079, lon: 110.2038),
      established: '9th Century',
      isUnesco: true,
      transitAccess: 'Yogyakarta Tugu Railway Station (1 hr drive) · DAMRI Direct Shuttle',
      highlights: <String>['World\'s Largest Buddhist Temple', '504 Buddha Statues & 72 Stupas', '2,672 Carved Relief Panels'],
      minZoom: 5.5,
      summary:
          'Built in the 9th century under the Sailendra Dynasty, Borobudur is the largest Buddhist monument on Earth. Rising across nine stacked volcanic-stone terraces topped by bell-shaped stupas overlooking misty Javanese volcanoes, it is a crowning UNESCO World Heritage treasure.',
    ),
    KartaFeaturedPlace(
      id: 'id-prambanan',
      name: 'Prambanan Temple Compounds',
      shortLabel: 'Prambanan',
      kind: KartaPlaceKind.temple,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Sleman, Yogyakarta',
      coordinate: Coordinate(lat: -7.7520, lon: 110.4914),
      established: '9th Century',
      isUnesco: true,
      transitAccess: 'Brambanan KRL Commuter Rail Station (10 min walk)',
      highlights: <String>['Largest Hindu Temple in Indonesia', '47 m Shiva Spire', 'Ramayana Ballet Amphitheatre'],
      minZoom: 7.8,
      summary:
          'Dedicated to the Hindu Trimurti—Shiva, Vishnu, and Brahma—the soaring 47-meter spires of Prambanan form the grandest Hindu temple complex in Indonesia and one of Southeast Asia\'s supreme architectural masterpieces.',
    ),
    KartaFeaturedPlace(
      id: 'id-tanah-lot',
      name: 'Pura Tanah Lot',
      shortLabel: 'Tanah Lot',
      kind: KartaPlaceKind.temple,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Tabanan, Bali',
      coordinate: Coordinate(lat: -8.6212, lon: 115.0868),
      established: '16th Century',
      transitAccess: '45 min from Seminyak / Canggu · 1 hr from Ngurah Rai Airport',
      highlights: <String>['Ocean-Rock Sea Temple', 'Dramatic Indian Ocean Sunsets', 'Sacred Balinese Pilgrimage Site'],
      minZoom: 7.8,
      summary:
          'Perched dramatically atop an offshore wave-carved rock formation along Bali\'s southwest coast, Pura Tanah Lot is one of Bali\'s seven revered sea temples and an unforgettable sunset pilgrimage landmark.',
    ),
    KartaFeaturedPlace(
      id: 'id-istiqlal',
      name: 'Istiqlal Mosque (Masjid Istiqlal)',
      shortLabel: 'Istiqlal Mosque',
      kind: KartaPlaceKind.mosque,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Central Jakarta',
      coordinate: Coordinate(lat: -6.1702, lon: 106.8314),
      established: '1978',
      transitAccess: 'Stasiun Juanda (KRL Commuter Line — 3 min walk)',
      highlights: <String>['Largest Mosque in Southeast Asia', '200,000 Worshipper Capacity', 'Tunnel of Friendship to Cathedral'],
      minZoom: 8.8,
      summary:
          'Southeast Asia\'s largest mosque and one of the biggest in the world, Masjid Istiqlal ("Independence Mosque") features a 45-meter stainless-steel dome symbolizing 1945 independence and connects directly to Jakarta Cathedral via the Tunnel of Friendship.',
    ),
    KartaFeaturedPlace(
      id: 'id-jakarta-cathedral',
      name: 'Jakarta Cathedral (Gereja Katedral)',
      shortLabel: 'Jakarta Cathedral',
      kind: KartaPlaceKind.church,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Central Jakarta',
      coordinate: Coordinate(lat: -6.1692, lon: 106.8331),
      established: '1901',
      transitAccess: 'Stasiun Juanda (KRL Commuter Line — 4 min walk)',
      highlights: <String>['Twin 60 m Neo-Gothic Spires', 'Directly Opposite Istiqlal Mosque', 'Heritage Museum Inside'],
      minZoom: 9.8,
      summary:
          'Consecrated in 1901 in soaring Neo-Gothic style, the Cathedral of Our Lady of the Assumption stands directly across from Istiqlal Mosque as an enduring symbol of Indonesia\'s religious harmony.',
    ),
    KartaFeaturedPlace(
      id: 'id-cgk',
      name: 'Soekarno-Hatta International Airport',
      shortLabel: 'Soekarno-Hatta',
      kind: KartaPlaceKind.airport,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Tangerang, Greater Jakarta',
      coordinate: Coordinate(lat: -6.1256, lon: 106.6559),
      established: '1985',
      iataCode: 'CGK',
      icaoCode: 'WIII',
      transitAccess: 'KAI Bandara Airport Railink (45 min to BNI City / Manggarai)',
      highlights: <String>['Indonesia\'s Busiest Gateway', 'Javanese Joglo Pavilions', 'Direct Airport Railink'],
      minZoom: 5.5,
      summary:
          'Serving Greater Jakarta and the Indonesian archipelago, Soekarno-Hatta International Airport blends tropical courtyard pavilions in Terminals 1–2 with the expansive modern Terminal 3 hub, linked to central Jakarta by Airport Railink.',
    ),
    KartaFeaturedPlace(
      id: 'id-dps',
      name: 'I Gusti Ngurah Rai International Airport',
      shortLabel: 'Bali Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'Badung, Bali',
      coordinate: Coordinate(lat: -8.7482, lon: 115.1672),
      established: '1931',
      iataCode: 'DPS',
      icaoCode: 'WADD',
      transitAccess: '15 min to Kuta / Jimbaran · Direct Bali Mandara Over-Water Tollway',
      highlights: <String>['Bali\'s International Gateway', 'Coastal Peninsula Runway', 'Balinese Split-Gate Terminal'],
      minZoom: 6.0,
      summary:
          'Bali\'s sole international airport, renowned for its dramatic coastal runway extending into the Indian Ocean and traditional Balinese temple-inspired terminal architecture.',
    ),
    KartaFeaturedPlace(
      id: 'id-halim-whoosh',
      name: 'Stasiun Halim (Whoosh High-Speed Rail)',
      shortLabel: 'Halim Whoosh HSR',
      kind: KartaPlaceKind.railHub,
      countryCode: 'ID',
      countryName: 'Indonesia',
      city: 'East Jakarta',
      coordinate: Coordinate(lat: -6.2458, lon: 106.8858),
      established: '2023',
      transitAccess: 'Whoosh 350 km/h HSR (Jakarta–Bandung in 45 min) · LRT Jabodebek',
      highlights: <String>['Southeast Asia\'s First 350 km/h HSR', 'Jakarta to Bandung in 45 min', 'Direct LRT Jabodebek Link'],
      minZoom: 9.2,
      summary:
          'The Jakarta terminus of Whoosh, Southeast Asia\'s first high-speed railway operating at 350 km/h between Jakarta and Bandung, seamlessly integrated with the LRT Jabodebek metro line.',
    ),

    // =========================================================================
    // THAILAND (TH)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'th-grand-palace',
      name: 'The Grand Palace & Wat Phra Kaew',
      shortLabel: 'Grand Palace',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Bangkok',
      coordinate: Coordinate(lat: 13.7500, lon: 100.4913),
      established: '1782',
      transitAccess: 'Sanam Chai MRT Station (Blue Line) · Tha Chang Chao Phraya Pier',
      highlights: <String>['Temple of the Emerald Buddha', 'Gilded Royal Pavilions', 'Chao Phraya Riverbank'],
      minZoom: 5.8,
      summary:
          'Built in 1782 as the official royal residence of the Kings of Siam, Bangkok\'s Grand Palace dazzles with gilded spires, intricate mosaic stupas, and Wat Phra Kaew—home to Thailand\'s most sacred jadeite Emerald Buddha.',
    ),
    KartaFeaturedPlace(
      id: 'th-wat-arun',
      name: 'Wat Arun (Temple of Dawn)',
      shortLabel: 'Wat Arun',
      kind: KartaPlaceKind.temple,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Bangkok Yai, Bangkok',
      coordinate: Coordinate(lat: 13.7437, lon: 100.4888),
      established: '17th Century',
      transitAccess: 'Itsaraphap MRT Station (Blue Line) · Cross-River Ferry from Tha Tien',
      highlights: <String>['70 m Porcelain-Encrusted Prang', 'Iconic Chao Phraya Silhouette', 'Sunset & Night Illumination'],
      minZoom: 9.2,
      summary:
          'Rising 70 meters along the west bank of the Chao Phraya River, Wat Arun\'s soaring Khmer-style central prang is encrusted with thousands of colorful Chinese porcelain fragments that shimmer at dawn and twilight.',
    ),
    KartaFeaturedPlace(
      id: 'th-wat-pho',
      name: 'Wat Pho (Temple of the Reclining Buddha)',
      shortLabel: 'Wat Pho',
      kind: KartaPlaceKind.temple,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Phra Nakhon, Bangkok',
      coordinate: Coordinate(lat: 13.7465, lon: 100.4930),
      established: '1788',
      transitAccess: 'Sanam Chai MRT Station (Blue Line — 4 min walk)',
      highlights: <String>['46 m Gold-Plated Reclining Buddha', 'Birthplace of Traditional Thai Massage', 'Over 1,000 Buddha Images'],
      minZoom: 10.2,
      summary:
          'Just south of the Grand Palace, Wat Pho houses the awe-inspiring 46-meter gilded Reclining Buddha with mother-of-pearl inlaid feet and is revered as Thailand\'s historic birthplace of traditional Thai massage.',
    ),
    KartaFeaturedPlace(
      id: 'th-ayutthaya',
      name: 'Historic City of Ayutthaya',
      shortLabel: 'Ayutthaya',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Phra Nakhon Si Ayutthaya',
      coordinate: Coordinate(lat: 14.3569, lon: 100.5674),
      established: '1350',
      isUnesco: true,
      transitAccess: 'Ayutthaya Railway Station (SRT Northern Line — 1 hr from Bangkok)',
      highlights: <String>['Wat Mahathat Tree-Root Buddha', 'Former Siamese Capital', 'UNESCO Archaeological Park'],
      minZoom: 7.4,
      summary:
          'Founded in 1350 as the second capital of the Siamese Kingdom, Ayutthaya\'s island archaeological park preserves monumental red-brick prangs, towering stone stupas, and the famed Buddha head entwined within banyan roots at Wat Mahathat.',
    ),
    KartaFeaturedPlace(
      id: 'th-wat-rong-khun',
      name: 'Wat Rong Khun (White Temple)',
      shortLabel: 'White Temple',
      kind: KartaPlaceKind.temple,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Chiang Rai',
      coordinate: Coordinate(lat: 19.8241, lon: 99.7632),
      established: '1997',
      transitAccess: '13 km south of Chiang Rai City along Route 1',
      highlights: <String>['Mirrored White Plaster Architecture', 'Bridge of Rebirth', 'Contemporary Buddhist Art'],
      minZoom: 7.5,
      summary:
          'Conceived by renowned Thai artist Chalermchai Kositpipat, the shimmering white-and-mirror Wat Rong Khun reimagines classical Lanna Buddhist temple artistry into one of northern Thailand\'s most photographed cultural icons.',
    ),
    KartaFeaturedPlace(
      id: 'th-bkk',
      name: 'Suvarnabhumi International Airport',
      shortLabel: 'Suvarnabhumi',
      kind: KartaPlaceKind.airport,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Samut Prakan, Bangkok',
      coordinate: Coordinate(lat: 13.6900, lon: 100.7501),
      established: '2006',
      iataCode: 'BKK',
      icaoCode: 'VTBS',
      transitAccess: 'Bangkok Airport Rail Link (26 min directly to Phaya Thai BTS)',
      highlights: <String>['Thailand\'s Main Global Hub', 'Iconic Steel-and-Glass Concourse', 'Direct Airport Rail Link'],
      minZoom: 5.5,
      summary:
          'Thailand\'s primary international gateway, featuring one of the world\'s tallest air traffic control towers, sweeping Helmut Jahn architecture, and seamless Airport Rail Link transfers into central Bangkok.',
    ),
    KartaFeaturedPlace(
      id: 'th-hkt',
      name: 'Phuket International Airport',
      shortLabel: 'Phuket Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Thalang, Phuket',
      coordinate: Coordinate(lat: 8.1132, lon: 98.3169),
      established: '1956',
      iataCode: 'HKT',
      icaoCode: 'VTSP',
      transitAccess: 'Phuket Smart Bus to Patong, Kata & Rawai · Mai Khao Beachfront',
      highlights: <String>['Andaman Sea Island Gateway', 'Famous Mai Khao Beach Approach', 'Direct Global Flights'],
      minZoom: 6.5,
      summary:
          'Southern Thailand\'s premier tourist airport, famous for jet approaches directly over golden Mai Khao Beach and serving Phuket, Phang Nga Bay, and the Andaman islands.',
    ),
    KartaFeaturedPlace(
      id: 'th-krung-thep-aphiwat',
      name: 'Krung Thep Aphiwat Central Terminal',
      shortLabel: 'Krung Thep Aphiwat',
      kind: KartaPlaceKind.railHub,
      countryCode: 'TH',
      countryName: 'Thailand',
      city: 'Chatuchak, Bangkok',
      coordinate: Coordinate(lat: 13.8037, lon: 100.5403),
      established: '2021',
      transitAccess: 'Bang Sue MRT (Blue Line) · SRT Red Line · Intercity Trains to Chiang Mai & Hat Yai',
      highlights: <String>['Southeast Asia\'s Largest Rail Terminal', '26 Rail Platforms', 'Direct SRT Red Line to DMK'],
      minZoom: 9.0,
      summary:
          'Southeast Asia\'s largest railway terminal with 26 platforms, serving as Bangkok\'s modern gateway for intercity express trains to Chiang Mai, Nong Khai (Laos border), and southern Thailand toward Malaysia.',
    ),

    // =========================================================================
    // PHILIPPINES (PH)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'ph-intramuros',
      name: 'Intramuros & Fort Santiago',
      shortLabel: 'Intramuros',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Manila',
      coordinate: Coordinate(lat: 14.5942, lon: 120.9703),
      established: '1571',
      transitAccess: 'Central Terminal LRT-1 Station (12 min walk)',
      highlights: <String>['16th-Century Walled City', 'José Rizal Shrine', 'Cobblestone Heritage Plaza'],
      minZoom: 6.5,
      summary:
          'Established in 1571 along the Pasig River and Manila Bay, the Walled City of Intramuros preserves Spanish-colonial stone ramparts, Fort Santiago\'s riverside citadel, and the poignant shrine to Philippine national hero Dr. José Rizal.',
    ),
    KartaFeaturedPlace(
      id: 'ph-san-agustin',
      name: 'San Agustin Church',
      shortLabel: 'San Agustin Church',
      kind: KartaPlaceKind.church,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Intramuros, Manila',
      coordinate: Coordinate(lat: 14.5892, lon: 120.9752),
      established: '1607',
      isUnesco: true,
      transitAccess: 'Central Terminal LRT-1 · Intramuros Heritage Core',
      highlights: <String>['Oldest Stone Church in the Philippines', 'UNESCO Baroque Churches Site', 'Trompe-l\'œil Painted Vaults'],
      minZoom: 9.2,
      summary:
          'Completed in 1607, San Agustin Church is the oldest surviving stone church in the Philippines and a UNESCO World Heritage Baroque landmark, famous for its earthquake-resistant architecture, trompe-l\'œil frescoed ceiling, and historic monastery museum.',
    ),
    KartaFeaturedPlace(
      id: 'ph-santo-nino',
      name: 'Basilica Minore del Santo Niño',
      shortLabel: 'Santo Niño Basilica',
      kind: KartaPlaceKind.church,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Cebu City',
      coordinate: Coordinate(lat: 10.2942, lon: 123.9021),
      established: '1565',
      transitAccess: 'Cebu Downtown · Adjacent to Magellan\'s Cross Pavilion',
      highlights: <String>['Oldest Catholic Church in the PH', 'Home of Santo Niño de Cebú', 'Steps from Magellan\'s Cross'],
      minZoom: 8.2,
      summary:
          'Founded in 1565 on the exact site where the Santo Niño image was discovered, this coral-stone basilica in downtown Cebu is the spiritual heart of the Visayas and stands steps away from Magellan\'s Cross.',
    ),
    KartaFeaturedPlace(
      id: 'ph-chocolate-hills',
      name: 'Chocolate Hills',
      shortLabel: 'Chocolate Hills',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Carmen, Bohol',
      coordinate: Coordinate(lat: 9.8297, lon: 124.1397),
      established: 'UNESCO Global Geopark',
      isUnesco: true,
      transitAccess: '55 km inland from Tagbilaran Port & Bohol–Panglao Airport',
      highlights: <String>['Over 1,260 Symmetrical Limestone Cones', 'UNESCO Global Geopark', 'Panoramic Carmen Viewdeck'],
      minZoom: 7.2,
      summary:
          'One of the Philippines\' most extraordinary geological wonders, consisting of more than 1,260 grass-covered limestone mounds that turn rich chocolate-brown during the dry season across central Bohol.',
    ),
    KartaFeaturedPlace(
      id: 'ph-mnl',
      name: 'Ninoy Aquino International Airport',
      shortLabel: 'Manila NAIA',
      kind: KartaPlaceKind.airport,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Pasay / Parañaque, Metro Manila',
      coordinate: Coordinate(lat: 14.5086, lon: 121.0198),
      established: '1948',
      iataCode: 'MNL',
      icaoCode: 'RPLL',
      transitAccess: 'NAIAX Elevated Expressway · P2P Airport Bus to Makati & BGC · LRT-1 Baclaran',
      highlights: <String>['Philippines Primary Gateway', '4 Passenger Terminals', 'Direct NAIAX Skyway Link'],
      minZoom: 5.5,
      summary:
          'The primary international aviation gateway serving Metro Manila and Luzon, connecting the Philippine archipelago to global destinations across Asia, North America, the Middle East, and Oceania.',
    ),
    KartaFeaturedPlace(
      id: 'ph-ceb',
      name: 'Mactan-Cebu International Airport',
      shortLabel: 'Cebu Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'PH',
      countryName: 'Philippines',
      city: 'Lapu-Lapu City, Cebu',
      coordinate: Coordinate(lat: 10.3075, lon: 123.9794),
      established: '1966',
      iataCode: 'CEB',
      icaoCode: 'RPVM',
      transitAccess: 'CCLEX Bridge & Marcelo Fernan Bridge to Cebu City · MyBus Shuttle',
      highlights: <String>['Award-Winning Timber Resort Terminal', 'Visayas & Palawan Gateway', 'Mactan Island Coast'],
      minZoom: 6.5,
      summary:
          'Celebrated for its soaring wave-shaped glulam timber roof inspired by Philippine resort culture, Mactan-Cebu International Airport is the main hub for the Visayas, Bohol, and southern Philippines.',
    ),

    // =========================================================================
    // VIETNAM (VN)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'vn-halong',
      name: 'Ha Long Bay',
      shortLabel: 'Ha Long Bay',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Quang Ninh',
      coordinate: Coordinate(lat: 20.9101, lon: 107.1839),
      established: 'UNESCO Site (1994)',
      isUnesco: true,
      transitAccess: 'Ha Long–Hai Phong Expressway (2.5 hrs from Hanoi) · Tuan Chau Marina',
      highlights: <String>['1,600+ Emerald Limestone Karsts', 'Sung Sot Cave & Ti Top Island', 'Overnight Heritage Cruises'],
      minZoom: 5.8,
      summary:
          'Famed for more than 1,600 dramatic limestone monoliths rising out of emerald waters in the Gulf of Tonkin, Ha Long Bay is Vietnam\'s most celebrated UNESCO World Heritage natural seascape.',
    ),
    KartaFeaturedPlace(
      id: 'vn-hoian',
      name: 'Hoi An Ancient Town',
      shortLabel: 'Hoi An',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Quang Nam',
      coordinate: Coordinate(lat: 15.8770, lon: 108.3264),
      established: '15th Century',
      isUnesco: true,
      transitAccess: '45 min south of Da Nang Railway Station & Da Nang Airport',
      highlights: <String>['Japanese Covered Bridge (1593)', 'Lantern-Lit Thu Bon River', 'Preserved Trading Port'],
      minZoom: 6.8,
      summary:
          'Once a flourishing 15th–19th century Southeast Asian trading port, Hoi An enchants visitors with ochre merchant houses, the 16th-century Japanese Covered Bridge, and glowing silk lanterns reflected along the Thu Bon River.',
    ),
    KartaFeaturedPlace(
      id: 'vn-hue-citadel',
      name: 'Imperial City of Huế',
      shortLabel: 'Huế Citadel',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Huế',
      coordinate: Coordinate(lat: 16.4698, lon: 107.5784),
      established: '1804',
      isUnesco: true,
      transitAccess: 'Huế Railway Station (Reunification Express — 10 min drive)',
      highlights: <String>['Nguyen Dynasty Royal Citadel', 'Ngo Mon Meridian Gate', 'Perfume River Moat'],
      minZoom: 7.4,
      summary:
          'Serving as the imperial capital of Vietnam\'s Nguyen Dynasty from 1802 to 1945, the walled Citadel of Huế encompasses grand vermilion palaces, ceremonial gates, and lotus moats beside the Perfume River.',
    ),
    KartaFeaturedPlace(
      id: 'vn-notre-dame',
      name: 'Notre-Dame Cathedral Basilica of Saigon',
      shortLabel: 'Saigon Cathedral',
      kind: KartaPlaceKind.church,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'District 1, Ho Chi Minh City',
      coordinate: Coordinate(lat: 10.7798, lon: 106.6990),
      established: '1880',
      transitAccess: 'Opera House Metro Station (HCMC Line 1 — 6 min walk)',
      highlights: <String>['58 m Twin Red-Brick Bell Towers', 'Marseille Terracotta Facade', 'Beside Central Post Office'],
      minZoom: 9.2,
      summary:
          'Constructed between 1877 and 1880 entirely from red bricks imported from Marseille, Saigon\'s twin-spired Romanesque cathedral stands at Paris Commune Square beside the historic Central Post Office.',
    ),
    KartaFeaturedPlace(
      id: 'vn-temple-of-lit',
      name: 'Temple of Literature (Văn Miếu)',
      shortLabel: 'Temple of Literature',
      kind: KartaPlaceKind.temple,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Hanoi',
      coordinate: Coordinate(lat: 21.0285, lon: 105.8356),
      established: '1070',
      transitAccess: 'Cat Linh Metro Station (Line 2A) · Hanoi Railway Station (10 min walk)',
      highlights: <String>['Vietnam\'s First National University (1076)', '82 UNESCO Stone Turtle Stelae', 'Five Tranquil Courtyards'],
      minZoom: 9.2,
      summary:
          'Founded in 1070 under Emperor Lý Thánh Tông, Văn Miếu – Quốc Tử Giám is Vietnam\'s oldest temple of learning and first national university, housing 82 carved doctoral stone stelae resting atop stone tortoises.',
    ),
    KartaFeaturedPlace(
      id: 'vn-sgn',
      name: 'Tan Son Nhat International Airport',
      shortLabel: 'Tan Son Nhat',
      kind: KartaPlaceKind.airport,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Ho Chi Minh City',
      coordinate: Coordinate(lat: 10.8188, lon: 106.6519),
      established: '1930',
      iataCode: 'SGN',
      icaoCode: 'VVTS',
      transitAccess: 'Airport Express Bus 109 & 152 directly to Ben Thanh Metro Hub',
      highlights: <String>['Vietnam\'s Busiest Airport', '6 km to District 1', 'Southern Vietnam Hub'],
      minZoom: 5.8,
      summary:
          'Serving Ho Chi Minh City and the Mekong Delta, Tan Son Nhat International Airport is Vietnam\'s highest-volume aviation hub situated just 6 kilometers north of downtown District 1.',
    ),
    KartaFeaturedPlace(
      id: 'vn-han',
      name: 'Noi Bai International Airport',
      shortLabel: 'Noi Bai Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Hanoi',
      coordinate: Coordinate(lat: 21.2212, lon: 105.8072),
      established: '1978',
      iataCode: 'HAN',
      icaoCode: 'VVNB',
      transitAccess: 'Express Bus 86 directly to Hanoi Old Quarter & Hanoi Railway Station',
      highlights: <String>['Northern Vietnam Gateway', 'Nhat Tan Bridge Express Link', 'Ha Long & Sapa Access'],
      minZoom: 5.8,
      summary:
          'Northern Vietnam\'s primary international gateway serving Hanoi, connected via the iconic cable-stayed Nhat Tan Bridge directly toward Hanoi\'s Old Quarter and northern highland routes.',
    ),
    KartaFeaturedPlace(
      id: 'vn-hanoi-station',
      name: 'Hanoi Railway Station (Ga Hà Nội)',
      shortLabel: 'Hanoi Station',
      kind: KartaPlaceKind.railHub,
      countryCode: 'VN',
      countryName: 'Vietnam',
      city: 'Hoan Kiem, Hanoi',
      coordinate: Coordinate(lat: 21.0245, lon: 105.8412),
      established: '1902',
      transitAccess: 'Reunification Express (Hanoi–HCMC) · Sapa Overnight Trains · Hanoi Metro',
      highlights: <String>['North–South Reunification Express', 'Overnight Trains to Lao Cai / Sapa', 'Historic 1902 Terminus'],
      minZoom: 9.4,
      summary:
          'Vietnam\'s historic northern railway hub serving the famous 1,726 km Reunification Express along the coastline to Huế, Da Nang, and Ho Chi Minh City, as well as sleeper trains to Sapa and Hai Phong.',
    ),

    // =========================================================================
    // MYANMAR (MM)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'mm-shwedagon',
      name: 'Shwedagon Pagoda',
      shortLabel: 'Shwedagon Pagoda',
      kind: KartaPlaceKind.temple,
      countryCode: 'MM',
      countryName: 'Myanmar',
      city: 'Yangon',
      coordinate: Coordinate(lat: 16.7983, lon: 96.1496),
      established: '6th–10th Century',
      transitAccess: 'Yangon Circular Railway (10 min drive) · Kandawgyi Lake Corridor',
      highlights: <String>['99 m Solid Gold-Plated Stupa', 'Over 4,500 Crown Diamonds', 'Myanmar\'s Holiest Shrine'],
      minZoom: 5.8,
      summary:
          'Crowning Singuttara Hill above Yangon, the glittering 99-meter Shwedagon Pagoda is Myanmar\'s most sacred Buddhist pagoda. Encased in thousands of gold plates and topped by a diamond-studded hti spire, it glows unmistakably over the city skyline.',
    ),
    KartaFeaturedPlace(
      id: 'mm-bagan',
      name: 'Bagan Archaeological Zone',
      shortLabel: 'Bagan Temples',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'MM',
      countryName: 'Myanmar',
      city: 'Mandalay Region',
      coordinate: Coordinate(lat: 21.1717, lon: 94.8585),
      established: '9th–13th Century',
      isUnesco: true,
      transitAccess: 'Bagan Railway Station (Nyaung-U) · Irrawaddy River Ferry',
      highlights: <String>['2,200+ Ancient Brick Pagodas', 'Ananda & Dhammayangyi Temples', 'UNESCO Sacred Landscape'],
      minZoom: 5.8,
      summary:
          'Spanning the sunlit plains beside the Ayeyarwady River, the UNESCO World Heritage plains of Bagan hold more than 2,200 surviving medieval stupas, monasteries, and frescoed temples—including the golden-spired Ananda Temple.',
    ),
    KartaFeaturedPlace(
      id: 'mm-rgn',
      name: 'Yangon International Airport',
      shortLabel: 'Yangon Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'MM',
      countryName: 'Myanmar',
      city: 'Mingaladon, Yangon',
      coordinate: Coordinate(lat: 16.9073, lon: 96.1332),
      established: '1947',
      iataCode: 'RGN',
      icaoCode: 'VYYY',
      transitAccess: 'Yangon Airport Shuttle Bus · 35 min to Downtown & Shwedagon',
      highlights: <String>['Myanmar\'s Busiest Airport', '15 km North of Downtown', 'Regional ASEAN Links'],
      minZoom: 6.2,
      summary:
          'Myanmar\'s primary international aviation hub serving Yangon and connecting domestic travelers onward to Bagan, Mandalay, and Inle Lake.',
    ),
    KartaFeaturedPlace(
      id: 'mm-yangon-central',
      name: 'Yangon Central Railway Station',
      shortLabel: 'Yangon Central',
      kind: KartaPlaceKind.railHub,
      countryCode: 'MM',
      countryName: 'Myanmar',
      city: 'Downtown Yangon',
      coordinate: Coordinate(lat: 16.7819, lon: 96.1619),
      established: '1877',
      transitAccess: 'Yangon Circular Railway · Intercity Trains to Mandalay & Bagan',
      highlights: <String>['Traditional Burmese Pyatthat Roofs', 'Yangon Circular Commuter Train', 'National Rail Hub'],
      minZoom: 9.2,
      summary:
          'Adorned with multi-tiered traditional Burmese pyatthat roof spires, Yangon Central is the nerve center of Myanmar Railways—departing both intercity express trains and the famous Yangon Circular Train loop.',
    ),

    // =========================================================================
    // LAOS (LA)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'la-pha-that-luang',
      name: 'Pha That Luang (Great Stupa)',
      shortLabel: 'Pha That Luang',
      kind: KartaPlaceKind.temple,
      countryCode: 'LA',
      countryName: 'Laos',
      city: 'Vientiane',
      coordinate: Coordinate(lat: 17.9763, lon: 102.6345),
      established: '1566',
      transitAccess: '15 min from Vientiane LCR High-Speed Station · Lane Xang Ave',
      highlights: <String>['45 m Gold-Covered National Stupa', 'Symbol of Lao Sovereignty', 'Three-Tiered Buddhist Cloister'],
      minZoom: 6.2,
      summary:
          'Glistening in gold leaf along the eastern edge of Vientiane, the 45-meter Pha That Luang is the most sacred Buddhist monument in Laos and its national emblem, believed to enshrine a relic of the Buddha.',
    ),
    KartaFeaturedPlace(
      id: 'la-patuxai',
      name: 'Patuxai Victory Monument',
      shortLabel: 'Patuxai',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'LA',
      countryName: 'Laos',
      city: 'Vientiane',
      coordinate: Coordinate(lat: 17.9706, lon: 102.6186),
      established: '1968',
      transitAccess: 'Central Lane Xang Avenue · 5 min from Talat Sao Bus Hub',
      highlights: <String>['Lao-Carved Triumphal Arch', 'Rooftop View of Vientiane', 'Musical Fountain Park'],
      minZoom: 8.6,
      summary:
          'Standing proudly at the heart of Vientiane\'s grand Lane Xang Boulevard, Patuxai blends triumphant arch geometry with distinctly Lao Kinnari carvings, lotus towers, and a panoramic observation deck overlooking the Mekong city.',
    ),
    KartaFeaturedPlace(
      id: 'la-wat-xieng-thong',
      name: 'Wat Xieng Thong & Luang Prabang Old Town',
      shortLabel: 'Luang Prabang',
      kind: KartaPlaceKind.temple,
      countryCode: 'LA',
      countryName: 'Laos',
      city: 'Luang Prabang',
      coordinate: Coordinate(lat: 19.8975, lon: 102.1431),
      established: '1560',
      isUnesco: true,
      transitAccess: 'Luang Prabang LCR High-Speed Rail Station (20 min transfer)',
      highlights: <String>['16th-Century Royal Monastery', 'Tree of Life Glass Mosaic', 'UNESCO Mekong–Nam Khan Peninsula'],
      minZoom: 6.6,
      summary:
          'Built in 1560 at the confluence of the Mekong and Nam Khan rivers, Wat Xieng Thong is the jewel of UNESCO-listed Luang Prabang, renowned for its sweeping low-tiered roofs and glittering "Tree of Life" colored-glass mural.',
    ),
    KartaFeaturedPlace(
      id: 'la-vte',
      name: 'Wattay International Airport',
      shortLabel: 'Wattay Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'LA',
      countryName: 'Laos',
      city: 'Vientiane',
      coordinate: Coordinate(lat: 17.9883, lon: 102.5633),
      established: '1999',
      iataCode: 'VTE',
      icaoCode: 'VLVT',
      transitAccess: 'Airport Express Bus to Talat Sao (15 min) · 3 km to City Centre',
      highlights: <String>['Laos Primary Gateway', 'Minutes from Mekong Riverfront', 'Direct ASEAN Connections'],
      minZoom: 6.5,
      summary:
          'Serving the Lao capital of Vientiane just 3 kilometers from the Mekong riverfront, Wattay International Airport links international visitors swiftly to Vientiane\'s monuments and the Laos–China Railway.',
    ),
    KartaFeaturedPlace(
      id: 'la-vientiane-lcr',
      name: 'Vientiane Railway Station (Laos–China Railway)',
      shortLabel: 'Vientiane LCR',
      kind: KartaPlaceKind.railHub,
      countryCode: 'LA',
      countryName: 'Laos',
      city: 'Xaythany, Vientiane',
      coordinate: Coordinate(lat: 18.0672, lon: 102.6844),
      established: '2021',
      transitAccess: 'Lane Xang EMU Express Trains to Vang Vieng (1 hr) & Luang Prabang (2 hrs)',
      highlights: <String>['160 km/h Lane Xang EMU Rail', 'Vientiane to Luang Prabang in 2 hrs', 'Modern Sandalwood-Inspired Roof'],
      minZoom: 8.8,
      summary:
          'Laos\'s flagship modern railway station on the Laos–China Railway, whisking travelers aboard sleek electric EMU trains from Vientiane to Vang Vieng in under an hour and to UNESCO Luang Prabang in two hours.',
    ),

    // =========================================================================
    // CAMBODIA (KH)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'kh-angkor-wat',
      name: 'Angkor Wat',
      shortLabel: 'Angkor Wat',
      kind: KartaPlaceKind.temple,
      countryCode: 'KH',
      countryName: 'Cambodia',
      city: 'Siem Reap',
      coordinate: Coordinate(lat: 13.4125, lon: 103.8670),
      established: '12th Century',
      isUnesco: true,
      transitAccess: '7 km north of Siem Reap Town · 50 min from Siem Reap–Angkor Airport',
      highlights: <String>['World\'s Largest Religious Monument', 'Iconic 5 Lotus-Bud Towers', 'Sunrise Reflections & Bas-Reliefs'],
      minZoom: 5.2,
      summary:
          'Built in the early 12th century by Khmer King Suryavarman II, Angkor Wat spans 162.6 hectares as the largest religious monument on Earth. Surrounded by a vast ceremonial moat, its five lotus-bud towers and intricately carved sandstone galleries anchor Cambodia\'s supreme UNESCO World Heritage wonder.',
    ),
    KartaFeaturedPlace(
      id: 'kh-royal-palace',
      name: 'Royal Palace & Silver Pagoda',
      shortLabel: 'Royal Palace',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'KH',
      countryName: 'Cambodia',
      city: 'Phnom Penh',
      coordinate: Coordinate(lat: 11.5637, lon: 104.9313),
      established: '1866',
      transitAccess: 'Sisowath Quay Riverfront · 20 min from Phnom Penh Railway Station',
      highlights: <String>['Gilded Khmer Roof Spires', '5,000+ Silver Floor Tiles', 'Emerald & Diamond Buddha'],
      minZoom: 7.2,
      summary:
          'Overlooking the confluence of the Mekong and Tonlé Sap rivers, Phnom Penh\'s Royal Palace gleams with classical Khmer soaring roofs and houses the celebrated Silver Pagoda, inlaid with over 5,000 solid silver floor tiles.',
    ),
    KartaFeaturedPlace(
      id: 'kh-sai',
      name: 'Siem Reap–Angkor International Airport',
      shortLabel: 'Angkor Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'KH',
      countryName: 'Cambodia',
      city: 'Sotr Nikum, Siem Reap',
      coordinate: Coordinate(lat: 13.3693, lon: 104.2225),
      established: '2023',
      iataCode: 'SAI',
      icaoCode: 'VDSA',
      transitAccess: 'Dedicated Airport Expressway & Shuttle Bus to Siem Reap & Angkor Park',
      highlights: <String>['Cambodia\'s Largest New Airport', 'Khmer Palace-Inspired Roof', 'Gateway to Angkor Wat'],
      minZoom: 6.2,
      summary:
          'Opened in 2023 to preserve the acoustic and structural tranquility of Angkor Archaeological Park, Siem Reap–Angkor International Airport welcomes global travelers with sleek Khmer-inspired architecture.',
    ),
    KartaFeaturedPlace(
      id: 'kh-pnh',
      name: 'Phnom Penh International Airport',
      shortLabel: 'Phnom Penh Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'KH',
      countryName: 'Cambodia',
      city: 'Por Senchey, Phnom Penh',
      coordinate: Coordinate(lat: 11.5466, lon: 104.8441),
      established: '1959',
      iataCode: 'PNH',
      icaoCode: 'VDPP',
      transitAccess: '10 km west of Royal Palace · City Bus Line 3',
      highlights: <String>['Capital Aviation Hub', '25 min to Mekong Riverfront', 'ASEAN Regional Connections'],
      minZoom: 6.5,
      summary:
          'Serving Cambodia\'s vibrant capital along the Mekong River, connecting travelers directly to the Royal Palace, National Museum, and coastal routes toward Kampot and Sihanoukville.',
    ),

    // =========================================================================
    // TIMOR-LESTE (TL)
    // =========================================================================
    KartaFeaturedPlace(
      id: 'tl-cristo-rei',
      name: 'Cristo Rei of Dili',
      shortLabel: 'Cristo Rei',
      kind: KartaPlaceKind.historicalLandmark,
      countryCode: 'TL',
      countryName: 'Timor-Leste',
      city: 'Fatucama, Dili',
      coordinate: Coordinate(lat: -8.5208, lon: 125.6085),
      established: '1996',
      transitAccess: '15 min coastal drive east of Dili Waterfront along Areia Branca',
      highlights: <String>['27 m Hilltop Copper Statue', '590 Scenic Steps', 'Twin Turquoise Beach Views'],
      minZoom: 6.2,
      summary:
          'Standing 27 meters high atop Cape Fatucama overlooking Dili Bay and Atauro Island, Cristo Rei is Timor-Leste\'s most recognizable coastal monument, flanked by sweeping ocean cliffs and white-sand beaches.',
    ),
    KartaFeaturedPlace(
      id: 'tl-cathedral',
      name: 'Immaculate Conception Cathedral',
      shortLabel: 'Dili Cathedral',
      kind: KartaPlaceKind.church,
      countryCode: 'TL',
      countryName: 'Timor-Leste',
      city: 'Vila Verde, Dili',
      coordinate: Coordinate(lat: -8.5594, lon: 125.5688),
      established: '1989',
      transitAccess: 'Central Dili (5 min from Waterfront & Tais Market)',
      highlights: <String>['Largest Cathedral in Timor-Leste', 'Historic 1989 Papal Visit Site', 'Heart of Dili Community'],
      minZoom: 8.6,
      summary:
          'Serving as the mother church of the Archdiocese of Dili, the serene white-and-blue Immaculate Conception Cathedral stands at the spiritual and historic heart of Timor-Leste\'s capital.',
    ),
    KartaFeaturedPlace(
      id: 'tl-dil',
      name: 'Presidente Nicolau Lobato International Airport',
      shortLabel: 'Dili Airport',
      kind: KartaPlaceKind.airport,
      countryCode: 'TL',
      countryName: 'Timor-Leste',
      city: 'Comoro, Dili',
      coordinate: Coordinate(lat: -8.5466, lon: 125.5247),
      established: '1975',
      iataCode: 'DIL',
      icaoCode: 'WPDL',
      transitAccess: '12 min along Beachfront Avenue to Central Dili',
      highlights: <String>['Timor-Leste\'s International Gateway', 'Coastal Ombai Strait Approach', 'Direct Bali, Singapore & Darwin Links'],
      minZoom: 6.2,
      summary:
          'Named after Timor-Leste\'s national hero Nicolau dos Reis Lobato, Dili\'s coastal airport serves as the country\'s primary air bridge to Bali, Singapore, Kuala Lumpur, and Darwin.',
    ),
  ];

  static final Map<String, KartaFeaturedPlace> _byId = <String, KartaFeaturedPlace>{
    for (final p in all) p.id: p,
  };

  static List<KartaMapFeaturedPin> toMapPins() =>
      all.map((p) => p.toMapPin()).toList(growable: false);

  static KartaFeaturedPlace? findById(String id) => _byId[id];

  /// Attempts to match a tapped vector-tile POI against our curated SEA places
  /// (within [maxMeters]), so clicking an OSM label for e.g. KLCC or Angkor Wat
  /// still opens the full rich Karta Travel Guide card!
  static KartaFeaturedPlace? matchNearby(
    Coordinate coord, {
    String? nameHint,
    double maxMeters = 650,
  }) {
    final hint = (nameHint ?? '').trim().toLowerCase();
    KartaFeaturedPlace? best;
    double bestDist = maxMeters;
    for (final place in all) {
      final d = haversineMeters(coord, place.coordinate);
      if (d <= bestDist) {
        best = place;
        bestDist = d;
      } else if (hint.length >= 4 &&
          d <= maxMeters * 2.5 &&
          (place.name.toLowerCase().contains(hint) ||
              place.shortLabel.toLowerCase().contains(hint) ||
              (place.iataCode != null && place.iataCode!.toLowerCase() == hint))) {
        best = place;
        bestDist = d;
      }
    }
    return best;
  }

  /// Instant offline/local search across all curated landmarks, airports,
  /// sacred sites, and rail hubs (by name, city, country, IATA code, or category).
  static List<KartaFeaturedPlace> search({
    String query = '',
    String? filterGroup,
    int limit = 16,
  }) {
    final q = query.trim().toLowerCase();
    final matches = <KartaFeaturedPlace>[];
    for (final place in all) {
      if (filterGroup != null &&
          filterGroup.isNotEmpty &&
          place.kind.filterGroup != filterGroup) {
        continue;
      }
      if (q.isEmpty) {
        matches.add(place);
      } else {
        final hay = [
          place.name,
          place.shortLabel,
          place.city,
          place.countryName,
          place.countryCode,
          place.iataCode ?? '',
          place.kind.wireKind,
          place.kind.filterGroup,
          place.summary,
        ].join(' ').toLowerCase();
        if (hay.contains(q)) {
          matches.add(place);
        }
      }
      if (matches.length >= limit) break;
    }
    return matches;
  }

  /// Converts a tapped OpenStreetMap vector-tile station, mosque, temple,
  /// church, airport, or landmark into a clean contextual info record when it
  /// isn't one of the major curated entries above.
  static KartaFeaturedPlace fromVectorTap(KartaVectorFeatureTap tap) {
    final cls = tap.featureClass.toLowerCase();
    final sub = tap.subclass.toLowerCase();
    final rel = (tap.religion ?? '').toLowerCase();
    final lowerName = tap.name.toLowerCase();

    final isExplicitStation = cls == 'railway' ||
        sub == 'station' ||
        sub == 'halt' ||
        sub == 'subway_entrance' ||
        sub == 'tram_stop' ||
        sub == 'subway' ||
        sub == 'light_rail' ||
        sub == 'monorail' ||
        lowerName.contains('mrt') ||
        lowerName.contains('lrt') ||
        lowerName.contains('bts') ||
        lowerName.contains('stesen') ||
        lowerName.contains('stasiun') ||
        lowerName.contains('station');

    final curated = matchNearby(
      tap.coordinate,
      nameHint: tap.name,
      maxMeters: isExplicitStation ? 140 : 280,
    );
    if (curated != null) {
      final sameKindOrName = !isExplicitStation ||
          curated.kind == KartaPlaceKind.railHub ||
          curated.kind == KartaPlaceKind.trainStation ||
          curated.name.toLowerCase().contains(lowerName) ||
          lowerName.contains(curated.shortLabel.toLowerCase());
      if (sameKindOrName) return curated;
    }

    KartaPlaceKind kind;
    String summary;
    List<String> highlights;

    if (isExplicitStation) {
      kind = KartaPlaceKind.trainStation;
      summary =
          'Active rail / rapid transit station mapped on Karta Southeast Asia. Tap "Go Here" for live turn-by-turn directions to the station entrance or "Start Here" to plan your onward trip.';
      highlights = <String>['Rail & Transit Stop', 'Live Map Routing Ready'];
    } else if (cls == 'airport' ||
        cls == 'aerodrome' ||
        sub == 'aerodrome' ||
        (tap.iata != null && tap.iata!.isNotEmpty) ||
        lowerName.contains('airport') ||
        lowerName.contains('lapangan terbang') ||
        lowerName.contains('bandara')) {
      kind = KartaPlaceKind.airport;
      summary =
          'Mapped Southeast Asian aviation terminal${tap.iata != null ? ' (IATA: ${tap.iata})' : ''}. Use Karta to navigate directly to departures, drop-off lanes, or airport transit connections.';
      highlights = <String>[
        if (tap.iata != null && tap.iata!.isNotEmpty) 'IATA ${tap.iata}',
        'Airport Terminal',
      ];
    } else if (rel == 'muslim' ||
        sub == 'mosque' ||
        lowerName.contains('masjid') ||
        lowerName.contains('surau') ||
        lowerName.contains('mosque')) {
      kind = KartaPlaceKind.mosque;
      summary =
          'Islamic house of worship mapped in Karta Southeast Asia. Visitors are advised to observe modest attire and local prayer times when visiting.';
      highlights = <String>['Mosque / Masjid', 'Community Worship Site'];
    } else if (rel == 'christian' ||
        sub == 'church' ||
        lowerName.contains('church') ||
        lowerName.contains('gereja') ||
        lowerName.contains('cathedral') ||
        lowerName.contains('basilica') ||
        lowerName.contains('chapel')) {
      kind = KartaPlaceKind.church;
      summary =
          'Christian church or cathedral mapped in Karta Southeast Asia. Check local service hours and architectural heritage access when planning your visit.';
      highlights = <String>['Church / Cathedral', 'Sacred Architecture'];
    } else if (rel == 'buddhist' ||
        rel == 'hindu' ||
        rel == 'taoist' ||
        sub == 'temple' ||
        sub == 'place_of_worship' ||
        lowerName.contains('wat ') ||
        lowerName.contains('temple') ||
        lowerName.contains('kuil') ||
        lowerName.contains('tokong') ||
        lowerName.contains('pura ') ||
        lowerName.contains('candi ') ||
        lowerName.contains('pagoda') ||
        lowerName.contains('shrine')) {
      kind = KartaPlaceKind.temple;
      summary =
          'Sacred temple, pagoda, or cultural shrine mapped in Karta Southeast Asia. Dress respectfully and follow temple courtyard guidelines during your visit.';
      highlights = <String>['Temple / Sacred Site', 'Cultural Landmark'];
    } else {
      kind = KartaPlaceKind.historicalLandmark;
      summary =
          'Point of interest mapped on Karta Southeast Asia. Tap "Go Here" for live navigation, save it to your Karta Account, or inspect it in 3D Look-Around.';
      highlights = <String>['Southeast Asia Map POI'];
    }

    return KartaFeaturedPlace(
      id: 'vec-${tap.coordinate.lat.toStringAsFixed(5)}-${tap.coordinate.lon.toStringAsFixed(5)}',
      name: tap.name,
      shortLabel: tap.name,
      kind: kind,
      countryCode: '',
      countryName: 'Southeast Asia',
      city: '${tap.coordinate.lat.toStringAsFixed(4)}, ${tap.coordinate.lon.toStringAsFixed(4)}',
      coordinate: tap.coordinate,
      iataCode: tap.iata,
      summary: summary,
      highlights: highlights,
    );
  }
}
