module data_objects

import PyCall: PyObject, PyDict, pycall, pystring
import Base: size, show, showarray, display, showerror
import ..array: YTArray, YTQuantity, in_units, array_or_quan
import ..fixed_resolution: FixedResolutionBuffer

Center = Union(ASCIIString,Array{Float64,1},YTArray)
Length = Union(FloatingPoint,(FloatingPoint,ASCIIString),YTQuantity)

# Dataset

type Dataset
    ds::PyObject
    parameters::PyDict
    domain_center::YTArray
    domain_left_edge::YTArray
    domain_right_edge::YTArray
    domain_width::YTArray
    domain_dimensions::Array{Int,1}
    dimensionality::Integer
    current_time::YTQuantity
    current_redshift::FloatingPoint
    max_level::Integer
    function Dataset(ds::PyObject)
        new(ds,
            PyDict(ds["parameters"]::PyObject),
            YTArray(ds["domain_center"]),
            YTArray(ds["domain_left_edge"]),
            YTArray(ds["domain_right_edge"]),
            YTArray(ds["domain_width"]),
            ds[:domain_dimensions],
            ds[:dimensionality][1],
            YTQuantity(ds["current_time"]),
            ds[:current_redshift],
            ds[:max_level][1])
    end
end

function get_smallest_dx(ds::Dataset)
    pycall(ds.ds[:index]["get_smallest_dx"], YTArray)[1]
end

function print_stats(ds::Dataset)
    ds.ds[:print_stats]()
end

function find_min(ds::Dataset, field)
    v, c = pycall(ds.ds["find_min"], (PyObject, PyObject), field)
    return YTQuantity(v), YTArray(c)
end

function find_max(ds::Dataset, field)
    v, c = pycall(ds.ds["find_max"], (PyObject, PyObject), field)
    return YTQuantity(v), YTArray(c)
end

function get_field_list(ds::Dataset)
    ds.ds[:field_list]
end

function get_derived_field_list(ds::Dataset)
    ds.ds[:derived_field_list]
end

# Data containers

abstract DataContainer

function parse_fps(field_parameters)
    fps = nothing
    if field_parameters != nothing
        fps = Dict()
        for key in keys(field_parameters)
            fps[key] = convert(PyObject, field_parameters[key])
        end
    end
    return fps
end

# All Data

@doc doc"""
      An object representing all of the data in the domain.

      Parameters:

      * `ds::Dataset`: The dataset to be used.
      * `field_parameters::Dict{ASCIIString,Any}`: A dictionary of field parameters
        than can be accessed by derived fields.
      * `data_source::DataContainer`: Optionally draw the selection from the
        provided data source rather than all data associated with the dataset

      Examples:

          julia> import YT
          julia> ds = YT.load("RedshiftOutput0005")
          julia> dd = YT.AllData(ds)
      """ ->
