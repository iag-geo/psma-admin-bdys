# *********************************************************************************************************************
# locality-clean.py
# *********************************************************************************************************************
#
# Takes the already processed locality_boundaries from the gnaf-loader (see https://github.com/minus34/gnaf-loader) and
# prepares them for presentation and visualisation, by doing the following:
#  1. Trims the localities to the coastline;
#  2. Cleans the overlaps and gaps at each state border;
#  3. Thins the polygons to for faster display in both desktop GIS tolls and in browsers; and
#  4. Exports the result to a Shapefile
#
# Organisation: IAG
# Author: Hugh Saalmans, Location Science Manager
# GitHub: iag-geo
#
# Version: 0.9
# Date: 22-02-2016
#
# Copyright:
#  - Code is copyright IAG - licensed under an Apache License, version 2.0
#  - Data is copyright PSMA - licensed under a Creative Commons (By Attribution) license
#
# Pre-requisites
#  - Either: run the gnaf-loader Python script (30-60 mins); or load the gnaf-loader admin-bdys schema into Postgres
#      (see https://github.com/minus34/gnaf-loader)
#  - Postgres 9.x (tested on 9.3, 9.4 & 9.5 on Windows and 9.5 on OSX)
#  - PostGIS 2.2
#  - Python 2.7.x with Psycopg2 2.6.x
#
# TO DO:
#  - Refactor the scripts in the 05-finalise-display-localities.sql file
#  - Create postcode boundaries by aggregating the final localities by their postcode (derived from raw GNAF)
#  - Add a QA section to confirm to invalid geometries in final table and list the missing water based localities
#  - Drop all the temporary tables created in the process
#
# *********************************************************************************************************************

import json
import multiprocessing
import math
import os
import subprocess
import platform
import psycopg2

from datetime import datetime

# *********************************************************************************************************************
# Edit these parameters to taste - START
# *********************************************************************************************************************

# what are the maximum parallel processes you want to use for the data load?
# (set it to the number of cores on the Postgres server minus 2, limit to 12 if 16+ cores - minimal benefit beyond 12)
max_concurrent_processes = 6

# Postgres parameters. These will also respect the standard PGHOST/PGPORT/etc environment variables if set.
pg_host = os.getenv("PGHOST", "localhost")
pg_port = os.getenv("PGPORT", 5432)
pg_db = os.getenv("PGDATABASE", "psma_201602")
pg_user = os.getenv("PGUSER", "postgres")
pg_password = os.getenv("PGPASSWORD", "password")

# schema names for the raw and processed admin boundary tables
raw_admin_bdys_schema = "raw_admin_bdys"
admin_bdys_schema = "admin_bdys"

# full path and file name to export the resulting Shapefile to
shapefile_export_path = r"C:\temp\psma_201602\locality_bdys_display.shp"
geojson_export_path = r"C:\temp\psma_201602\locality_bdys_display.geojson"

# *********************************************************************************************************************
# Edit these parameters to taste - END
# *********************************************************************************************************************

# create postgres connect string
pg_connect_string = "dbname='{0}' host='{1}' port='{2}' user='{3}' password='{4}'"\
    .format(pg_db, pg_host, pg_port, pg_user, pg_password)

# set postgres script directory
sql_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), "postgres-scripts")


def main():
    full_start_time = datetime.now()

    print ""
    print "Started : {0}".format(full_start_time)

    # connect to Postgres
    try:
        pg_conn = psycopg2.connect(pg_connect_string)
        pg_conn.autocommit = True
        pg_cur = pg_conn.cursor()
    except psycopg2.Error:
        print "Unable to connect to database\nACTION: Check your Postgres parameters and/or database security"
        return False

    # add Postgres functions to clean out non-polygon geometries from GeometryCollections
    pg_cur.execute(open_sql_file("create-polygon-intersection-function.sql"))
    pg_cur.execute(open_sql_file("create-multi-linestring-split-function.sql"))

    # let's build some clean localities!
    create_states_and_prep_localities()
    get_split_localities(pg_cur)
    verify_locality_polygons(pg_cur)
    get_locality_state_border_gaps(pg_cur)
    finalise_display_localities(pg_cur)
    export_display_localities(pg_cur)
    qa_display_localities(pg_cur)

    pg_cur.close()
    pg_conn.close()

    print "Total time : {0}".format(datetime.now() - full_start_time)


