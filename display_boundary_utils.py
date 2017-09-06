#!/usr/bin/env python
# -*- coding: utf-8 -*-

import math


def thin_geom_sql(zoom_level):
    tolerance = get_tolerance(zoom_level, "degrees")

    # return "ST_Transform(ST_Multi(ST_Union(ST_MakeValid(ST_SimplifyVW(ST_Transform(geom, 3577), {0})))), 4283)".format(tolerance,)
    return "ST_Multi(ST_Union(ST_MakeValid(ST_SimplifyVW(geom, {0}))))".format(tolerance,)


# calculates the area tolerance (in metres or degrees squared)
# for input into the Visvalingam-Whyatt vector simplification
def get_tolerance(zoom_level, units="degrees"):

    # pixels squared factor
    tolerance_square_pixels = 20

    # default Google/Bing map tile scales
    metres_per_pixel = 156543.03390625 / math.pow(2.0, float(zoom_level + 1))

    if units == "metres":
        square_metres_per_pixel = math.pow(metres_per_pixel, 2.0)

        # tolerance to use
        tolerance = square_metres_per_pixel * tolerance_square_pixels
    else:
        # rough metres to degrees conversation, using spherical WGS84 datum radius (for simplicity and speed)
        metres2degrees = (2.0 * math.pi * 6378137.0) / 360.0

        degrees_per_pixel = metres_per_pixel / metres2degrees
        square_degrees_per_pixel = math.pow(degrees_per_pixel, 2.0)

        # tolerance to use
        tolerance = square_degrees_per_pixel * tolerance_square_pixels

    return tolerance


# maximum number of decimal places for boundary coordinates - improves display performance
def get_decimal_places(zoom_level):

    # rough metres to degrees conversation, using spherical WGS84 datum radius for simplicity and speed
    metres2degrees = (2.0 * math.pi * 6378137.0) / 360.0

    # default Google/Bing map tile scales
    metres_per_pixel = 156543.03390625 / math.pow(2.0, float(zoom_level))

    # the tolerance for thinning data and limiting decimal places in GeoJSON responses
    degrees_per_pixel = metres_per_pixel / metres2degrees

    scale_string = "{:10.9f}".format(degrees_per_pixel).split(".")[1]
    places = 1

    trigger = "0"

    # find how many zero decimal places there are. e.g. 0.00001234 = 4 zeros
    for c in scale_string:
        if c == trigger:
            places += 1
        else:
            trigger = "don't do anything else"  # used to cleanly exit the loop

    return places


print(thin_geom_sql(15))
