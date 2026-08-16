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

import argparse
import json
import logging
import os
import pathlib
import platform
import zipfile
from datetime import datetime
from typing import Any

import psycopg

import geoscape
import settings


def main():
    full_start_time = datetime.now().astimezone()

    # connect to Postgres
    try:
        pg_conn = psycopg.connect(settings["pg_connect_string"])
    except psycopg.Error:
        logger.fatal("Unable to connect to database\nACTION: Check your Postgres parameters and/or database security")
        return False

    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()

    # log postgres/postgis versions being used
    geoscape.check_postgis_version(pg_cur, settings, logger)

    logger.info("")

    # get SRID of locality boundaries
    sql = geoscape.prep_sql(f"select Find_SRID('{settings['admin_bdys_schema']}', 'locality_bdys', 'geom')", settings)
    pg_cur.execute(sql)
    settings['srid'] = int(pg_cur.fetchone()[0])
    if settings['srid'] == 4283:
        logger.info(f"Locality boundary coordinate system is EPSG:{settings['srid']} (GDA94)")
    elif settings['srid'] == 7844:
        logger.info(f"Locality boundary coordinate system is EPSG:{settings['srid']} (GDA2020)")
    else:
        logger.fatal("Invalid coordinate system (SRID) - EXITING!\nValid values are 4283 (GDA94) and 7844 (GDA2020)")
        exit()

    # add Postgres functions to clean out non-polygon geometries from GeometryCollections
    pg_cur.execute(geoscape.open_sql_file("create-polygon-intersection-function.sql", settings)
                   .format(settings['srid']))
    pg_cur.execute(geoscape.open_sql_file("create-multi-linestring-split-function.sql", settings))

    # let's build some clean localities!
    logger.info("")
    create_states_and_prep_localities(settings)
    get_split_localities(pg_cur, settings)
    verify_locality_polygons(pg_cur, settings)
    get_locality_state_border_gaps(pg_cur, settings)
    finalise_display_localities(pg_cur, settings)
    create_display_postcodes(pg_cur, settings)
    export_display_localities(pg_cur, settings)
    qa_display_localities(pg_cur, settings)

    pg_cur.close()
    pg_conn.close()

    logger.info(f"Total time : {datetime.now().astimezone() - full_start_time}")

    return True


def create_states_and_prep_localities(settings):
    start_time = datetime.now().astimezone()
    sql_list = [geoscape.open_sql_file("01a-create-states-from-sa4s.sql", settings).format(settings['srid']),
                geoscape.open_sql_file("01b-prep-locality-boundaries.sql", settings).format(settings['srid'])]
    geoscape.multiprocess_list("sql", sql_list, settings, logger)
    logger.info("\t- Step 1 of 8 : state table created & localities prepped : {0}".format(datetime.now().astimezone() - start_time))


# split locality bdys by state bdys, using multiprocessing
def get_split_localities(pg_cur, settings):
    start_time = datetime.now().astimezone()
    sql = geoscape.open_sql_file("02-split-localities-by-state-borders.sql", settings)
    sql_list = geoscape.split_sql_into_list(pg_cur, sql, settings['admin_bdys_schema'], "temp_localities", "loc", "gid",
                                            settings, logger)
    if sql_list:
        geoscape.multiprocess_list("sql", sql_list, settings, logger)
    
    logger.info("\t- Step 2 of 8 : localities split by state : {0}".format(datetime.now().astimezone() - start_time))


def verify_locality_polygons(pg_cur, settings):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("03a-verify-split-polygons.sql", settings).format(settings['srid']))
    pg_cur.execute(geoscape.open_sql_file("03b-load-messy-centroids.sql", settings))

    # convert messy centroids to GDA2020 if required
    if settings['srid'] == 7844:
        pg_cur.execute(geoscape.open_sql_file("03c-load-messy-centroids-gda2020.sql", settings))

    logger.info("\t- Step 3 of 8 : messy locality polygons verified : {0}".format(datetime.now().astimezone() - start_time))


