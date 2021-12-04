
import psycopg2

# create postgres connect string
pg_connect_string = "dbname='geo' host='localhost' port='5432' user='postgres' password='password'"

# connect to Postgres
pg_conn = psycopg2.connect(pg_connect_string)
pg_conn.autocommit = True
pg_cur = pg_conn.cursor()

input_file_path = "/Users/hugh.saalmans/git/iag_geo/psma-admin-bdys/postgres-scripts/xx-messy-centroids_fix.sql"
output_file_path = "/Users/hugh.saalmans/git/iag_geo/psma-admin-bdys/postgres-scripts/xx-messy-centroids_fixed.sql"

input_file = open(input_file_path, "r")
output_file = open(output_file_path, "w")

# go through each line and replace the old locality pid with the new one
for old_line in input_file.readlines():

    old_locality_pid = old_line.split("'")[1]

    sql = """SELECT locality_pid
             FROM raw_gnaf_202111.locality_pid_linkage
             WHERE ab_locality_pid = '{}'""".format(old_locality_pid)
    pg_cur.execute(sql)

    try:
        locality_pid = pg_cur.fetchone()[0]

        # print("{} : {}".format(locality_pid, old_locality_pid))

        new_line = old_line.replace(old_locality_pid, locality_pid)

        # print(new_line)

        output_file.write(new_line)
    except:
        pass


output_file.close()
input_file.close()

