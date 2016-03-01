# psma-admin-bdys
Some utils to make it easier to use the PSMA's Administrative Boundaries

## locality-clean
A Python script for creating a clean version of the Suburb-Locality boundaries for presentation or visualisation.

Trims the boundaries to the coastline; fixes state border overlaps and gaps; and thins the boundaries for faster display performance in desktop GIS tools and in browsers.

![alt text](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/aus.png "clean vs original localities")
Clean localities (green) versus the original localities (yellow)


![alt text](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/original-borders.png "clean vs original borders")
![alt text](https://github.com/iag-geo/psma-admin-bdys/blob/master/sample-images/fixed-borders.png "clean borders")

### I Just Want the Data!

You can run this script to get the result or just download it from here:


TO DO : ADD URL FROM IAG S3 BUCKET


### Pre-requisites

- You will need to have either: run the gnaf-loader script; or loaded the gnaf-loader admin-bdys schema and data into Postgres (see https://github.com/minus34/gnaf-loader)
- Postgres 9.x (tested on 9.3, 9.4 & 9.5 on Windows and 9.5 on OSX)
- PostGIS 2.1+ 
- Python 2.7.x with Psycopg2 2.6.x

### Missing localities
Trimming the boundaries to the coastline requires a small number of bay or estuary based localities (that have very few 'addresses') to be removed.

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
