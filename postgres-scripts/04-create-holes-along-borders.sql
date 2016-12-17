INSERT INTO admin_bdys.temp_holes (state_gid, state, geom)
SELECT ste.new_gid,
       ste.state,
       (ST_Dump(ST_Difference(ste.geom, ST_Union(loc.geom)))).geom
  FROM admin_bdys.temp_state_border_buffers_subdivided AS ste
  INNER JOIN admin_bdys.temp_split_localities AS loc
  ON (ST_Intersects(ste.geom, loc.geom) AND ste.state = loc.loc_state)
  GROUP BY ste.new_gid,
    ste.state,
    ste.geom;
