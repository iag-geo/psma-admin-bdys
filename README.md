# psma-admin-bdys
Some utils to make it easier to use the PSMA's Administrative Boundaries

## clean-localities
A Python script for creating a clean version of the Suburb-Locality boundaries for presentation or visualisation.

Trims the boundaries to the coastline; fixes state border overlaps and gaps; and thins the boundaries for faster display performance in desktop GIS tools and in browsers.

### I Just Want the Data!

Ok, here it is: 


### Pre-requisites

- You will need to have either: run the gnaf-loader script; or loaded the gnaf-loader admin-bdys schema and data into Postgres (see https://github.com/minus34/gnaf-loader)
- Postgres 9.x (tested on 9.3, 9.4 & 9.5 on Windows and 9.5 on OSX)
- PostGIS 2.1+ 
- Python 2.7.x with Psycopg2 2.6.x

### Missing localities
Trimming the boundaries to the coastline comes at the cost of a small number of bay or estuary based localities (with very few 'addresses'), these are:

