CREATE OR REPLACE FUNCTION PolygonalIntersection(a geometry, b geometry) RETURNS geometry(MultiPolygon, 4283) AS $$

SELECT ST_Multi(ST_Union(geom))
  FROM (
    SELECT (ST_Dump(ST_Intersection(a, b))).geom 
    UNION ALL
    SELECT ST_SetSRID(ST_GeomFromText('POLYGON EMPTY'), 4283)
  ) AS sqt
  WHERE ST_GeometryType(geom) = 'ST_Polygon';

$$ LANGUAGE SQL;
