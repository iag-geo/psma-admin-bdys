
drop table if exists testing.postcode_lines;
create table testing.postcode_lines as
with pc as (
    select postcode,
           st_collect(geom) as geom
    from admin_bdys_202208.postcode_bdys_display
    where postcode is not null
    group by postcode
), pnt as (
    select postcode,
           st_centroid(geom) as geom
    from pc
)
select postcode,
       lead(postcode) over (order by postcode) as next_postcode,
       st_makeline(geom, lead(geom) over (order by postcode)) as geom
from pnt
;
