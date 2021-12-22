
-- rename GDA94 table
ALTER TABLE admin_bdys.temp_messy_centroids RENAME TO temp_messy_centroids_gda94;

-- Create GDA2020 table
DROP TABLE IF EXISTS admin_bdys.temp_messy_centroids;
CREATE TABLE admin_bdys.temp_messy_centroids(
    gid integer NOT NULL,
    locality_pid text NOT NULL,
    loc_gid integer NOT NULL,
    state_gid integer NOT NULL,
    latitude numeric(10,8),
    longitude numeric(11,8),
    geom public.geometry(Point, 7844) NOT NULL
);
ALTER TABLE admin_bdys.temp_messy_centroids OWNER TO postgres;

-- insert transformed geoms
INSERT INTO admin_bdys.temp_messy_centroids
SELECT gid,
       locality_pid,
       loc_gid,
       state_gid,
       latitude,
       longitude,
       ST_transform(geom, 7844) as geom
FROM admin_bdys.temp_messy_centroids_gda94
;

DROP TABLE admin_bdys.temp_messy_centroids_gda94;

ALTER TABLE ONLY admin_bdys.temp_messy_centroids ADD CONSTRAINT temp_messy_centroids_pkey PRIMARY KEY (gid);

ANALYSE admin_bdys.temp_messy_centroids;
