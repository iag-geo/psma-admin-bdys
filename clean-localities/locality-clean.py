# *********************************************************************************************************************
# load.gnaf.py
# *********************************************************************************************************************
#
# A script for loading raw GNAF & PSMA Admin boundaries and creating flattened, complete, easy to use versions of them
#
# Author: Hugh Saalmans
# GitHub: minus34
# Twitter: @minus34
#
# Version: 1.0.0
# Date: 22-02-2016
#
# Process:
#   1. Loads raw GNAF into Postgres from PSV files using COPY
#   2. Loads raw PSMA Admin Boundaries from Shapefiles into Postgres using shp2pgsql (part of PostGIS)
#   3. Creates flattened and simplified GNAF tables containing all relevant data
#   4. Creates a ready to use Locality Boundaries table containing a number of fixes to overcome known data issues
#   5. Splits the locality boundary for Melbourne into 2, one for each of its postcodes (3000 & 3004)
#   6. Creates final principal & alias address tables containing fixes based on the above locality customisations
#   7. Creates an almost correct Postcode Boundary table from locality boundary aggregates with address based postcodes
#   8. Adds primary and foreign keys to check for PID integrity across the reference tables
#
# TO DO:
# - create clean, web ready locality bdys
# - create ready-to-use versions of all admin bdys
# - boundary tag addresses for census bdys
# - boundary tag addresses for admin bdys
# - output reference tables to PSV & SHP
# - check address_alias_lookup record count
#
# *********************************************************************************************************************

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

# what's the maximum parallel processes you want to use for the data load?
# (set it to the number of cores on the Postgres server minus 2, limit to 12 if 16+ cores - minimal benefit beyond 12)
max_concurrent_processes = 24

# Postgres parameters

pg_host = "localhost"
pg_port = 5433
pg_db = "gnaf_test"
pg_user = "postgres"
pg_password = "password"

# schema names for the raw gnaf, flattened reference and admin boundary tables
raw_gnaf_schema = "raw_gnaf"
raw_admin_bdys_schema = "raw_admin_bdys"
gnaf_schema = "gnaf"
admin_bdys_schema = "admin_bdys"

# *********************************************************************************************************************
# Edit these parameters to taste - END
# *********************************************************************************************************************

# create postgres connect string
pg_connect_string = "dbname='{0}' host='{1}' port='{2}' user='{3}' password='{4}'"\
    .format(pg_db, pg_host, pg_port, pg_user, pg_password)

# application_name ?

# set postgres script directory
if platform.system() == "Windows":
    sql_dir = os.path.dirname(os.path.realpath(__file__)) + "\\postgres-scripts\\clean-localities\\"
else:  # assume all else use forward slashes
    sql_dir = os.path.dirname(os.path.realpath(__file__)) + "/postgres-scripts/clean-localities/"


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
    pg_cur.execute(open_sql_file("00-create-polygon-intersection-function.sql"))
    pg_cur.execute(open_sql_file("00-create-multi-linestring-split-function.sql"))

    create_states_and_prep_localities()
    get_split_localities(pg_cur)
    verify_locality_polygons(pg_cur)
    get_locality_state_border_gaps(pg_cur)
    # finalise_display_localities(pg_cur)

    pg_cur.close()
    pg_conn.close()

    print "Total time : {0}".format(datetime.now() - full_start_time)


def create_states_and_prep_localities():
    start_time = datetime.now()
    sql_list = [open_sql_file("01-create-states-from-sa4s.sql"), open_sql_file("02-thin-locality-boundaries.sql")]
    multiprocess_list(2, "sql", sql_list)
    print "\t- Step  1 of 10 : state table created & localities prepped : {0}".format(datetime.now() - start_time)


def get_split_localities(pg_cur):
    start_time = datetime.now()

    # split locality bdys by state bdys, using multiprocessing
    sql = prep_sql("INSERT INTO admin_bdys.temp_split_localities "
                   "(gid, locality_pid, loc_state, state_gid, ste_state, match_type, geom) "
                   "SELECT loc.gid, loc.locality_pid, loc.state, ste.gid, ste.state, 'SPLIT', "
                   "(ST_Dump(PolygonalIntersection(loc.geom, ste.geom))).geom "
                   "FROM admin_bdys.temp_localities AS loc "
                   "INNER JOIN admin_bdys.temp_sa4_state_lines AS lne ON ST_Intersects(loc.geom, lne.geom)"
                   "INNER JOIN admin_bdys.temp_sa4_states AS ste ON lne.gid = ste.gid;")
    split_sql_into_list_and_process(pg_cur, sql, admin_bdys_schema, "temp_localities", "loc", "gid")

    print "\t- Step  2 of 10 : localities split by state : {0}".format(datetime.now() - start_time)


