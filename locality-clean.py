# *********************************************************************************************************************
# locality-clean.py
# *********************************************************************************************************************
#
# Takes the already processed locality_boundaries from the gnaf-loader (see https://github.com/minus34/gnaf-loader) and
# prepares them for presentation and visualisation, by doing the following:
#  1. Trims the localities to the coastline;
#  2. Cleans the overlaps and gaps along each state border;
#  3. Thins the polygons to for faster display in both desktop GIS and in browsers; and
#  4. Exports the end result to Shapefile and GeoJSON (for use in Elasticsearch)
#
# Organisation: IAG
# Author: Hugh Saalmans, Location Engineering Director
# GitHub: iag-geo
#
# Copyright:
#  - Code is copyright IAG - licensed under an Apache License, version 2.0
#  - Data is copyright Geoscape - licensed under a Creative Commons (By Attribution) license
#
# Pre-requisites
#  - Either: run the gnaf-loader Python script (30-90 mins); or load the gnaf-loader admin-bdys schema into Postgres
#      (see https://github.com/minus34/gnaf-loader)
#  - Postgres 14.x
#  - PostGIS 3+
#  - Python 3.11 with Psycopg
#
# *********************************************************************************************************************

import json
import logging
import os
import pathlib
import platform
import sys
import zipfile
from datetime import datetime
from typing import Any

import psycopg

import geoscape
import settings


def main():
    full_start_time = datetime.now().astimezone()

    # log Python and OS versions
    logger.info(f"\t- running Python {settings.python_version} with psycopg {settings.psycopg_version}")
    logger.info(f"\t- on {settings.os_version}")

    # get Postgres connection & cursor
    pg_conn = psycopg.connect(settings.pg_connect_string)
    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()

    # add postgis to database (in the public schema) - run this in a try to confirm db user has privileges
    try:
        pg_cur.execute("SET search_path = public, pg_catalog; CREATE EXTENSION IF NOT EXISTS postgis")
    except psycopg.Error:
        logger.fatal("Unable to add PostGIS extension\nACTION: Check your Postgres user privileges or PostGIS install")
        return False

    # test if ST_Subdivide exists (only in PostGIS 2.2+). It's used to split boundaries for faster processing
    logger.info(f"\t- using Postgres {settings.pg_version} and PostGIS {settings.postgis_version} "
                f"(with GEOS {settings.geos_version})")

    # log the user's input parameters
    logger.info("")
    logger.info("Arguments")
    for arg in vars(settings.args):
        value = getattr(settings.args, arg)

        if value is not None:
            if arg != "pgpassword":
                logger.info(f"\t- {arg} : {value}")
            else:
                logger.info(f"\t- {arg} : ************")

    # get SRID of locality boundaries
    sql = geoscape.prep_sql(f"select Find_SRID('{settings.admin_bdys_schema}', 'locality_bdys', 'geom')")
    pg_cur.execute(sql) # type: ignore
    srid = int(pg_cur.fetchone()[0]) # type: ignore
    if srid == 4283:
        logger.info(f"Locality boundary coordinate system is EPSG:{srid} (GDA94)")
    elif srid == 7844:
        logger.info(f"Locality boundary coordinate system is EPSG:{srid} (GDA2020)")
    else:
        logger.fatal("Invalid coordinate system (SRID) - EXITING!\nValid values are 4283 (GDA94) and 7844 (GDA2020)")
        sys.exit()

    # add Postgres functions to clean out non-polygon geometries from GeometryCollections
    pg_cur.execute(geoscape.open_sql_file("create-polygon-intersection-function.sql").format(srid))  # type: ignore
    pg_cur.execute(geoscape.open_sql_file("create-multi-linestring-split-function.sql")) # type: ignore

    # let's build some clean localities!
    logger.info("")
    create_states_and_prep_localities(srid)
    get_split_localities(pg_cur)
    verify_locality_polygons(pg_cur, srid)
    get_locality_state_border_gaps(pg_cur)
    finalise_display_localities(pg_cur, srid)
    create_display_postcodes(pg_cur, srid)
    export_display_localities(pg_cur, srid)
    qa_display_localities(pg_cur)

    pg_cur.close()
    pg_conn.close()

    logger.info(f"Total time : {datetime.now().astimezone() - full_start_time}")

    return True


def create_states_and_prep_localities(srid: int):
    start_time = datetime.now().astimezone()
    sql_list = [geoscape.open_sql_file("01a-create-states-from-sa4s.sql").format(srid),
                geoscape.open_sql_file("01b-prep-locality-boundaries.sql").format(srid)]
    geoscape.multiprocess_list("sql", sql_list, logger)
    logger.info(f"\t- Step 1 of 8 : state table created & localities prepped : {datetime.now().astimezone() - start_time}")


