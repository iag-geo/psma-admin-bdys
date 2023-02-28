# psma-admin-bdys
Some utils to make it easier to use Geoscape's Administrative Boundaries

## locality-clean
A Python script for creating a clean version of the Suburb-Locality boundaries for presentation or visualisation.

Trims the boundaries to the coastline; fixes state border overlaps and gaps; and thins the boundaries for faster display performance in desktop/mobile browsers and GIS tools.

This process takes ~30-45 mins.

![aus.png](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/aus.png "clean vs original localities")

Coastline improvements

![border-comparison](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/border-comparison.png "clean vs original borders")

State border improvements

### Important

The cleaned and thinned localities have a reduced precision of 1-2m; however this is within the general precision of the property boundary data (Geoscape Cadlite) used to create the locality boundaries.

### I Just Want the Data!

You can run the script to get the result or download the data from here:
- [Shapefile](https://github.com/iag-geo/psma-admin-bdys/releases/download/202302/locality-bdys-display-202302-shapefile.zip) (~40Mb) 
- [GeoJSON](https://github.com/iag-geo/psma-admin-bdys/releases/download/202302/locality-bdys-display-202302.geojson.zip) (~30Mb) 

#### Data License

Incorporates or developed using Administrative Boundaries © [Geoscape Australia](https://geoscape.com.au/legal/data-copyright-and-disclaimer/) licensed by the Commonwealth of Australia under [Creative Commons Attribution 4.0 International licence (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

### Script Pre-requisites

- You will need to run the [gnaf-loader](https://github.com/minus34/gnaf-loader) script to load the required Admin Bdy tables into Postgres
- Postgres 10.x and above
- PostGIS 2.1+
- Python 2.7 or 3.5+ with psycopg 2.6+

### Missing localities
Trimming the boundaries to the coastline removes a small number of bay or estuary based localities.  These have very few G-NAF addresses.

These localities are:

| locality_pid | name | postcode | state | addresses | streets |
| ------------- | ------------- | ------------- | ------------- | -------------: | -------------: |
| NSW524 | BOTANY BAY | 2019 | NSW | 2 | 12 |
| NSW2046 | JERVIS BAY |  | NSW | 0 | 5 |
| NSW2627 | MIDDLE HARBOUR | 2087 | NSW | 3 | 23 |
| NSW3019 | NORTH HARBOUR |  | NSW | 0 | 10 |
| NSW3255 | PITTWATER | 2105 | NSW | 5 | 31 |
| NT26 | BEAGLE GULF |  | NT | 0 | 0 |
| NT75 | DARWIN HARBOUR |  | NT | 0 | 0 |
| QLD3395 | UNNAMED LOCALITY | 9999 | QLD | 0 | 2 |
