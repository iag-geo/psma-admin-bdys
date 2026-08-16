# takes the command line parameters and creates a dictionary of setting_dict

import argparse
import os
import platform
import sys
from datetime import datetime

import psycopg
from psycopg import sql


# get latest Geoscape release version as YYYYMM, as of the date provided, as well as the prev. version 3 months prior
def get_geoscape_version(date: datetime) -> tuple[str, str]:
    month = date.month
    year = date.year

    if month == 1:
        gs_version = str(year - 1) + "11"
        previous_gs_version = str(year - 1) + "08"
    elif 2 <= month < 5:
        gs_version = str(year) + "02"
        previous_gs_version = str(year - 1) + "11"
    elif 5 <= month < 8:
        gs_version = str(year) + "05"
        previous_gs_version = str(year) + "02"
    elif 8 <= month < 11:
        gs_version = str(year) + "08"
        previous_gs_version = str(year) + "05"
    else:
        gs_version = str(year) + "11"
        previous_gs_version = str(year) + "08"

    return gs_version, previous_gs_version


# get python, psycopg and OS versions
python_version = sys.version.split("(")[0].strip()
psycopg_version = psycopg.__version__.split("(")[0].strip()
os_version = platform.system() + " " + platform.version().strip()

parser = argparse.ArgumentParser(
    description='A quick way to load the complete GNAF and Geoscape Admin Boundaries into Postgres, '
                'simplified and ready to use as reference data for geocoding, analysis and visualisation.')

parser.add_argument(
    '--max-processes', type=int, default=3,
    help='Maximum number of parallel processes to use for the data load. (Set it to the number of cores on the '
            'Postgres server minus 2, limit to 12 if 16+ cores - there is minimal benefit beyond 12). Defaults to 6.')

# parser.add_argument(
#     "--srid", type=int, default=4283,
#     help="Sets the coordinate system of the input data. Valid values are 4283 (GDA94) and 7844 (GDA2020)")

# PG Options
parser.add_argument(
    '--pghost',
    help='Host name for Postgres server. Defaults to PGHOST environment variable if set, otherwise localhost.')
parser.add_argument(
    '--pgport', type=int,
    help='Port number for Postgres server. Defaults to PGPORT environment variable if set, otherwise 5432.')
parser.add_argument(
    '--pgdb',
    help='Database name for Postgres server. Defaults to PGDATABASE environment variable if set, '
            'otherwise geo.')
parser.add_argument(
    '--pguser',
    help='Username for Postgres server. Defaults to PGUSER environment variable if set, otherwise postgres.')
parser.add_argument(
    '--pgpassword',
    help='Password for Postgres server. Defaults to PGPASSWORD environment variable if set, '
            'otherwise \'password\'.')

# schema names for the raw gnaf, flattened reference and admin boundary tables
geoscape_version = get_geoscape_version(datetime.today().astimezone())

parser.add_argument(
    "--geoscape-version", default=geoscape_version,
    help=f"Geoscape release version number as YYYYMM. Defaults to latest release year and month '{geoscape_version}'.")
parser.add_argument(
    "--admin-schema",
    help=f"Destination schema name to store final admin boundary tables in. Defaults to 'admin_bdys_{geoscape_version}'.")
parser.add_argument(
    '--sa4-boundary-table', default='abs_2026_sa4',
    help='SA4 table name used to create state boundaries. '
            'Defaults to \'abs_2026_sa4\'. Other options are: \'abs_2021_sa4\'')

# output directory
parser.add_argument(
    '--output-path', required=True,
    help='Local path where the Shapefile and GeoJSON files will be output.')
parser.add_argument(
    "--log-path",
    help="Optional directory for the loader log file. Defaults to a log file beside load-gnaf.py.")

# global var containing all input parameters
args = parser.parse_args()

# assign parameters to global settings

max_processes = args.max_processes
geoscape_version = args.geoscape_version
sa4_boundary_table = args.sa4_boundary_table
output_path = args.output_path
log_path = args.log_path

admin_bdys_schema = sql.Identifier(args.admin_schema or "admin_bdys_" + geoscape_version)

# create postgres connect string
pg_host = args.pghost or os.getenv("PGHOST", "localhost")
pg_port = int(args.pgport or os.getenv("PGPORT", '5432'))
pg_db = args.pgdb or os.getenv("PGDATABASE", "geoscape")
pg_user = sql.Identifier(args.pguser or os.getenv("PGUSER", "postgres"))
pg_password = args.pgpassword or os.getenv("PGPASSWORD", "password")

pg_connect_string = f"dbname='{pg_db}' host='{pg_host}' port='{pg_port}' user='{pg_user}' password='{pg_password}'"

# set postgres script directory
sql_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "postgres-scripts")

# full path and file name to export the resulting Shapefile to
shapefile_export_path = os.path.join(output_path, f"locality-bdys-display-{geoscape_version}.shp")
shapefile_name = f"locality-bdys-display-{geoscape_version}"
shapefile_extensions = [".cpg", ".dbf", ".prj", ".shp", ".shx"]

geojson_export_path = os.path.join(output_path, f"locality-bdys-display-{geoscape_version}.geojson")

# get Postgres, PostGIS & GEOS versions and flag if ST_Subdivide is supported

# get Postgres connection & cursor
temp_pg_conn = psycopg.connect(pg_connect_string)
temp_pg_cur = temp_pg_conn.cursor()

# get Postgres version
temp_pg_cur.execute("SELECT version()")
pg_version = str(temp_pg_cur.fetchone()[0]).replace("PostgreSQL ", "").split(",")[0] # type: ignore

# get PostGIS version
temp_pg_cur.execute("SELECT PostGIS_full_version()")
lib_strings = str(temp_pg_cur.fetchone()[0]).replace("\"", "").split(" ") # type: ignore

temp_pg_cur.close()
temp_pg_cur = None
temp_pg_conn.close()
temp_pg_conn = None

postgis_version = "UNKNOWN"
postgis_version_num = 0.0
geos_version = "UNKNOWN"
geos_version_num = 0.0

st_subdivide_supported = False

postgis_version_num = list[int]()
geos_version_num = list[int]()

for lib_string in lib_strings:
    if lib_string[:8] == "POSTGIS=":
        postgis_version = lib_string.replace("POSTGIS=", "")
        postgis_version_num = [int(v) for v in postgis_version.split('.') if v.isdigit()]
    if lib_string[:5] == "GEOS=":
        geos_version = lib_string.replace("GEOS=", "")
        # Parse for numeric parts of GEOS version,
        # handling (for eg. '3.10.2-CAPI-1.16.0') well enough to get the major/minor version
        geos_version_num = [int(v) for v in geos_version.split('.') if v.isdigit()]

if (postgis_version_num[0] > 2 or (postgis_version_num[0] == 2 and postgis_version_num[1] >= 2)) and \
   (geos_version_num[0] > 3 or (geos_version_num[0] == 3 and geos_version_num[1] >= 5)):
    st_subdivide_supported = True
