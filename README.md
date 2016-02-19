# psma-admin-bdys
Some utils to make it easier to use the PSMA's Administrative Boundaries

## clean-localities
A Python script for creating a clean version of the Suburb-Locality boundaries for presentation or visualisation.

It trims the boundaries to the coastline; fixes state border overlaps and gaps; and thins the boundaries for improved display performance on both desktop and in browser.

### Pre-requisites

- You will need to have either: run the gnaf-loader script; or loaded the gnaf-loader admin-bdys schema and data into Postgres
- Postgres 9.x (tested on 9.3, 9.4 & 9.5 on Windows and 9.5 on OSX)
- PostGIS 2.x
- Python 2.7.x with Psycopg2 2.6.x

### Missing localities
Trimming the boundaries to the coastline comes at the costs of a small number of bay or estuary based localities, these are:

