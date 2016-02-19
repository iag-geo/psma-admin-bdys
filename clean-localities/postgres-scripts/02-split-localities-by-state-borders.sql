INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, state_gid, ste_state, match_type, geom)
SELECT loc.gid,
       loc.locality_pid,
       loc.state,
       ste.gid,
       ste.state,
       'SPLIT',
       (ST_Dump(PolygonalIntersection(loc.geom, ste.geom))).geom
  FROM admin_bdys.temp_localities AS loc
  INNER JOIN admin_bdys.temp_sa4_state_lines AS lne ON ST_Intersects(loc.geom, lne.geom)
  INNER JOIN admin_bdys.temp_sa4_states AS ste ON lne.gid = ste.gid;
