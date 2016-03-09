# psma-admin-bdys
Some utils to make it easier to use the PSMA's Administrative Boundaries

## locality-clean
A Python script for creating a clean version of the Suburb-Locality boundaries for presentation or visualisation.

Trims the boundaries to the coastline; fixes state border overlaps and gaps; and thins the boundaries for faster display performance in desktop GIS tools and in browsers.

This process takes ~30-45 mins.

![aus.png](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/aus.png "clean vs original localities")

Coastline improvements


![border-comparison](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/border-comparison.png "clean vs original borders")

State border improvements

### Important

The cleaned localities are not well suited to data processing as they have been deliberately thinned to improve display performance.

A better dataset for processing is the admin_bdys.locality_bdy_analysis table that gets created in the [gnaf-loader](https://github.com/minus34/gnaf-loader) process

### I Just Want the Data!

You can run the script to get the result or just download the data from here:
- [Shapefile](https://github.com/iag-geo/psma-admin-bdys/releases/download/v1.0/locality_bdys_display_shapefile.zip) (~40Mb) 
- [GeoJSON](https://github.com/iag-geo/psma-admin-bdys/releases/download/v1.0/locality_bdys_display_geojson.zip) (~25Mb) 

#### Data License

Incorporates or developed using Administrative Boundaries ©PSMA Australia Limited licensed by the Commonwealth of Australia under [Creative Commons Attribution 4.0 International licence (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

### Script Pre-requisites

- You will need to run the [gnaf-loader](https://github.com/minus34/gnaf-loader) script to load the required Admin Bdy tables into Postgres
- Postgres 9.x (tested on 9.3, 9.4 & 9.5 on Windows and 9.5 on OSX)
- PostGIS 2.1+
- Python 2.7 with Psycopg2 2.6

### Missing localities
Trimming the boundaries to the coastline removes a small number of bay or estuary based localities.  These have very few G-NAF addresses.

These localities are:

| locality_pid | name | postcode | state | addresses | streets |
| ------------- | ------------- | ------------- | ------------- | -------------: | -------------: |
| NSW524 | BOTANY BAY | 2019 | NSW | 1 | 12 | 
| NSW2046 | JERVIS BAY |  | NSW | 0 | 5 | 
| NSW2275 | LAKE MACQUARIE |  | NSW | 1 | 67 | 
| NSW2627 | MIDDLE HARBOUR | 2087 | NSW | 3 | 22 | 
| NSW3019 | NORTH HARBOUR |  | NSW | 0 | 11 | 
| NSW3255 | PITTWATER | 2108 | NSW | 5 | 31 | 
| NT26 | BEAGLE GULF |  | NT | 0 | 0 | 
| NT75 | DARWIN HARBOUR |  | NT | 0 | 0 | 
| QLD1351 | HERVEY BAY |  | QLD | 0 | 2 |
