-- ============================================================================
-- Karta Navigation Platform — Regional Countries, Currency & Vehicle Classes
-- Note: 06_ingest_postgis.sh upgrades geo.countries.geom with exact OSM
-- admin_level=2 boundaries once malaysia-singapore-brunei-latest.osm.pbf loads.
-- ============================================================================

INSERT INTO geo.countries (
    iso_a2, iso_a3, name, currency_code, currency_symbol,
    symbol_prefix_space, decimal_places, driving_side, speed_unit,
    timezone_iana, geom
)
VALUES
(
    'SG', 'SGP', 'Singapore', 'SGD', '$',
    FALSE, 2, 'left', 'kmh', 'Asia/Singapore',
    ST_Multi(ST_GeomFromText(
        'POLYGON((103.59 1.15, 104.09 1.15, 104.09 1.472, 103.80 1.472, 103.63 1.445, 103.59 1.32, 103.59 1.15))',
        4326
    ))
),
(
    'BN', 'BRN', 'Brunei Darussalam', 'BND', 'B$',
    FALSE, 2, 'left', 'kmh', 'Asia/Brunei',
    ST_Multi(ST_GeomFromText(
        'MULTIPOLYGON(((114.07 4.00, 115.05 4.00, 115.05 5.06, 114.07 5.06, 114.07 4.00)), ((115.06 4.28, 115.36 4.28, 115.36 4.92, 115.06 4.92, 115.06 4.28)))',
        4326
    ))
),
(
    'MY', 'MYS', 'Malaysia', 'MYR', 'RM',
    TRUE, 2, 'left', 'kmh', 'Asia/Kuala_Lumpur',
    ST_Multi(ST_Difference(
        ST_GeomFromText(
            'MULTIPOLYGON(((99.55 1.14, 104.55 1.14, 104.55 6.80, 99.55 6.80, 99.55 1.14)), ((109.50 0.85, 119.40 0.85, 119.40 7.40, 109.50 7.40, 109.50 0.85)))',
            4326
        ),
        ST_Union(
            ST_GeomFromText('POLYGON((103.59 1.15, 104.09 1.15, 104.09 1.472, 103.80 1.472, 103.63 1.445, 103.59 1.32, 103.59 1.15))', 4326),
            ST_GeomFromText('MULTIPOLYGON(((114.07 4.00, 115.05 4.00, 115.05 5.06, 114.07 5.06, 114.07 4.00)), ((115.06 4.28, 115.36 4.28, 115.36 4.92, 115.06 4.92, 115.06 4.28)))', 4326)
        )
    ))
),
(
    'ID', 'IDN', 'Indonesia', 'IDR', 'Rp',
    TRUE, 0, 'left', 'kmh', 'Asia/Jakarta',
    ST_Multi(ST_GeomFromText(
        'POLYGON((94.80 -11.10, 141.10 -11.10, 141.10 5.95, 119.45 5.95, 119.45 0.80, 109.45 0.80, 109.45 1.10, 99.50 1.10, 94.80 5.95, 94.80 -11.10))',
        4326
    ))
),
(
    'TH', 'THA', 'Thailand', 'THB', '฿',
    FALSE, 2, 'left', 'kmh', 'Asia/Bangkok',
    ST_Multi(ST_GeomFromText(
        'POLYGON((97.35 5.60, 105.65 5.60, 105.65 20.48, 97.35 20.48, 97.35 5.60))',
        4326
    ))
),
(
    'PH', 'PHL', 'Philippines', 'PHP', '₱',
    FALSE, 2, 'right', 'kmh', 'Asia/Manila',
    ST_Multi(ST_GeomFromText(
        'POLYGON((116.85 4.55, 126.95 4.55, 126.95 21.15, 116.85 21.15, 116.85 4.55))',
        4326
    ))
),
(
    'VN', 'VNM', 'Vietnam', 'VND', '₫',
    FALSE, 0, 'right', 'kmh', 'Asia/Ho_Chi_Minh',
    ST_Multi(ST_GeomFromText(
        'POLYGON((102.14 8.35, 109.50 8.35, 109.50 23.40, 102.14 23.40, 102.14 8.35))',
        4326
    ))
),
(
    'MM', 'MMR', 'Myanmar', 'MMK', 'Ks',
    TRUE, 0, 'right', 'kmh', 'Asia/Yangon',
    ST_Multi(ST_GeomFromText(
        'POLYGON((92.18 9.60, 101.18 9.60, 101.18 28.55, 92.18 28.55, 92.18 9.60))',
        4326
    ))
),
(
    'LA', 'LAO', 'Laos', 'LAK', '₭',
    FALSE, 0, 'right', 'kmh', 'Asia/Vientiane',
    ST_Multi(ST_GeomFromText(
        'POLYGON((100.08 13.90, 107.65 13.90, 107.65 22.52, 100.08 22.52, 100.08 13.90))',
        4326
    ))
),
(
    'KH', 'KHM', 'Cambodia', 'KHR', '៛',
    FALSE, 0, 'right', 'kmh', 'Asia/Phnom_Penh',
    ST_Multi(ST_GeomFromText(
        'POLYGON((102.33 10.35, 107.63 10.35, 107.63 14.70, 102.33 14.70, 102.33 10.35))',
        4326
    ))
),
(
    'TL', 'TLS', 'Timor-Leste', 'USD', '$',
    FALSE, 2, 'left', 'kmh', 'Asia/Dili',
    ST_Multi(ST_GeomFromText(
        'MULTIPOLYGON(((124.94 -9.55, 127.35 -9.55, 127.35 -8.12, 124.94 -8.12, 124.94 -9.55)), ((124.04 -9.48, 124.48 -9.48, 124.48 -9.16, 124.04 -9.16, 124.04 -9.48)))',
        4326
    ))
)
ON CONFLICT (iso_a2) DO NOTHING;