def create_states_and_prep_localities():
    start_time = datetime.now()
    sql_list = [open_sql_file("01a-create-states-from-sa4s.sql"), open_sql_file("01b-prep-locality-boundaries.sql")]
    multiprocess_list(2, "sql", sql_list)
    print "\t- Step 1 of 7 : state table created & localities prepped : {0}".format(datetime.now() - start_time)


# split locality bdys by state bdys, using multiprocessing
def get_split_localities(pg_cur):
    start_time = datetime.now()
    sql = open_sql_file("02-split-localities-by-state-borders.sql")
    split_sql_into_list_and_process(pg_cur, sql, admin_bdys_schema, "temp_localities", "loc", "gid")
    print "\t- Step 2 of 7 : localities split by state : {0}".format(datetime.now() - start_time)


def verify_locality_polygons(pg_cur):
    start_time = datetime.now()
    pg_cur.execute(open_sql_file("03a-verify-split-polygons.sql"))
    pg_cur.execute(open_sql_file("03b-load-messy-centroids.sql"))
    print "\t- Step 3 of 7 : messy locality polygons verified : {0}".format(datetime.now() - start_time)


# get holes in the localities along the state borders, using multiprocessing (doesn't help much - too few states!)
def get_locality_state_border_gaps(pg_cur):
    start_time = datetime.now()
    sql = open_sql_file("04-create-holes-along-borders.sql")
    split_sql_into_list_and_process(pg_cur, sql, admin_bdys_schema, "temp_state_border_buffers_subdivided",
                                    "ste", "new_gid")
    print "\t- Step 4 of 7 : locality holes created : {0}".format(datetime.now() - start_time)


def finalise_display_localities(pg_cur):
    start_time = datetime.now()
    pg_cur.execute(open_sql_file("05-finalise-display-localities.sql"))
    print "\t- Step 5 of 7 : display localities finalised : {0}".format(datetime.now() - start_time)


def export_display_localities(pg_cur):
    start_time = datetime.now()

    sql = open_sql_file("06-export-display-localities.sql")

    if platform.system() == "Windows":
        password_str = "SET"
    else:
        password_str = "export"

    password_str += " PGPASSWORD={0}&&".format(pg_password)

    cmd = password_str + "pgsql2shp -f \"{0}\" -u {1} -h {2} -p {3} {4} \"{5}\""\
        .format(shapefile_export_path, pg_user, pg_host, pg_port, pg_db, sql)

    # print cmd
    run_command_line(cmd)

    print "\t- Step 6 of 7 : display localities exported to SHP : {0}".format(datetime.now() - start_time)
    print "\t\t- IMPORTANT - if this step took < 1 second - it may have failed silently. Check your output directory!"
    start_time = datetime.now()

    # Export as GeoJSON FeatureCollection
    sql = prep_sql("SELECT gid, locality_pid, locality_name, COALESCE(postcode, '') AS postcode, state, "
                   "locality_class, address_count, street_count, ST_AsGeoJSON(geom, 5, 0) AS geom "
                   "FROM admin_bdys.locality_bdys_display")
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

    text_file = open(geojson_export_path, "w")
    text_file.write(geojson)
    text_file.close()

    print "\t- Step 6 of 7 : display localities exported to GeoJSON : {0}".format(datetime.now() - start_time)


def qa_display_localities(pg_cur):
    print "\t- Step 7 of 7 : Start QA"
    start_time = datetime.now()

    pg_cur.execute(prep_sql("SELECT locality_pid, Locality_name, postcode, state, address_count, street_count "
                            "FROM admin_bdys.locality_bdys_display WHERE NOT ST_IsValid(geom);"))
    display_qa_results("Invalid Geometries", pg_cur)

    pg_cur.execute(prep_sql("SELECT locality_pid, Locality_name, postcode, state, address_count, street_count "
                            "FROM admin_bdys.locality_bdys_display WHERE ST_IsEmpty(geom);"))
    display_qa_results("Empty Geometries", pg_cur)

    pg_cur.execute(open_sql_file("07-qa-display-localities.sql"))
    display_qa_results("Dropped Localities", pg_cur)

    print "\t- Step 7 of 7 : display localities qa'd : {0}".format(datetime.now() - start_time)