type AllData <: DataContainer
    cont::PyObject
    ds::Dataset
    field_dict::Dict
    function AllData(ds::Dataset; field_parameters=nothing,
                     data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        new(ds.ds[:all_data](field_parameters=field_parameters,
                             data_source=source, args...), ds, Dict())
    end
end

# Point

@doc doc"""
      A 0-dimensional object defined by a single point

      Parameters:

      * `ds::Dataset`: The dataset to be used.
      * `p::Array{Float64,1}`: A point defined within the domain. If the domain is periodic
        its position will be corrected to lie inside the range [DLE,DRE) to ensure
        one and only one cell may match that point.
      * `field_parameters::Dict{ASCIIString,Any}`: A dictionary of field parameters
        than can be accessed by derived fields.
      * `data_source::DataContainer`: Optionally draw the selection from the
        provided data source rather than all data associated with the dataset

      Examples:

          julia> import YT
          julia> ds = YT.load("RedshiftOutput0005")
          julia> c = [0.5,0.5,0.5]
          julia> point = YT.Point(ds,c)
      """ ->
type Point <: DataContainer
    cont::PyObject
    ds::Dataset
    coord::Array{Float64,1}
    field_dict::Dict
    function Point(ds::Dataset, coord::Array{Float64,1};
                   field_parameters=nothing, data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        pt = ds.ds[:point](coord; field_parameters=field_parameters,
                           data_source=source, args...)
        new(pt, ds, pt[:p], Dict())
    end
end

# Region

type Region <: DataContainer
    cont::PyObject
    ds::Dataset
    center::YTArray
    left_edge::YTArray
    right_edge::YTArray
    field_dict::Dict
    function Region(ds::Dataset, center::Center,
                    left_edge::Union(Array{Float64,1},YTArray),
                    right_edge::Union(Array{Float64,1},YTArray);
                    field_parameters=nothing, data_source=nothing, args...)
        if typeof(center) == YTArray
            c = convert(PyObject, center)
        else
            c = center
        end
        if typeof(left_edge) == YTArray
            le = in_units(YTArray(ds, left_edge.value,
                          repr(left_edge.units.unit_symbol)),
                          "code_length").value
        else
            le = left_edge
        end
        if typeof(right_edge) == YTArray
            re = in_units(YTArray(ds, right_edge.value,
                          repr(right_edge.units.unit_symbol)),
                          "code_length").value
        else
            re = right_edge
        end
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        reg = ds.ds[:region](c, le, re; field_parameters=field_parameters,
                             data_source=source, args...)
        new(reg, ds, YTArray(reg["center"]), YTArray(reg["left_edge"]),
            YTArray(reg["right_edge"]), Dict())
    end
end

# Disk

type Disk <: DataContainer
    cont::PyObject
    ds::Dataset
    center::YTArray
    normal::Array{Float64,1}
    field_dict::Dict
    function Disk(ds::Dataset, center::Center, normal::Array{Float64,1},
                  radius::Length, height::Length; data_source=nothing,
                  args...)
        if typeof(center) == YTArray
            c = convert(PyObject, center)
        else
            c = center
        end
        if typeof(radius) == YTQuantity
            r = convert(PyObject, radius)
        else
            r = radius
        end
        if typeof(height) == YTQuantity
            h = convert(PyObject, height)
        else
            h = height
        end
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        dk = ds.ds[:disk](c, normal, r, h; data_source=source, args...)
        new(dk, ds, YTArray(dk["center"]), normal, Dict())
    end
end

# Ray

@doc doc"""
      This is an arbitrarily-aligned ray cast through the entire domain, at a
      specific coordinate.

      The resulting arrays have their dimensionality reduced to one, and
      an ordered list of points at an (x,y) tuple are available, as is the
      `"t"` field, which corresponds to a unitless measurement along
      the ray from start to end.

      Parameters:

      * `ds::Dataset`: The dataset to be used.
      * `start_point::Array{Float64,1}`: The place where the ray starts.
      * `end_point::Array{Float64,1}`: The place where the ray ends.
      * `field_parameters::Dict{ASCIIString,Any}`: A dictionary of field
        parameters than can be accessed by derived fields.
      * `data_source::DataContainer`: Optionally draw the selection from the
        provided data source rather than all data associated with the dataset

      Examples:

          julia> import YT
          julia> ds = YT.load("RedshiftOutput0005")
          julia> ray = YT.Ray(ds, [0.2, 0.74, 0.11], [0.4, 0.91, 0.31])
      """ ->
type Ray <: DataContainer
    cont::PyObject
    ds::Dataset
    start_point::YTArray
    end_point::YTArray
    field_dict::Dict
    function Ray(ds::Dataset, start_point::Array{Float64,1},
                 end_point::Array{Float64,1}; data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        ray = ds.ds[:ray](start_point, end_point; data_source=source, args...)
        new(ray, ds, YTArray(ray["start_point"]),
            YTArray(ray["end_point"]), Dict())
    end
end

# Cutting

@doc doc"""
      This is a data object corresponding to an oblique slice through the
      simulation domain.

      A cutting plane is an oblique plane through the data, defined by a
      normal vector and a coordinate. It attempts to guess a "north" vector,
      which can be overridden, and then it pixelizes the appropriate data
      onto the plane without interpolation.

      Parameters:

      * `ds::Dataset`: The dataset to be used.
      * `normal::Array{Float64,1}`: The vector that defines the desired plane.
        For instance, the angular momentum of a sphere.
      * `center::Union(ASCIIString,Array{Float64,1},YTArray)` : array_like
        The center of the cutting plane, where the normal vector is anchored.
      * `north_vector::Array{Float64,1}`: An optional vector to describe the
        north-facing direction in the resulting plane.
      * `field_parameters::Dict{ASCIIString,Any}`: A dictionary of field
        parameters than can be accessed by derived fields.
      * `data_source::DataContainer`: Optionally draw the selection from the
        provided data source rather than all data associated with the dataset

      Examples:

          julia> import YT
          julia> ds = YT.load("RedshiftOutput0005")
          juila> cp = YT.Cutting(ds, [0.1, 0.2, -0.9], [0.5, 0.42, 0.6])
      """ ->
type Cutting <: DataContainer
    cont::PyObject
    ds::Dataset
    normal::Array{Float64,1}
    center::YTArray
    field_dict::Dict
    function Cutting(ds::Dataset, normal::Array{Float64,1}, center::Center;
                     north_vector=nothing, field_parameters=nothing,
                     data_source=nothing, args...)
        if typeof(center) == YTArray
            c = convert(PyObject, center)
        else
            c = center
        end
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        cutting = ds.ds[:cutting](normal, c; data_source=source,
                                  north_vector=north_vector,
                                  field_parameters=field_parameters, args...)
        new(cutting, ds, cutting[:normal], YTArray(cutting["center"]), Dict())
    end
end

# Projection

type Proj <: DataContainer
    cont::PyObject
    ds::Dataset
    field
    axis::Integer
    weight_field
    field_dict::Dict
    function Proj(ds::Dataset, field, axis::Union(Integer,ASCIIString);
                  weight_field=nothing, field_parameters=nothing,
                  data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        prj = ds.ds[:proj](field, axis, weight_field=weight_field,
                           field_parameters=field_parameters,
                           data_source=source; args...)
        new(prj, ds, field, prj["axis"], weight_field, Dict())
    end
end

# Slice
@doc doc"""
      This is a data object corresponding to a slice through the simulation
      domain.

      The slice is an orthogonal slice through the data, taking all the
      points at the finest resolution available and then indexing them.

      Parameters:

      * `axis::Integer`: The axis along which to slice. Can be 0, 1, or 2
        for x, y, z.
      * `coord::FloatingPoint`: The coordinate along the axis at which to
        slice. This is in "domain" coordinates.
      * `center::Array{Float64,1}`: The 'center' supplied to fields that
        use it. Note that this does not have to have `coord` as one value.
        Optional.
      * `field_parameters::Dict{ASCIIString,Any}`: A dictionary of field
        parameters than can be accessed by derived fields.
      * `data_source::DataContainer`: Optionally draw the selection from the
        provided data source rather than all data associated with the dataset

      Examples:

          julia> import YT
          julia> ds = YT.load("RedshiftOutput0005")
          julia> slc = Slice(ds, 0, 0.25)
      """ ->
type Slice <: DataContainer
    cont::PyObject
    ds::Dataset
    axis::Integer
    coord::Float64
    field_dict::Dict
    function Slice(ds::Dataset, axis::Integer,
                   coord::FloatingPoint; center=nothing,
                   field_parameters=nothing,
                   data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        slc = ds.ds[:slice](axis, coord; center=center,
                            field_parameters=field_parameters,
                            data_source=source, args...)
        new(slc, ds, slc["axis"], slc["coord"], Dict())
    end
end

function to_frb(cont::Union(Slice,Proj), width::Union(Length,(Length,Length)),
                nx::Union(Integer,(Integer,Integer)); center=nothing,
                height=nothing, args...)
    FixedResolutionBuffer(cont.ds, cont.cont[:to_frb](width, nx;
                                                      center=center,
                                                      height=height, args...))
end

# Sphere

type Sphere <: DataContainer
    cont::PyObject
    ds::Dataset
    center::YTArray
    radius::YTQuantity
    field_dict::Dict
    function Sphere(ds::Dataset, center::Center, radius::Length;
                    field_parameters=nothing, data_source=nothing, args...)
        if typeof(center) == YTArray
            c = convert(PyObject, center)
        else
            c = center
        end
        if typeof(radius) == YTQuantity
            r = convert(PyObject, radius)
        else
            r = radius
        end
        if data_source != nothing
            source = data_source.cont
        else
            source = nothing
        end
        field_parameters = parse_fps(field_parameters)
        sp = ds.ds[:sphere](c, r; field_parameters=field_parameters,
                            data_source=source, args...)
        new(sp, ds, YTArray(sp["center"]),
            YTQuantity(sp["radius"]), Dict())
    end
end

# CutRegion

type CutRegion <: DataContainer
    cont::PyObject
    ds::Dataset
    conditions::Array{ASCIIString,1}
    field_dict::Dict
    function CutRegion(dc::DataContainer, conditions::Array{ASCIIString,1}; args...)
        cut_reg = dc.cont[:cut_region](conditions; args...)
        new(cut_reg, dc.ds, conditions, Dict())
    end
end

# Grids

type Grids <: AbstractArray
    grids::Array
    grid_dict::Dict
    function Grids(ds::Dataset)
        new(ds.ds[:index][:grids], Dict())
    end
    function Grids(grid_array::Array)
        new(grid_array, Dict())
    end
    function Grids(grid::PyObject)
        new([grid], Dict())
    end
    function Grids(nothing)
        new([], Dict())
    end
end

size(grids::Grids) = size(grids.grids)

# Grid

type Grid <: DataContainer
    cont::PyObject
    left_edge::YTArray
    right_edge::YTArray
    id::Integer
    level::Integer
    number_of_particles::Integer
    active_dimensions::Array{Integer,1}
    Parent::Grids
    Children::Grids
    field_dict::Dict
end

# CoveringGrid

type CoveringGrid <: DataContainer
    cont::PyObject
    ds::Dataset
    left_edge::YTArray
    right_edge::YTArray
    level::Integer
    active_dimensions::Array{Integer,1}
    field_dict::Dict
    function CoveringGrid(ds::Dataset, level::Integer,
                          left_edge::Array{Float64,1},
                          dims::Array{Int,1};
                          field_parameters=nothing, args...)
        field_parameters = parse_fps(field_parameters)
        cg = ds.ds[:covering_grid](level, left_edge, dims;
                                   field_parameters=field_parameters, args...)
        new(cg, ds, YTArray(cg["left_edge"]), YTArray(cg["right_edge"]),
            level, cg[:ActiveDimensions], Dict())
    end
end

# Field parameters

@doc doc"""
      Set the value of a field parameter in a data container.

      Parameters:

      * `dc::DataContainer`: The data container object to set the
        parameter for.
      * `key::String`: The name of the parameter to set.
      * `value::Any`: The value of the parameter.

      Examples:

          julia> import YT
          julia> ds = YT.load("GasSloshing/sloshing_nomag2_hdf5_plt_cnt_0100")
          julia> sp = YT.Sphere(ds, "c", (200.,"kpc"))
          julia> set_field_parameter(sp, "mu", 0.592)

      """ ->
function set_field_parameter(dc::DataContainer, key::String, value)
    v = convert(PyObject, value)
    dc.cont[:set_field_parameter](key, v)
end

@doc doc"""
      Check if a field parameter is set in a data container object.

      Parameters:

      * `dc::DataContainer`: The data container object to check for
        a parameter.
      * `key::String`: The name of the parameter to check.

      Examples:

          julia> import YT
          julia> ds = YT.load("GasSloshing/sloshing_nomag2_hdf5_plt_cnt_0100")
          julia> sp = YT.Sphere(ds, "c", (200.,"kpc"))
          julia> has_field_parameter(sp, "center")
      """ ->
function has_field_parameter(dc::DataContainer, key::String)
    dc.cont[:has_field_parameter](key)
end

@doc doc"""
      Get the value of a field parameter.

      Parameters:

      * `dc::DataContainer`: The data container object to get the
        parameter from.
      * `key::String`: The name of the parameter to get.

      Examples:

          julia> import YT
          julia> ds = YT.load("GasSloshing/sloshing_nomag2_hdf5_plt_cnt_0100")
          julia> sp = YT.Sphere(ds, "c", (200.,"kpc"))
          julia> ctr = get_field_parameter(sp, "center")

      """ ->
function get_field_parameter(dc::DataContainer, key::String)
    v = pycall(dc.cont["get_field_parameter"], PyObject, key)
    if contains(pystring(v), "YTArray")
        v = YTArray(v)
    else
        v = dc.cont[:get_field_parameter](key)
    end
    return v
end

@doc doc"""
      Get all of the field parameters from a data container. Returns
      a dictionary of field parameters.

      Parameters:

      * `dc::DataContainer`: The data container object to get the
        parameters from.

      Examples:

          julia> import YT
          julia> ds = YT.load("GasSloshing/sloshing_nomag2_hdf5_plt_cnt_0100")
          julia> sp = YT.Sphere(ds, "c", (200.,"kpc"))
          julia> field_parameters = get_field_parameters(sp)
      """ ->
function get_field_parameters(dc::DataContainer)
    fp = Dict()
    for k in collect(keys(dc.cont[:field_parameters]))
        fp[k] = get_field_parameter(dc, k)
    end
    return fp
end

# Indices

function getindex(dc::DataContainer, field::Union(String,Tuple))
    if !haskey(dc.field_dict, field)
        dc.field_dict[field] = YTArray(get(dc.cont, PyObject, field))
        delete!(dc.cont, field)
    end
    return dc.field_dict[field]
end

getindex(dc::DataContainer, ftype::String,
         fname::String) = getindex(dc, (ftype, fname))

function getindex(grids::Grids, i::Integer)
    if !haskey(grids.grid_dict, i)
        g = grids.grids[i]
        grids.grid_dict[i] = Grid(g,
                                  YTArray(g["LeftEdge"]),
                                  YTArray(g["RightEdge"]),
                                  g[:id][1],
                                  g[:Level][1],
                                  g[:NumberOfParticles][1],
                                  g[:ActiveDimensions],
                                  Grids(g[:Parent]),
                                  Grids(g[:Children]), Dict())
    end
    return grids.grid_dict[i]
end

getindex(grids::Grids, idxs::Ranges) = Grids(grids.grids[idxs])

# Show

show(io::IO, ds::Dataset) = print(io,pystring(ds.ds))
show(io::IO, dc::DataContainer) = print(io,pystring(dc.cont))

function showarray(io::IO, grids::Grids)
    num_grids = length(grids)
    if num_grids == 0
        print(io, "[]")
        return
    end
    if num_grids == 1
        print(io, "[ $(pystring(grids.grids[1])) ]")
        return
    end
    n = num_grids > 8 ? 5 : num_grids
    println(io, "[ $(pystring(grids.grids[1])),")
    for grid in grids.grids[2:n-1]
        println(io, "  $(pystring(grid)),")
    end
    if num_grids > 8
        println(io, "  ...")
        for grid in grids.grids[num_grids-3:num_grids-1]
            println(io, "  $(pystring(grid)),")
        end
    end
    print(io, "  $(pystring(grids.grids[end])) ]")
end

show(io::IO, grids::Grids) = showarray(io, grids)
display(grids::Grids) = show(STDOUT, grids)

end
