module YT

import Base: setindex!, getindex, show

# Datasets, Indices

export Dataset
export print_stats, get_smallest_dx
export find_min, find_max, get_field_list
export get_derived_field_list

# YTArrays, YTQuantities, units

export YTArray, YTQuantity, YTUnit, in_base
export in_units, in_cgs, in_mks, from_hdf5, write_hdf5
export to_equivalent, list_equivalencies, has_equivalent
export convert_to_units, convert_to_cgs, convert_to_mks

# load

export load, load_uniform_grid, load_amr_grids, load_particles

# DataContainers

export DataContainer, CutRegion, Disk, Ray, Slice, Region, Point
export Sphere, AllData, Proj, CoveringGrid, Grids, Cutting, OrthoRay
export set_field_parameter, get_field_parameter, get_field_parameters
export has_field_parameter

# Fixed resolution

export FixedResolutionBuffer, to_frb

# Profiles

export YTProfile, add_fields, variance
export set_field_unit, set_x_unit, set_y_unit, set_z_unit

# Plotting

export SlicePlot, ProjectionPlot
export show_plot

# DatasetSeries

export DatasetSeries

# Other

export enable_plugins, ytcfg, quantities, unit_system_registry

import PyCall: pyimport_conda, PyError, pycall, PyObject, set!, PyNULL

const yt = PyNULL()
const ytconv = PyNULL()
const ytstream = PyNULL()
const ytconfig = PyNULL()
const enable_plugins = PyNULL()

include("array.jl")
include("fixed_resolution.jl")
include("data_objects.jl")
include("physical_constants.jl")
include("dataset_series.jl")
include("plots.jl")
include("profiles.jl")
include("unit_symbols.jl")
include("unit_systems.jl")

import .array: YTArray, YTQuantity, in_units, in_cgs, in_mks, YTUnit,
    from_hdf5, write_hdf5, to_equivalent, list_equivalencies, in_base,
    has_equivalent, convert_to_units, convert_to_mks, convert_to_cgs
import .data_objects: Dataset, Grids, Sphere, AllData, Proj, Slice,
    CoveringGrid, to_frb, print_stats, get_smallest_dx, Disk, Ray,
    Cutting, CutRegion, DataContainer, Region, has_field_parameter,
    set_field_parameter, get_field_parameter, get_field_parameters,
    Point, find_min, find_max, get_field_list, get_derived_field_list,
    OrthoRay
import .plots: SlicePlot, ProjectionPlot, show_plot
import .fixed_resolution: FixedResolutionBuffer
import .profiles: YTProfile, set_x_unit, set_y_unit, set_z_unit,
    set_field_unit, variance
import .dataset_series: DatasetSeries
import .unit_systems: UnitSystem

unit_system_registry = Dict()

struct YTConfig
    ytcfg::PyObject
end

function setindex!(ytcfg::YTConfig, value::String, section::String,
                   param::String)
    set!(ytcfg.ytcfg, (section,param), value)
end

function getindex(ytcfg::YTConfig, section::String, param::String)
    pycall(ytcfg.ytcfg["get"], String, section, param)
end

show(ytcfg::YTConfig) = typeof(ytcfg)

function __init__()
    copy!(yt, pyimport_conda("yt", "yt"))
    min_version = v"3.3.1"

    yt_version = VersionNumber(yt[:__version__])
    if yt_version < min_version
        err_msg = "Your yt installation (v. $yt_version) is not up to " *
                  "date. Please install a version >= v. $min_version."
        error(err_msg)
    end
    copy!(ytconv, pyimport_conda("yt.convenience", "yt"))
    copy!(ytconfig, pyimport_conda("yt.config", "yt"))
    copy!(ytstream, pyimport_conda("yt.frontends.stream.api", "yt"))

    yt_unit_systems = collect(keys(yt[:unit_system_registry]))

    for us in yt_unit_systems
      unit_system_registry[us] = UnitSystem(yt[:unit_system_registry][us])
    end

    """
        enable_plugins()

    Enable the plugins defined in the plugin file.
    """
    enable_plugins = yt[:enable_plugins]

    global ytcfg = YTConfig(ytconfig["ytcfg"])
end

"""
    load(fn::String; args...)

Load a `Dataset` object from a file.
"""
load(fn::String; args...) = Dataset(ytconv[:load](fn; args...))

# Stream datasets