# get holes in the localities along the state borders, using multiprocessing (doesn't help much - too few states!)
def get_locality_state_border_gaps(pg_cur, settings):
    start_time = datetime.now().astimezone()
    sql = geoscape.open_sql_file("04-create-holes-along-borders.sql", settings)
    sql_list = geoscape.split_sql_into_list(pg_cur, sql, settings['admin_bdys_schema'],
                                            "temp_state_border_buffers_subdivided", "ste", "new_gid", settings, logger)
    if sql_list:
        geoscape.multiprocess_list("sql", sql_list, settings, logger)
    
    logger.info("\t- Step 4 of 8 : locality holes created : {0}".format(datetime.now().astimezone() - start_time))


def finalise_display_localities(pg_cur, settings):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("05-finalise-display-localities.sql", settings).format(settings['srid']))
    logger.info("\t- Step 5 of 8 : display localities finalised : {0}".format(datetime.now().astimezone() - start_time))


def create_display_postcodes(pg_cur, settings):
    start_time = datetime.now().astimezone()
    pg_cur.execute(geoscape.open_sql_file("06-create-display-postcodes.sql", settings).format(settings['srid']))
    logger.info("\t- Step 6 of 8 : display postcodes created : {0}".format(datetime.now().astimezone() - start_time))


def export_display_localities(pg_cur, settings):
    start_time = datetime.now().astimezone()

    # create export path
    pathlib.Path(settings['output_path']).mkdir(parents=True, exist_ok=True)

    sql = geoscape.open_sql_file("07-export-display-localities.sql", settings)

    if platform.system() == "Windows":
        password_str = "SET"
    else:
        password_str = "export"

    password_str += " PGPASSWORD={0}&&".format(settings['pg_password'])

    cmd = password_str + "pgsql2shp -f \"{0}\" -u {1} -h {2} -p {3} {4} \"{5}\""\
        .format(settings['shapefile_export_path'], settings['pg_user'], settings['pg_host'],
                settings['pg_port'], settings['pg_db'], sql)

    # logger.info(cmd
    geoscape.run_command_line(cmd)

    # zip shapefile
    if settings['srid'] == 4283:
        shp_zip_path = settings['shapefile_name'] + "-shapefile.zip"
    else:
        shp_zip_path = settings['shapefile_name'] + "-gda2020-shapefile.zip"

    output_zipfile = os.path.join(settings['output_path'], shp_zip_path)
    zf = zipfile.ZipFile(output_zipfile, mode="w")

    for ext in settings['shapefile_extensions']:
        file_name = settings['shapefile_name'] + ext
        file_path = os.path.join(settings['output_path'], file_name)
        zf.write(file_path, file_name, compress_type=zipfile.ZIP_DEFLATED)

    zf.close()

    time_elapsed = datetime.now().astimezone() - start_time

    logger.info("\t- Step 7 of 8 : display localities exported to SHP : {0}".format(time_elapsed))
    if time_elapsed.seconds < 2:
        logger.warning("\t\t- This step took < 2 seconds - it may have failed silently. "
                       "Check your output directory!")

    start_time = datetime.now().astimezone()

    # Export as GeoJSON FeatureCollection
    sql = geoscape.prep_sql("SELECT gid, locality_pid, locality_name, COALESCE(postcode, '') AS postcode, state, "
                            "locality_class, address_count, street_count, ST_AsGeoJSON(geom, 5, 0) AS geom "
                            "FROM {0}.locality_bdys_display".format(settings['admin_bdys_schema']), settings)
    pg_cur.execute(sql)

    # Create the GeoJSON output with an array of dictionaries containing the field names and values

    # get column names from cursor
    column_names = [desc[0] for desc in pg_cur.description]

    json_dicts = []
    row = pg_cur.fetchone()

    if row is not None:
        while row is not None:
            rec = {}
            props = {}
            i = 0
            rec["type"] = "Feature"

            for column in column_names:
                if column == "geometry" or column == "geom":
                    rec["geometry"] = row[i]
                else:
                    props[column] = row[i]

                i += 1

            rec["properties"] = props
            json_dicts.append(rec)
            row = pg_cur.fetchone()

    gj = json.dumps(json_dicts).replace("\\", "").replace('"{', '{').replace('}"', '}')

    geojson = ''.join(['{"type":"FeatureCollection","features":', gj, '}'])

    text_file = open(settings['geojson_export_path'], "w")
    text_file.write(geojson)
    text_file.close()

    # compress GeoJSON
    if settings['srid'] == 4283:
        geojson_zip_path = settings['geojson_export_path'].replace(".geojson", "-geojson.zip")
    else:
        geojson_zip_path = settings['geojson_export_path'].replace(".geojson", "-gda2020-geojson.zip")

    zipfile.ZipFile(geojson_zip_path, mode="w")\
        .write(settings['geojson_export_path'], compress_type=zipfile.ZIP_DEFLATED)

    logger.info("\t- Step 7 of 8 : display localities exported to GeoJSON : {0}".format(datetime.now().astimezone() - start_time))