-- ============================================================================
-- Regional Toll Vehicle Classifications (MY LLM, SG LTA, BN JKR)
-- ============================================================================
INSERT INTO tolls.vehicle_classes (country_code, class_code, canonical_profile, label, description)
VALUES
    -- Malaysia (LLM Standard Classes 1-5 + Motorcycle)
    ('MY', 'MY_C1', 'car',        'Class 1 — Private Car',       'Vehicles with 2 axles and 3 or 4 wheels (excluding taxis)'),
    ('MY', 'MY_C2', 'van_2axle',  'Class 2 — 2-Axle Commercial', 'Vehicles with 2 axles and 5 or 6 wheels (excluding buses)'),
    ('MY', 'MY_C3', 'truck_3axle','Class 3 — 3+ Axle Heavy',     'Vehicles with 3 or more axles'),
    ('MY', 'MY_C4', 'taxi',       'Class 4 — Taxi',              'Licensed Malaysian taxis'),
    ('MY', 'MY_C5', 'bus',        'Class 5 — Bus',               'Public and express buses'),
    ('MY', 'MY_MC', 'motorcycle', 'Motorcycle',                  'Two-wheelers (toll-free on most MY expressways except select bridges)'),

    -- Singapore (LTA ERP Vehicle Classes)
    ('SG', 'SG_PC',   'car',         'Passenger Car / Light Goods', 'Passenger cars, light goods vehicles <= 3.5t, small buses'),
    ('SG', 'SG_MC',   'motorcycle',  'Motorcycle',                  'Motorcycles (50% of passenger car ERP rate)'),
    ('SG', 'SG_TAXI', 'taxi',        'Taxi',                        'Taxis (same rate tier as passenger cars)'),
    ('SG', 'SG_HGV',  'van_2axle',   'Heavy Goods / Small Bus',     'Heavy goods vehicles > 3.5t up to 16t / small buses'),
    ('SG', 'SG_VHGV', 'truck_3axle', 'Very Heavy Goods / Big Bus',  'Very heavy goods vehicles > 16t / big buses'),
    ('SG', 'SG_BUS',  'bus',         'Big Bus',                     'Big buses (> 30 seats)'),

    -- Brunei Darussalam
    ('BN', 'BN_C1', 'car',         'Class 1 — Private Car / SUV', 'Saloon cars, 4WDs, MPVs'),
    ('BN', 'BN_C2', 'van_2axle',   'Class 2 — Light Commercial',  'Vans, pickups, light trucks'),
    ('BN', 'BN_C3', 'truck_3axle', 'Class 3 — Heavy Commercial',  'Multi-axle heavy trucks'),
    ('BN', 'BN_C4', 'bus',         'Class 4 — Bus',               'Coaches and passenger buses'),
    ('BN', 'BN_MC', 'motorcycle',  'Motorcycle',                  'Motorcycles'),
    ('BN', 'BN_TX', 'taxi',        'Taxi',                        'Licensed taxis')
ON CONFLICT (country_code, class_code) DO NOTHING;
