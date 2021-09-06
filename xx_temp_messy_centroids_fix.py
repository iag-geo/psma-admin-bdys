

input_file_path = "/Users/hugh.saalmans/git/iag_geo/psma-admin-bdys/postgres-scripts/xx-messy-centroids_fix.sql"
output_file_path = "/Users/hugh.saalmans/git/iag_geo/psma-admin-bdys/postgres-scripts/xx-messy-centroids_fixed.sql"


input_file = open(input_file_path, "r")
output_file = open(output_file_path, "w")


for line in input_file.readlines():

    print(line)