"""
    load_uniform_grid(data::Dict{Any,Any}, domain_dimensions::Array;
                      length_unit=nothing, bbox=nothing,
                      nprocs=1, sim_time=0.0, mass_unit=nothing,
                      time_unit=nothing, velocity_unit=nothing,
                      magnetic_unit=nothing,
                      periodicity=(true, true, true),
                      geometry="cartesian")

Load a uniform grid of in-memory data into yt.

This should allow a uniform grid of data to be loaded directly into yt and
analyzed. This comes with several caveats:

* Units will be incorrect unless the unit system is explicitly
  specified.
* Particles may be difficult to integrate.

Particle fields are detected as one-dimensional fields. The number of
particles is set by the `number_of_particles` key in data.

# Arguments

* `data::Dict`: A dict of Arrays or (Array, unit string) tuples. The keys are
  the field names.
* `domain_dimensions::Array`: These are the domain dimensions of the grid
* `length_unit=nothing`: Unit to use for lengths. Defaults to 1 cm.
* `bbox=nothing`: Size of computational domain in units specified by
  `length_unit`. Defaults to a cubic unit-length domain.
* `nprocs::Integer=1`: If greater than 1, will create this number of subgrids
  out of data
* `sim_time::Real=0.0`: The simulation time.
* `mass_unit=nothing`: Unit to use for lengths. Defaults to 1 g.
* `time_unit=nothing`: Unit to use for lengths. Defaults to 1 s.
* `velocity_unit=nothing`: Unit to use for lengths. Defaults to 1 cm/s.
* `magnetic_unit=nothing`: Unit to use for lengths. Defaults to 1 gauss.
* `periodicity::Tuple{Bool,Bool,Bool}=(true, true, true)`: Determines whether
  the data will be treated as periodic along each axis.
* `geometry::String="cartesian"``: "cartesian", "cylindrical", or "polar"

# Examples
```julia
julia> import YT
julia> arr = rand(64,64,64)
julia> data = Dict()
julia> data["density"] = (arr, "g/cm^3")
julia> bbox = [-1.5 1.5; -1.5 1.5; -1.5 1.5]
julia> ds = YT.load_uniform_grid(data, [64,64,64]; length_unit="Mpc",
                                 bbox=bbox, nprocs=64)
```
"""
function load_uniform_grid(data::Dict{Any,Any}, domain_dimensions::Array;
                           length_unit=nothing, bbox=nothing,
                           nprocs=1, sim_time=0.0, mass_unit=nothing,
                           time_unit=nothing, velocity_unit=nothing,
                           magnetic_unit=nothing,
                           periodicity=(true, true, true),
                           geometry="cartesian")
    ds = ytstream[:load_uniform_grid](data, domain_dimensions; length_unit=length_unit,
                                      bbox=bbox, nprocs=nprocs, sim_time=sim_time,
                                      mass_unit=mass_unit, time_unit=time_unit,
                                      velocity_unit=velocity_unit,
                                      magnetic_unit=magnetic_unit,
                                      periodicity=periodicity, geometry=geometry)
    return Dataset(ds)
end

"""
    load_amr_grids(data::Array, domain_dimensions::Array;
                   bbox=nothing, sim_time=0.0, length_unit=nothing,
                   mass_unit=nothing, time_unit=nothing,
                   velocity_unit=nothing, magnetic_unit=nothing,
                   periodicity=(true, true, true), geometry="cartesian",
                   refine_by=2)

Load a set of grids of data, of varying resolution. This comes with
several caveats:

* Particles may be difficult to integrate.
* No consistency checks are performed on the index

# Arguments

* `grid_data::Array`: This is an Array of Dicts. Each Dict must have entries
  "left_edge", "right_edge", "dimensions", "level", and then any remaining
  entries are assumed to be fields. Field entries must map to an Array. The
  grid_data may also include a particle count. If no particle count is supplied,
  the dataset is understood to contain no particles. The grid_data will be
  modified in place and can't be assumed to be static.
* `domain_dimensions::Array`: These are the domain dimensions of the grid
* `length_unit=nothing`: Unit to use for lengths. Defaults to 1 cm.
* `bbox=nothing`: Size of computational domain in units specified by
  `length_unit`. Defaults to a cubic unit-length domain.
* `sim_time::Real=0.0`: The simulation time.
* `mass_unit=nothing`: Unit to use for lengths. Defaults to 1 g.
* `time_unit=nothing`: Unit to use for lengths. Defaults to 1 s.
* `velocity_unit=nothing`: Unit to use for lengths. Defaults to 1 cm/s.
* `magnetic_unit=nothing`: Unit to use for lengths. Defaults to 1 gauss.
* `periodicity::Tuple{Bool,Bool,Bool}=(true, true, true)`: Determines whether
  the data will be treated as periodic along each axis.
* `geometry::String="cartesian"`: "cartesian", "cylindrical", or "polar"
* `refine_by::Integer=2`: Specifies the refinement ratio between levels.

# Examples
```julia
julia> import YT
julia> grid_data = [
         Dict("left_edge"=>[0.0, 0.0, 0.0],
              "right_edge"=>[1.0, 1.0, 1.0],
              "level"=>0,
              "dimensions"=>[32, 32, 32]),
         Dict("left_edge"=>[0.25, 0.25, 0.25],
              "right_edge"=>[0.75, 0.75, 0.75],
              "level"=>1,
              "dimensions"=>[32, 32, 32])
       ]
julia> for g in grid_data
           g["density"] = (rand(g["dimensions"]...) * 2^g["level"], "g/cm^3")
       end
julia> ds = YT.load_amr_grids(grid_data, [32, 32, 32])
```
"""
function load_amr_grids(data::Array, domain_dimensions::Array;
                        bbox=nothing, sim_time=0.0, length_unit=nothing,
                        mass_unit=nothing, time_unit=nothing,
                        velocity_unit=nothing, magnetic_unit=nothing,
                        periodicity=(true, true, true), geometry="cartesian", refine_by=2)
    ds = ytstream[:load_amr_grids](data, domain_dimensions; bbox=bbox, sim_time=sim_time,
                                   length_unit=length_unit, mass_unit=mass_unit, time_unit=time_unit,
                                   velocity_unit=velocity_unit, magnetic_unit=magnetic_unit,
                                   periodicity=periodicity, geometry=geometry, refine_by=refine_by)
    return Dataset(ds)