def qa_display_localities(pg_cur, settings):
    logger.info("\t- Step 8 of 8 : Start QA")
    start_time = datetime.now().astimezone()

    pg_cur.execute(geoscape.prep_sql("SELECT locality_pid, locality_name, coalesce(postcode, '') as postcode, state, "
                                     "address_count, street_count "
                                     "FROM admin_bdys.locality_bdys_display WHERE NOT ST_IsValid(geom);", settings))
    display_qa_results("Invalid Geometries", pg_cur)

    pg_cur.execute(geoscape.prep_sql("SELECT locality_pid, locality_name, coalesce(postcode, '') as postcode, state, "
                                     "address_count, street_count "
                                     "FROM admin_bdys.locality_bdys_display WHERE ST_IsEmpty(geom);", settings))
    display_qa_results("Empty Geometries", pg_cur)

    pg_cur.execute(geoscape.open_sql_file("08-qa-display-localities.sql", settings))
    display_qa_results("Dropped Localities", pg_cur)

    logger.info("\t- Step 8 of 8 : display localities qa'd : {0}".format(datetime.now().astimezone() - start_time))


def display_qa_results(purpose, pg_cur):
    logger.info("\t\t----------------------------------------")
    logger.info("\t\t" + purpose)

    rows = pg_cur.fetchall()

    if rows is not None and len(rows) > 0:
        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")
        logger.info("\t\t| {:17} | {:40} | {:8} | {:5} | {:13} | {:12} |"
                    .format("locality_pid", "locality_name", "postcode", "state", "address_count", "street_count"))
        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")

        for row in rows:
            logger.info("\t\t| {:17} | {:40} | {:8} | {:5} | {:13} | {:12} |"
                        .format(row[0], row[1], row[2], row[3], row[4], row[5]))

        logger.info("\t\t----------------------------------------------------------------------------------------"
                    "--------------------------")
    else:
        logger.info("\t\t" + "No records")


if __name__ == '__main__':
    logger = logging.getLogger()

    # set logger
    log_file = os.path.abspath(__file__).replace(".py", ".log")
    logging.basicConfig(filename=log_file, level=logging.DEBUG, format="%(asctime)s %(message)s",
                        datefmt="%m/%d/%Y %I:%M:%S %p")

    # setup logger to write to screen as well as writing to log file
    # define a Handler which writes INFO messages or higher to the sys.stderr
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    # set a format which is simpler for console use
    formatter = logging.Formatter('%(name)-12s: %(levelname)-8s %(message)s')
    # tell the handler to use this format
    console.setFormatter(formatter)
    # add the handler to the root logger
    logging.getLogger('').addHandler(console)

    logger.info("")
    logger.info("Start locality-clean")
    geoscape.check_python_version(logger)

    if main():
        logger.info("Finished successfully!")
    else:
        logger.fatal("Something bad happened!")

    logger.info("")
    logger.info("-------------------------------------------------------------------------------")