# takes a list of sql queries or command lines and runs them using multiprocessing
def multiprocess_list(concurrent_processes, mp_type, work_list):
    pool = multiprocessing.Pool(processes=concurrent_processes)

    if mp_type == "sql":
        results = pool.imap_unordered(run_sql_multiprocessing, work_list)
    else:
        results = pool.imap_unordered(run_command_line, work_list)

    pool.close()
    pool.join()

    for result in results:
        if result is not None:
            print result


def run_sql_multiprocessing(sql):

    pg_conn = psycopg2.connect(pg_connect_string)
    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()

    try:
        pg_cur.execute(sql)
    except psycopg2.Error, e:
        return "SQL FAILED! : {0} : {1}".format(sql, e.message)

    pg_cur.close()
    pg_conn.close()

    return None


def run_command_line(cmd):
    # run the command line without any output (it'll still tell you if it fails)
    try:
        fnull = open(os.devnull, "w")
        subprocess.call(cmd, shell=True, stdout=fnull, stderr=subprocess.STDOUT)
    except Exception, e:
        return "COMMAND FAILED! : {0} : {1}".format(cmd, e.message)

    return None


def open_sql_file(file_name):
    sql = open(os.path.join(sql_dir, file_name), "r").read()
    return prep_sql(sql)


# # change schema names in an array of SQL script if schemas not the default
# def prep_sql_list(sql_list):
#     output_list = []
#     for sql in sql_list:
#         output_list.append(prep_sql(sql))
#     return output_list


# change schema names in the SQL script if not the default
def prep_sql(sql):
    if raw_admin_bdys_schema != "raw_admin_bdys":
        sql = sql.replace(" raw_admin_bdys.", " {0}.".format(raw_admin_bdys_schema,))
    if admin_bdys_schema != "admin_bdys":
        sql = sql.replace(" admin_bdys.", " {0}.".format(admin_bdys_schema,))
    return sql


def split_sql_into_list_and_process(pg_cur, the_sql, table_schema, table_name, table_alias, table_gid):
    # get min max gid values from the table to split
    min_max_sql = "SELECT MIN({2}) AS min, MAX({2}) AS max FROM {0}.{1}".format(table_schema, table_name, table_gid)

    pg_cur.execute(min_max_sql)
    result = pg_cur.fetchone()

    min_pkey = int(result[0])
    max_pkey = int(result[1])
    diff = max_pkey - min_pkey

    # Number of records in each query
    rows_per_request = int(math.floor(float(diff) / float(max_concurrent_processes))) + 1

    # If less records than processes or rows per request, reduce both to allow for a minimum of 15 records each process
    if float(diff) / float(max_concurrent_processes) < 10.0:
        rows_per_request = 10
        processes = int(math.floor(float(diff) / 10.0)) + 1
        print "\t\t- running {0} processes (adjusted due to low row count in table to split)".format(processes)
    else:
        processes = max_concurrent_processes
        # print "\t\t- running {0} processes".format(processes)

    # create list of sql statements to run with multiprocessing
    sql_list = []
    start_pkey = min_pkey - 1

    for i in range(0, processes):
        end_pkey = start_pkey + rows_per_request

        where_clause = " WHERE {0}.{3} > {1} AND {0}.{3} <= {2}".format(table_alias, start_pkey, end_pkey, table_gid)

        if "WHERE " in the_sql:
            mp_sql = the_sql.replace(" WHERE ", where_clause + " AND ")
        elif "GROUP BY " in the_sql:
            mp_sql = the_sql.replace("GROUP BY ", where_clause + " GROUP BY ")
        elif "ORDER BY " in the_sql:
            mp_sql = the_sql.replace("ORDER BY ", where_clause + " ORDER BY ")
        else:
            mp_sql = the_sql.replace(";", where_clause + ";")

        sql_list.append(mp_sql)
        start_pkey = end_pkey

    # print '\n'.join(sql_list)
    multiprocess_list(processes, 'sql', sql_list)


def display_qa_results(purpose, pg_cur):
    print "\t\t" + purpose
    print "\t\t----------------------------------------"

    results = pg_cur.fetchall()

    if results is not None:
        # Print the column names returned
        print "\t\t" + ",".join([desc[0] for desc in pg_cur.description])

        for result in results:
            print "\t\t" + ",".join(map(str,result))
    else:
        print "\t\t" + "No records"

    print "\t\t----------------------------------------"


if __name__ == '__main__':
    main()