def verify_locality_polygons(pg_cur):
    start_time = datetime.now()
    pg_cur.execute(open_sql_file("03-verify-split-polygons.sql"))
    pg_cur.execute(open_sql_file("04-load-messy-centroids.sql"))
    print "\t- Step  3 of 10 : messy locality polygons verified : {0}".format(datetime.now() - start_time)


def get_locality_state_border_gaps(pg_cur):
    start_time = datetime.now()

    # get holes in the localities along the state borders
    sql = prep_sql("INSERT INTO admin_bdys.temp_holes (state, geom) "
                   "SELECT ste.state, (ST_Dump(ST_Difference(ste.geom, ST_Union(loc.geom)))).geom "
                   "FROM admin_bdys.temp_sa4_state_borders AS ste "
                   "INNER JOIN admin_bdys.temp_split_localities AS loc "
                   "ON (ST_Overlaps(ste.geom, loc.geom) AND ste.state = loc.loc_state) "
                   "GROUP BY ste.state, ste.geom;")
    split_sql_into_list_and_process(pg_cur, sql, admin_bdys_schema, "temp_sa4_state_borders", "ste", "gid")

    print "\t- Step  4 of 10 : locality holes created : {0}".format(datetime.now() - start_time)


def finalise_display_localities(pg_cur):
    start_time = datetime.now()
    pg_cur.execute(open_sql_file("05-finalise-display-localities.sql"))
    pg_cur.execute(prep_sql("VACUUM ANALYSE admin_bdys.locality_boundaries_display;"))
    print "\t- Step  5 of 10 : display localities finalised : {0}".format(datetime.now() - start_time)


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

    # set raw gnaf database schema (it's needed for the primary and foreign key creation)
    if raw_gnaf_schema != "public":
        pg_cur.execute("SET search_path = {0}, public, pg_catalog".format(raw_gnaf_schema,))

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
    sql = open(sql_dir + file_name, "r").read()
    return prep_sql(sql)


# change schema names in an array of SQL script if schemas not the default
def prep_sql_list(sql_list):
    output_list = []
    for sql in sql_list:
        output_list.append(prep_sql(sql))
    return output_list


# change schema names in the SQL script if not the default
def prep_sql(sql):
    if raw_gnaf_schema != "raw_gnaf":
        sql = sql.replace(" raw_gnaf.", " {0}.".format(raw_gnaf_schema,))
    if gnaf_schema != "gnaf":
        sql = sql.replace(" gnaf.", " {0}.".format(gnaf_schema,))
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

        if "WHERE " in the_sql:
            mp_sql = the_sql.replace("WHERE ", "WHERE {0}.{3} > {1} AND {0}.{3} <= {2} AND ")\
                .format(table_alias, start_pkey, end_pkey, table_gid)
        elif "GROUP BY " in the_sql:
            mp_sql = the_sql.replace("GROUP BY ", "WHERE {0}.{3} > {1} AND {0}.{3} <= {2} GROUP BY ")\
                .format(table_alias, start_pkey, end_pkey, table_gid)
        elif "ORDER BY " in the_sql:
            mp_sql = the_sql.replace("ORDER BY ", "WHERE {0}.{3} > {1} AND {0}.{3} <= {2} ORDER BY ")\
                .format(table_alias, start_pkey, end_pkey, table_gid)
        else:
            mp_sql = the_sql.replace(";", " WHERE {0}.{3} > {1} AND {0}.{3} <= {2};")\
                .format(table_alias, start_pkey, end_pkey, table_gid)

        sql_list.append(mp_sql)
        start_pkey = end_pkey

    # print '\n'.join(sql_list)
    multiprocess_list(processes, 'sql', sql_list)


if __name__ == '__main__':
    main()