end

"""
    load_particles(data::Dict{Any,Any}; length_unit=nothing, bbox=nothing,
                   sim_time=0.0, mass_unit=nothing, time_unit=nothing,
                   velocity_unit=nothing, magnetic_unit=nothing,
                   periodicity=(true, true, true), n_ref=64,
                   over_refine_factor=1, geometry="cartesian")

Load a set of particles into yt.

This should allow a collection of particle data to be loaded directly into
yt and analyzed as would any others.

This will initialize an Octree of data. Note that fluid fields will not
work yet, or possibly ever.

# Arguments

* `data::Dict`: This is a dict of Arrays, where the keys are the field names.
  Particle positions must be named "particle_position_x", "particle_position_y",
  "particle_position_z".
* `length_unit=nothing`: Unit to use for lengths. Defaults to 1 cm.
* `bbox=nothing`: Size of computational domain in units specified by
  `length_unit`. Defaults to a cubic unit-length domain.
* `sim_time::Real=0.0`: The simulation time.
* `mass_unit=nothing`: Unit to use for lengths. Defaults to 1 g.
* `time_unit=nothing`: Unit to use for lengths. Defaults to 1 s.
* `velocity_unit=nothing`: Unit to use for lengths. Defaults to 1 cm/s.
* `magnetic_unit=nothing`: Unit to use for lengths. Defaults to 1 gauss.
* `periodicity::Tuple{Bool,Bool,Bool}=(true, true, true)`: Determines whether
  the data will be treated as periodic along each axis.
* `geometry::String="cartesian"`: "cartesian", "cylindrical", or "polar"
* `n_ref::Integer=64` (optional): The number of particles that result in refining an
oct used for indexing the particles.

# Examples
```julia
julia> import YT
julia> n_particles = 5000000
julia> data = Dict()
julia> data["particle_position_x"] = 1.0e6*randn(n_particles)
julia> data["particle_position_y"] = 1.0e6*randn(n_particles)
julia> data["particle_position_z"] = 1.0e6*randn(n_particles)
julia> data["particle_mass"] = ones(n_particles)
julia> bbox = 1.1*[minimum(data["particle_position_x"])
                   maximum(data["particle_position_x"]);
                   minimum(data["particle_position_y"])
                   maximum(data["particle_position_y"]);
                   minimum(data["particle_position_z"])
                   maximum(data["particle_position_z"])]
julia> ds = YT.load_particles(data, length_unit="pc",
                              mass_unit=(1e8, "Msun"),
                              n_ref=256, bbox=bbox)
```
"""
function load_particles(data::Dict{Any,Any}; length_unit=nothing, bbox=nothing,
                        sim_time=0.0, mass_unit=nothing, time_unit=nothing,
                        velocity_unit=nothing, magnetic_unit=nothing,
                        periodicity=(true, true, true), n_ref=64,
                        over_refine_factor=1, geometry="cartesian")
    ds = ytstream[:load_particles](data; length_unit=length_unit, bbox=bbox,
                                   sim_time=sim_time, mass_unit=mass_unit,
                                   time_unit=time_unit, velocity_unit=velocity_unit,
                                   magnetic_unit=magnetic_unit, periodicity=periodicity,
                                   n_ref=n_ref, over_refine_factor=over_refine_factor,
                                   geometry=geometry)
    return Dataset(ds)
end

end
