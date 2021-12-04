### November 2021 Release
- Existing locality_pids have been replaced by Geoscape
- Removed `old_pid` field from exported _locality_bdy_display_ Shapefile. The GNAF old locality_pid lookup table was a one off in the 202108 release

### August 2021 Release
- Existing locality_pids have been replaced by Geoscape
- Added `old_pid` field to exported _locality_bdy_display_ Shapefile, representing the old locality pids

### May 2021 Release
- Renamed all references to PSMA to Geoscape, reflecting the new data provider's name

### November 2017 Release
- Postcode display boundaries are now also created - note: these postcodes are approximations from GNAF addresses and are very close to the real thing, but they are not authoritative

### August 2017 Release
- Locality boundaries are now trimmed to the coastline using ABS Census 2016 SA4 boundaries
- To use the ABS Census 2011 SA4 table as per before - supply the following argument: `--sa4-boundary-table abs_2011_sa4`

### November 2016 Release
- Logging is now written to locality-clean.log in your local repo directory as well as to the console 
- Added `--geoscape-version` to the parameters. Represents the PSMA version number in YYYYMM format and is used to add a suffix to the default schema names. Defaults to current year and latest release month. e.g. `201611`. Valid values are `<year>02` `<year>05` `<year>08` `<year>11`, and is based on the Geoscape quarterly release months 
- All default schema names are now suffixed with `--geoscape-version` to avoid clashes with previous versions. e.g. `gnaf_201705`
- locality-clean.py now works with Python 2.7 and Python 3.5
- locality-clean.py has been successfully tested on Postgres 9.6 and PostGIS 2.3
    - Note: Limited performance testing on Postgres 9.6 has shown setting the maximum number of parallel processes `--max-processes` to 3 is the most efficient value on non-SSD machines
- Code has been refactored to simplify it a bit and move some common functions to a new psma.py file
