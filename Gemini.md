# Project Rules: Karta Navigation Platform

## Brand & Visual Identity (Derived from Logo)
- **App Name:** Karta
- **Theme:** Dark-first automotive & desktop UI.
- **Color Palette:** 
  - Background Primary: `#0D0F12` (Deep Obsidian)
  - Surface / Cards: `#181C22` (Charcoal Slate)
  - Accent Primary: `#5B9A94` (Muted Teal from Karta map pin)
  - Text Primary: `#F4F6F8` (Crisp Off-White)
  - Text Secondary: `#8E96A0` (Steel Gray)

## Target Platforms
- Mobile & Tablets: iOS, Android (Flutter or React Native New Architecture)
- Desktop & Web: Windows, macOS, Linux, Web
- Automotive: Apple CarPlay (`CPMapTemplate`) & Android Auto (`NavigationTemplate`)

## Regional Testbed (MY / SG / BN)
- Geographic bounding box: Malaysia, Singapore, and Brunei (`osm.pbf` extracts via Geofabrik).
- Local toll systems: PLUS, Touch 'n Go RFID/SmartTAG (MY), ERP gantries (SG).
- Currency formatting: `MYR` (RM), `SGD` ($), `BND` (B$) based on active GPS country code.
- Transit & POI data: OpenStreetMap + local GTFS feeds (Prasarana/RapidKL, LTA Singapore).

## Engineering Standards
- Never mock core routing or database queries with dummy arrays; implement real PostGIS/Valhalla/MapLibre interfaces.
- Keep UI components strictly decoupled from native GPS/automotive background services.
