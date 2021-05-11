

-- HS note: this doesn't scale to Geoscape localities - it never finishes!


-- Simplify the given table of multipolygon with the given tolerance.
-- This function preserves the connection between polygons and try to avoid generating gaps between objects.
-- To identify objects after simplification, area comparison is performed, instead of PIP test, that may fail
-- with odd-shaped polygons. Area comparison may also failed on some cases

-- Example: (table 'departement' is in the public schema) 
-- select * from simplifyLayerPreserveTopology('', 'departement', 'gid', 'geom', 10000) as (gid int, geom geometry);
-- 
-- @param schename: text, the schema name of the table to simplify. set to null or empty string to use search_path-defined schemas
-- @param tablename: text, the name of the table to simplify
-- @param idcol: text, the name of a unique table identifier column. This is the gid returned by the function
-- @param tolerance: float, the simplify tolerance, in object's unit
-- @return a setof (gid, geom) where gid is the identifier of the multipolygon, geom is the simplified geometry
create or replace function simplifyLayerPreserveTopology (schemaname text, tablename text, idcol text, geom_col text, tolerance float) 
returns setof record as $$
    DECLARE
        schname alias for $1;
        tabname alias for $2;
        tid alias for $3;
        geo alias for $4;
        tol alias for $5;
        numpoints int:=0;
        time text:='';
        fullname text := '';

    BEGIN
        IF schname IS NULL OR length(schname) = 0 THEN
            fullname := quote_ident(tabname);
        ELSE
            fullname := quote_ident(schname)||'.'||quote_ident(tabname);
        END IF;
        
        raise notice 'fullname: %', fullname;

        EXECUTE 'select sum(st_npoints('||quote_ident(geo)||')), to_char(clock_timestamp(), ''MI:ss:MS'') from '
            ||fullname into numpoints, time;
        raise notice 'Num points in %: %. Time: %', tabname, numpoints, time;
        
        EXECUTE 'create unlogged table public.poly as ('
                ||'select '||quote_ident(tid)||', (st_dump('||quote_ident(geo)||')).* from '||fullname||')';

        -- extract rings out of polygons
        create unlogged table rings as 
        select st_exteriorRing((st_dumpRings(geom)).geom) as g from public.poly;
        
        select to_char(clock_timestamp(), 'MI:ss:MS') into time;
        raise notice 'rings created: %', time;
        
        drop table poly;

        -- Simplify the rings. Here, no points further than 10km:
        create unlogged table gunion as select st_union(g) as g from rings;
        
        select to_char(clock_timestamp(), 'MI:ss:MS') into time;
        raise notice 'union done: %', time;
        
        drop table rings;
        
        create unlogged table mergedrings as select st_linemerge(g) as g from gunion;
        
        select to_char(clock_timestamp(), 'MI:ss:MS') into time;
        raise notice 'linemerge done: %', time;
        
        drop table gunion;
        
        create unlogged table simplerings as select st_simplifyPreserveTopology(g, tol) as g from mergedrings;
        
        
        select to_char(clock_timestamp(), 'MI:ss:MS') into time;
        raise notice 'rings simplified: %', time;
        
        drop table mergedrings;

        -- extract lines as individual objects, in order to rebuild polygons from these
        -- simplified lines
        create unlogged table simplelines as select (st_dump(g)).geom as g from simplerings;
        
        drop table simplerings;

        -- Rebuild the polygons, first by polygonizing the lines, with a 
        -- distinct clause to eliminate overlaping segments that may prevent polygon to be created,
        -- then dump the collection of polygons into individual parts, in order to rebuild our layer. 
        drop table if exists simplepolys;
        create  table simplepolys as 
        select (st_dump(st_polygonize(distinct g))).geom as g
        from simplelines;
        
        select count(*) from simplepolys into numpoints;
        select to_char(clock_timestamp(), 'MI:ss:MS') into time;
        raise notice 'rings polygonized. num rings: %. time: %', numpoints, time;
        
        drop table simplelines;

        -- some spatial indexes
        create index simplepolys_geom_gist on simplepolys  using gist(g);

        raise notice 'spatial index created...';

        -- works better: comparing percentage of overlaping area gives better results.
        -- as input set is multipolygon, we first explode multipolygons into their polygons, to
        -- be able to find islands and set them the right departement code.
        RETURN QUERY EXECUTE 'select '||quote_ident(tid)||', st_collect('||quote_ident(geo)||') as geom '
            ||'from ('
            --||'    select distinct on (d.'||quote_ident(tid)||') d.'||quote_ident(tid)||', s.g as geom '
            ||'    select d.'||quote_ident(tid)||', s.g as geom '
            ||'   from '||fullname||' d, simplepolys s '
            --||'    where (st_intersects(d.'||quote_ident(geo)||', s.g) or st_contains(d.'||quote_ident(geo)||', s.g))'
            ||'    where st_intersects(d.'||quote_ident(geo)||', s.g) '
            ||'    and st_area(st_intersection(s.g, d.'||quote_ident(geo)||'))/st_area(s.g) > 0.5 '
            ||'    ) as foo '
            ||'group by '||quote_ident(tid);
            
        --drop table simplepolys;
        
        RETURN;
    
    END;
$$ language plpgsql strict;