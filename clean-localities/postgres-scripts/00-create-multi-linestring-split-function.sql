CREATE OR REPLACE FUNCTION public.ST_SplitPolygon(gid integer, poly geometry, blades geometry)
  RETURNS geometry AS
  
$BODY$DECLARE
  i integer := 0;
  num_lines integer;
  num_polys integer;
  output_polys geometry;
  
BEGIN
  -- get number of blades to split with
  SELECT ST_NumGeometries(blades) INTO num_lines;

  output_polys := ST_Collect(poly);
 
  WHILE i < num_lines LOOP
    i := i + 1;
    --SELECT ST_Buffer(ST_Split(output_polys, ST_GeometryN(blades, i)), 0.0) INTO output_polys;
    SELECT ST_Split(output_polys, ST_GeometryN(blades, i)) INTO output_polys;
  END LOOP;

  SELECT ST_NumGeometries(output_polys) INTO num_polys;
  IF num_polys < num_lines + 1 THEN
    RAISE NOTICE 'NOT ENOUGH POLYGONS! : gid % : blades % : num output polys %', gid, num_lines, num_polys;
  END IF;

  RETURN output_polys;

END$BODY$
  LANGUAGE plpgsql VOLATILE COST 100;
ALTER FUNCTION ST_SplitPolygon(integer, geometry, geometry) OWNER TO postgres;
