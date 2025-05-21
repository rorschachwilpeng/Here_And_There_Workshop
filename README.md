# Geo Music Personality Test App

This is a Flutter mobile application triggered by geographical location for music playback and personality test results. When users enter specific geographic areas defined by GeoJSON, the app automatically plays music corresponding to that area and displays related personality test results.

## Features

- Read and parse geographic areas defined in GeoJSON files
- Track user location in real-time and determine if they enter specific areas
- Automatically play corresponding music when users enter an area
- Display personality test results associated with the area
- Include simulated location features for testing

## Technology Stack

- Flutter framework
- geolocator: for obtaining user location
- audioplayers: for playing music
- turf: for geospatial analysis, determining if a point is within a polygon
- permission_handler: managing application permissions

## Usage Instructions

1. Ensure a valid GeoJSON file named `test.geojson` is in the `assets` folder
2. Each Feature in the GeoJSON file should include the following properties:
   - `name`: Area name
   - `music_url`: Music URL
   - `personality_result`: Personality test result text
3. Run the application and grant location permissions
4. Enter the defined geographic area, and the app will automatically play music and display personality test results

## Test Mode

The application includes a test mode, where you can simulate entering different geographic areas via buttons at the bottom of the interface:
- "Area 1" button: Simulate entering test area 1
- "Area 2" button: Simulate entering test area 2
- "Leave Area" button: Simulate leaving all areas

## Development Extensions

To add more areas, simply add new Features to the GeoJSON file, ensuring they contain the required properties. The application will automatically load and process the newly added areas.