# split locality bdys by state bdys, using multiprocessing
def get_split_localities(pg_cur: psycopg.Cursor):
    start_time = datetime.now().astimezone()
    sql = geoscape.open_sql_file("02-split-localities-by-state-borders.sql")
    sql_list = geoscape.split_sql_into_list(pg_cur, sql, settings.admin_bdys_schema, "temp_localities", "loc", "gid", logger)
    if sql_list:
        geoscape.multiprocess_list("sql", sql_list, logger)
    
    logger.info(f"\t- Step 2 of 8 : localities split by state : {datetime.now().astimezone() - start_time}")


def verify_locality_polygons(pg_cur: psycopg.Cursor, srid: int):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("03a-verify-split-polygons.sql").format(srid)) # type: ignore
    pg_cur.execute(geoscape.open_sql_file("03b-load-messy-centroids.sql")) # type: ignore

    # convert messy centroids to GDA2020 if required
    if srid == 7844:
        pg_cur.execute(geoscape.open_sql_file("03c-load-messy-centroids-gda2020.sql")) # type: ignore

    logger.info(f"\t- Step 3 of 8 : messy locality polygons verified : {datetime.now().astimezone() - start_time}")


# get holes in the localities along the state borders, using multiprocessing (doesn't help much - too few states!)
def get_locality_state_border_gaps(pg_cur: psycopg.Cursor):
    start_time = datetime.now().astimezone()
    sql = geoscape.open_sql_file("04-create-holes-along-borders.sql")
    sql_list = geoscape.split_sql_into_list(pg_cur, sql, settings.admin_bdys_schema,
                                            "temp_state_border_buffers_subdivided", "ste", "new_gid", logger)
    if sql_list:
        geoscape.multiprocess_list("sql", sql_list, logger)
    
    logger.info(f"\t- Step 4 of 8 : locality holes created : {datetime.now().astimezone() - start_time}")


def finalise_display_localities(pg_cur: psycopg.Cursor, srid: int):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("05-finalise-display-localities.sql").format(srid)) # type: ignore
    logger.info(f"\t- Step 5 of 8 : display localities finalised : {datetime.now().astimezone() - start_time}")


def create_display_postcodes(pg_cur: psycopg.Cursor, srid: int):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("06-create-display-postcodes.sql").format(srid)) # type: ignore
    logger.info(f"\t- Step 6 of 8 : display postcodes created : {datetime.now().astimezone() - start_time}")


def export_display_localities(pg_cur: psycopg.Cursor, srid: int):
    start_time = datetime.now().astimezone()

    # create export path
    pathlib.Path(settings.output_path).mkdir(parents=True, exist_ok=True)

    sql = geoscape.open_sql_file("07-export-display-localities.sql")

    if platform.system() == "Windows":
        password_str = "SET"
    else:
        password_str = "export"

    password_str += f" PGPASSWORD={settings.pg_password}&&"

    cmd = password_str + f"pgsql2shp -f \"{settings.shapefile_export_path}\" -u {settings.pg_user} -h {settings.pg_host} -p {settings.pg_port} {settings.pg_db} \"{sql}\""

    # logger.info(cmd
    geoscape.run_command_line(cmd)

    # zip shapefile
    if srid == 4283:
        shp_zip_path = settings.shapefile_name + "-shapefile.zip"
    else:
        shp_zip_path = settings.shapefile_name + "-gda2020-shapefile.zip"

    output_zipfile = os.path.join(settings.output_path, shp_zip_path)
    zf = zipfile.ZipFile(output_zipfile, mode="w")

    for ext in settings.shapefile_extensions:
        file_name = settings.shapefile_name + ext
        file_path = os.path.join(settings.output_path, file_name)
        zf.write(file_path, file_name, compress_type=zipfile.ZIP_DEFLATED)

    zf.close()

    time_elapsed = datetime.now().astimezone() - start_time

    logger.info(f"\t- Step 7 of 8 : display localities exported to SHP : {time_elapsed}")
    if time_elapsed.seconds < 2:
        logger.warning("\t\t- This step took < 2 seconds - it may have failed silently. Check your output directory!")

    start_time = datetime.now().astimezone()

    # Export as GeoJSON FeatureCollection
    sql_string = geoscape.prep_sql(f"SELECT gid, locality_pid, locality_name, COALESCE(postcode, '') AS postcode, state, locality_class, address_count, street_count, ST_AsGeoJSON(geom, 5, 0) AS geom FROM {settings.admin_bdys_schema}.locality_bdys_display")
    pg_cur.execute(sql_string) # type: ignore

    # Create the GeoJSON output with an array of dictionaries containing the field names and values

    # get column names from cursor
    column_names = [desc[0] for desc in pg_cur.description] # type: ignore

    json_dicts = list[dict[str, str]]()
    row = pg_cur.fetchone()

    if row is not None:
        while row is not None:
            rec = dict[str, Any]()
            props = dict[str, str]()
            rec["type"] = "Feature"

            for i, column in enumerate(column_names, start=0):
                if column == "geometry" or column == "geom":
                    rec["geometry"] = row[i]
                else:
                    props[column] = row[i]

            rec["properties"] = props
            json_dicts.append(rec)
            row = pg_cur.fetchone()

    gj = json.dumps(json_dicts).replace("\\", "").replace('"{', '{').replace('}"', '}')

    geojson = f'{{"type":"FeatureCollection","features":{gj}}}'

    with open(settings.geojson_export_path, "w") as text_file:
        text_file.write(geojson)

    # compress GeoJSON
    if srid == 4283:
        geojson_zip_path = settings.geojson_export_path.replace(".geojson", "-geojson.zip")
    else:
        geojson_zip_path = settings.geojson_export_path.replace(".geojson", "-gda2020-geojson.zip")

    zipfile.ZipFile(geojson_zip_path, mode="w")\
        .write(settings.geojson_export_path, compress_type=zipfile.ZIP_DEFLATED)

    logger.info(f"\t- Step 7 of 8 : display localities exported to GeoJSON : {datetime.now().astimezone() - start_time}")


