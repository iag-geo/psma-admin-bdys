import logging
import math
import multiprocessing
import os
import subprocess

import psycopg

import settings


# takes a list of sql queries or command lines and runs them using multiprocessing
def multiprocess_list(mp_type: str, work_list: list[str], logger: logging.Logger) -> None:
    pool = multiprocessing.Pool(processes=settings.max_processes)

    num_jobs = len(work_list)

    if mp_type == "sql":
        results = pool.imap_unordered(run_sql_multiprocessing, work_list)
    else:
        results = pool.imap_unordered(run_command_line, work_list)

    pool.close()
    pool.join()

    result_list = list(results)
    num_results = len(result_list)

    if num_jobs > num_results:
        logger.warning("\t- A MULTIPROCESSING PROCESS FAILED WITHOUT AN ERROR\nACTION: Check the record counts")

    for result in result_list:
        if result != "SUCCESS":
            logger.info(result)


def run_sql_multiprocessing(the_sql: str):
    pg_conn = psycopg.connect(settings.pg_connect_string)
    pg_conn.autocommit = True
    pg_cur = pg_conn.cursor()

    # # set raw gnaf database schema (it's needed for the primary and foreign key creation)
    # if settings.raw_gnaf_schema != "public":
    #     pg_cur.execute("SET search_path = %s, public, pg_catalog", (settings.raw_gnaf_schema,))

    try:
        pg_cur.execute(the_sql) # type: ignore
        result = "SUCCESS"
    except psycopg.Error as ex:
        result = f"SQL FAILED! : {the_sql} : {ex}"

    pg_cur.close()
    pg_conn.close()

    return result


def run_command_line(cmd: str) -> str:
    # run the command line without any output (it'll still tell you if it fails miserably)
    with open(os.devnull, "w") as f_null:
        returncode = subprocess.call(cmd, shell=True, stdout=f_null, stderr=subprocess.STDOUT)
        if returncode != 0:
            result = f"COMMAND FAILED! : {cmd} : exit code {returncode}"
        else:
            result = "SUCCESS"

    return result


def open_sql_file(file_name: str) -> str:
    with open(os.path.join(settings.sql_dir, file_name), "r") as f:
        sql_string = f.read()
        
    return prep_sql(sql_string)


# change schema names in an array of SQL script if schemas not the default
def prep_sql_list(sql_list: list[str]) -> list[str]:
    output_list = list[str]()
    for sql_string in sql_list:
        output_list.append(prep_sql(sql_string))
    return output_list


# set schema names in the SQL script
def prep_sql(sql: str) -> str:
    # if settings.raw_gnaf_schema:
    #     sql = sql.replace(" raw_gnaf.", f" {settings.raw_gnaf_schema}.")
    # if settings.raw_admin_bdys_schema:
    #     sql = sql.replace(" raw_admin_bdys.", f" {settings.raw_admin_bdys_schema}.")
    # if settings.gnaf_schema:
    #     sql = sql.replace(" gnaf.", f" {settings.gnaf_schema}.")
    if settings.admin_bdys_schema:
        sql = sql.replace(" admin_bdys.", f" {settings.admin_bdys_schema}.")

    if settings.pg_user != "postgres":
        # alter create table script to run with correct Postgres username
        sql = sql.replace(" postgres;", f" {settings.pg_user};")

    return sql


def split_sql_into_list(pg_cur: psycopg.Cursor, the_sql: str, table_schema: str, table_name: str, table_alias: str, table_gid: str, logger: logging.Logger) -> list[str]:
    # get min max gid values from the table to split
    min_max_sql = "SELECT MIN(%s) AS min, MAX(%s) AS max FROM %s.%s"
    pg_cur.execute(min_max_sql, (table_gid, table_gid, table_schema, table_name))

    try:
        result = pg_cur.fetchone()

        min_pkey = int(result[0]) # type: ignore
        max_pkey = int(result[1]) # type: ignore
        diff = max_pkey - min_pkey

        # Number of records in each query
        rows_per_request = math.floor(float(diff) / float(settings.max_processes)) + 1

        # If less records than processes or rows per request,
        # reduce both to allow for a minimum of 15 records each process
        if float(diff) / float(settings.max_processes) < 10.0:
            rows_per_request = 10
            processes = math.floor(float(diff) / 10.0) + 1
            logger.info(f"\t\t- running {processes} processes (adjusted due to low row count in table to split)")
        else:
            processes = settings.max_processes

        # create list of sql statements to run with multiprocessing
        sql_list = list[str]()
        start_pkey = min_pkey - 1

        for _ in range(processes):
            end_pkey = start_pkey + rows_per_request

            where_clause = \
                f" WHERE {table_alias}.{table_gid} > {start_pkey} AND {table_alias}.{table_gid} <= {end_pkey}"

            if "WHERE " in the_sql:
                mp_sql = the_sql.replace(" WHERE ", where_clause + " AND ")
            elif "GROUP BY " in the_sql:
                mp_sql = the_sql.replace("GROUP BY ", where_clause + " GROUP BY ")
            elif "ORDER BY " in the_sql:
                mp_sql = the_sql.replace("ORDER BY ", where_clause + " ORDER BY ")
            else:
                if ";" in the_sql:
                    mp_sql = the_sql.replace(";", where_clause + ";")
                else:
                    mp_sql = the_sql + where_clause
                    logger.warning("\t\t- NOTICE: no ; found at the end of the SQL statement")

            sql_list.append(mp_sql)
            start_pkey = end_pkey

        # logger.info("\n".join(sql_list))

        return sql_list
    except Exception as ex:  # noqa: BLE001
        logger.fatal(f"Looks like the table in this query is empty: {min_max_sql}\n{ex}")
        return list[str]()