def qa_display_localities(pg_cur: psycopg.Cursor):
    logger.info("\t- Step 8 of 8 : Start QA")
    start_time = datetime.now().astimezone()

    pg_cur.execute(geoscape.prep_sql("SELECT locality_pid, locality_name, coalesce(postcode, '') as postcode, state, "
                                     "address_count, street_count "
                                     "FROM admin_bdys.locality_bdys_display WHERE NOT ST_IsValid(geom);")) # type: ignore
    display_qa_results("Invalid Geometries", pg_cur)

    pg_cur.execute(geoscape.prep_sql("SELECT locality_pid, locality_name, coalesce(postcode, '') as postcode, state, "
                                     "address_count, street_count "
                                     "FROM admin_bdys.locality_bdys_display WHERE ST_IsEmpty(geom);")) # type: ignore
    display_qa_results("Empty Geometries", pg_cur)

    pg_cur.execute(geoscape.open_sql_file("08-qa-display-localities.sql")) # type: ignore
    display_qa_results("Dropped Localities", pg_cur)

    logger.info(f"\t- Step 8 of 8 : display localities qa'd : {datetime.now().astimezone() - start_time}")


def display_qa_results(purpose: str, pg_cur: psycopg.Cursor):
    logger.info("\t\t----------------------------------------")
    logger.info("\t\t" + purpose)

    rows = pg_cur.fetchall() # type: ignore

    if rows:
        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")
        logger.info(f"\t\t| {'locality_pid':17} | {'locality_name':40} | {'postcode':8} | {'state':5} | {'address_count':13} | {'street_count':12} |")
        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")

        for row in rows:
            logger.info(f"\t\t| {row[0]:17} | {row[1]:40} | {row[2]:8} | {row[3]:5} | {row[4]:13} | {row[5]:12} |")

        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")
    else:
        logger.info("\t\t" + "No records")


if __name__ == '__main__':
    logger = logging.getLogger()

    logger = logging.getLogger()

    file_time = datetime.now().astimezone()
    file_time_str = file_time.strftime("%Y-%m-%d-%H-%M-%S")

    # set logger
    if settings.log_path:
        os.makedirs(settings.log_path, exist_ok=True)
        log_file = os.path.join(settings.log_path, f"locality-clean-{file_time_str}.log")
    else:
        log_file = os.path.abspath(__file__).replace(".py", f"-{file_time_str}.log")
    logging.basicConfig(filename=log_file, level=logging.DEBUG, format="%(asctime)s %(message)s",
                        datefmt="%m/%d/%Y %I:%M:%S %p")

    # setup logger to write to screen as well as writing to log file
    # define a Handler which writes INFO messages or higher to the sys.stderr
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    # set a format which is simpler for console use
    formatter = logging.Formatter("%(name)-12s: %(levelname)-8s %(message)s")
    # tell the handler to use this format
    console.setFormatter(formatter)
    # add the handler to the root logger
    logging.getLogger("").addHandler(console)

    logger.info("")
    logger.info("Start locality-clean")

    if main():
        logger.info("Finished successfully!")
    else:
        logger.fatal("Something bad happened!")

    logger.info("")
    logger.info("-------------------------------------------------------------------------------")
