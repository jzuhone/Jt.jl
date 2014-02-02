module yt_array

import Base: cbrt, convert, copy, eltype, hypot, maximum, minimum, ndims,
             similar, show, size, sqrt
using SymPy
using PyCall
@pyimport yt
import ..utils: pyslice

# Grab the classes for creating YTArrays and YTQuantities

ytarray_new = yt.units["yt_array"]["YTArray"]
ytquantity_new = yt.units["yt_array"]["YTQuantity"]

function fix_sqrt_units(units::String)
    m = match(r"sqrt\((.*?)\)", units)
    if m != nothing
        subunit = m.captures[1]
        return replace(units, "sqrt($subunit)", "($subunit)**0.5")
    else
        return units
    end
end

# YTQuantity definition

type YTQuantity
    ytquantity::PyObject
    quantity::Real
    units::Sym
    dimensions::String
    function YTQuantity(ytquantity::PyObject)
        new(ytquantity, ytquantity[:ndarray_view]()[1],
            ytquantity[:units], ytquantity[:units][:dimensions][:__str__]())
    end
    function YTQuantity(quantity::Real, units::String)
        units_str = fix_sqrt_units(units)
        if units_str == "dimensionless"
            units_str = ""
        end
        ytquantity = pycall(ytquantity_new, PyObject, quantity, units_str)
        new(ytquantity, ytquantity[:ndarray_view]()[1],
            ytquantity[:units], ytquantity[:units][:dimensions][:__str__]())
    end
    YTQuantity(quantity::Real, units::Sym) = YTQuantity(quantity, units[:__str__]())
    YTQuantity(quantity::Real, q::YTQuantity) = YTQuantity(quantity, q.units)
end

# YTArray definition

type YTArray <: AbstractArray
    array::AbstractArray
    quantity::YTQuantity
    units::Sym
    dimensions::String
    function YTArray(ytarray::PyObject)
        quantity = YTQuantity(1.0, ytarray[:units])
        new(pycall(ytarray["ndarray_view"], PyArray),
            quantity, ytarray[:units], ytarray[:units][:dimensions][:__str__]())
    end
    function YTArray(array::AbstractArray, units::String)
        quantity = YTQuantity(1.0, units)
        new(array, quantity, quantity.units, quantity.units[:dimensions][:__str__]())
    end
    YTArray(array::AbstractArray, units::Sym) = YTArray(array, units[:__str__]())
    YTArray(array::AbstractArray, q::YTQuantity) = YTArray(array, q.units)
end

# Helper function
function get_array(a::YTArray)
    if typeof(a.array) <: PyArray
        return copy(a.array)
    else
        return a.array
    end
end

# Copy, similar

function copy(q::YTQuantity)
    YTQuantity(q.quantity, q)
end
function copy(a::YTArray)
    YTArray(get_array(a), a.units)
end

# Conversions

convert(::Type{YTArray}, o::PyObject) = YTArray(o)
convert(::Type{YTQuantity}, o::PyObject) = YTQuantity(o)
function convert(::Type{Array}, a::YTArray)
    get_array(a)
end
function convert(::Type{Real}, q::YTQuantity)
    q.quantity
end

# Indexing, ranges (slicing)

IntOrRange = Union(Int,Range,Range1)
RealOrArray = Union(Real,Array)

getindex(a::YTArray, i::Int) = YTQuantity(a.array[i], a.units)
# Hack to PyArray to conserve memory
getindex(a::PyArray, idxs::Ranges) = pycall(a.o["__getitem__"], PyArray, pyslice(idxs))
getindex(a::YTArray, idxs::Ranges) = YTArray(getindex(a.array, idxs), a.units)

function setindex!(a::YTArray, x::Real, i::Int)
    a.array[i] = x
end
# Hack to PyArray to conserve memory
function setindex!(a::PyArray, x::RealOrArray, idxs::Ranges)
    pycall(a.o["__setitem__"], PyArray, pyslice(idxs), x)
end
function setindex!(a::YTArray, x::RealOrArray, idxs::Ranges)
    YTArray(setindex!(a.array, x, idxs), a.units)
end

# For grids
# Hack to PyArray to conserve memory
function getindex(a::PyArray, i::IntOrRange, j::IntOrRange, k::IntOrRange)
    pycall(a.o["__getitem__"], PyArray, (pyslice(i), pyslice(j), pyslice(k),))
end
function getindex(a::YTArray, i::IntOrRange, j::IntOrRange, k::IntOrRange)
    num_items = length(i)*length(j)*length(k)
    if num_items == 1
        return YTQuantity(getindex(a.array, i, j, k), a.units)
    else
        return YTArray(getindex(a.array, i, j, k), a.units)
    end
end

# Unit conversions

function in_units(q::YTQuantity, units::String)
    units_str = fix_sqrt_units(units)
    YTQuantity(pycall(q.ytquantity["in_units"], PyObject, units_str))
end
in_units(q::YTQuantity, units::Sym) = in_units(q, units[:__str__]())
in_units(q::YTQuantity, p::YTQuantity) = in_units(q, p.units)

function in_cgs(q::YTQuantity)
    pycall(q.ytquantity["in_cgs"], YTQuantity)
end

function in_units(a::YTArray, units::String)
    q = in_units(a.quantity, units)
    YTArray(get_array(a)*q.quantity, q.units)
end
in_units(a::YTArray, units::Sym) = in_units(a, units[:__str__]())
in_units(a::YTArray, b::YTQuantity) = in_units(a, b.units)
in_units(a::YTArray, b::YTArray) = in_units(a, b.units)

function in_cgs(a::YTArray)
    q = in_cgs(a.quantity)
    YTArray(get_array(a)*q.quantity, q.units)
end

# Basic arithmetic

# YTQuantity first

function +(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    c = a.quantity + in_units(b, a).quantity
    return YTQuantity(r, b.units)
end

function *(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if same_dims
        c = q.quantity*in_units(b, a).quantity
        units = a.units*a.units
    else
        c = a.quantity*b.quantity
        units = a.units*b.units
    end
    return YTQuantity(c, units)
end

function *(a::YTQuantity, b::Real)
    c = b*a.quantity
    return YTQuantity(c, a)
end

*(a::Real, b::YTQuantity) = *(b, a)
/(a::YTQuantity, b::Real) = *(a, 1.0/b)
\(a::YTQuantity, b::Real) = /(b,a)

function /(a::Real, b::YTQuantity)
    c = a/b.quantity
    units = "1/\($(b.units[:__str__]())\)"
    return YTQuantity(c, units)
end

\(a::Real, b::YTQuantity) = /(b,a)

function ^(a::YTQuantity, b::Integer)
    c = a.quantity^b
    units = a.units^b
    return YTQuantity(c, units)
end

function ^(a::YTQuantity, b::Real)
    c = a.quantity^b
    units = a.units^b
    return YTQuantity(c, units)
end

-(a::YTQuantity, b::YTQuantity) = +(a,-b)
/(a::YTQuantity, b::YTQuantity) = *(a,1.0/b)
\(a::YTQuantity, b::YTQuantity) = /(b,a)

function *(a::YTQuantity, b::Array)
    c = b*a.quantity
    return YTArray(c, a)
end

*(a::Array, b::YTQuantity) = *(b, a)
/(a::YTQuantity, b::Array) = *(a, 1.0/b)
/(a::Array, b::YTQuantity) = *(a, 1.0/b)
\(a::YTQuantity, b::Array) = /(b,a)
\(a::Array, b::YTQuantity) = /(b,a)
-(a::YTQuantity) = *(-1.0, a)

function *(a::YTQuantity, b::PyArray)
    c = copy(b)*a.quantity
    return YTArray(c, a)
end

*(a::PyArray, b::YTQuantity) = *(b, a)
/(a::YTQuantity, b::PyArray) = *(a, 1.0/b)
/(a::PyArray, b::YTQuantity) = *(a, 1.0/b)
\(a::YTQuantity, b::PyArray) = /(b,a)
\(a::PyArray, b::YTQuantity) = /(b,a)
-(a::YTQuantity) = *(-1.0, a)

# YTArray next

function +(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    c = get_array(a) + in_units(b, a.units).array
    return YTArray(c, a.units)
end

function .*(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if same_dims
        c = get_array(a).*in_units(b, a.units).array
        units = a.units*a.units
    else
        c = get_array(a).*get_array(b)
        units = a.units*b.units
    end
    if units[:__str__]() == "dimensionless"
        return c
    else
        return YTArray(c, units)
    end
end

function *(a::YTArray, b::Real)
    c = b*get_array(a)
    return YTArray(c, a.units)
end

-(a::YTArray) = *(-1.0, a)
*(a::Real, b::YTArray) = *(b, a)
/(a::YTArray, b::Real) = *(a, 1.0/b)
\(a::YTArray, b::Real) = /(b,a)

function /(a::Real, b::YTArray)
    c = a/get_array(b)
    quantity = 1.0/b.quantity
    return YTArray(c, quantity)
end

\(a::Real, b::YTArray) = /(b,a)

-(a::YTArray, b::YTArray) = +(a,-b)
./(a::YTArray, b::YTArray) = .*(a,1.0/b)
.\(a::YTArray, b::YTArray) = ./(b, a)

function .*(a::YTArray, b::Array)
    c = b.*get_array(a)
    return YTArray(c, a.units)
end

.*(a::Array, b::YTArray) = .*(b, a)
./(a::YTArray, b::Array) = .*(a, 1.0/b)
./(a::Array, b::YTArray) = .*(a, 1.0/b)
.\(a::YTArray, b::Array) = ./(b, a)
.\(a::Array, b::YTArray) = ./(b, a)

function .^(a::YTArray, b::Real)
    c = get_array(a).^b
    units = a.units^b
    return YTArray(c, units)
end

function +(a::YTQuantity, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Array and quantity are not in the same dimensions!")
    end
    c = a + in_units(b, a.units).array
    return YTArray(c, a.units)
end
+(a::YTQuantity, b::YTArray) = +(b,a)
-(a::YTArray, b::YTQuantity) = +(a,-b)
-(a::YTQuantity, b::YTArray) = -(b,a)

function *(a::YTQuantity, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if same_dims
        c = a.quantity*in_units(b, a.units).array
        units = a.units*a.units
    else
        c = a.quantity*get_array(b)
        units = a.units*b.units
    end
    if units[:__str__]() == "dimensionless"
        return c
    else
        return YTArray(c, units)
    end
end

*(a::YTArray, b::YTQuantity) = *(b,a)
/(a::YTArray, b::YTQuantity) = *(a, 1.0/b)
/(a::YTQuantity, b::YTArray) = *(a, 1.0/b)
\(a::YTArray, b::YTQuantity) = /(b,a)
\(a::YTQuantity, b::YTArray) = /(b,a)

# Comparison functions

function .==(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .== in_units(b,a.units).array
end

function .!=(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .!= in_units(b,a.units).array
end

function .>=(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .>= in_units(b,a.units).array
end

function .<=(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .<= in_units(b,a.units).array
end

function .>(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .> in_units(b,a.units).array
end

function .<(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    return get_array(a) .< in_units(b,a.units).array
end

function ==(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity == in_units(b,a.units).quantity
end

function !=(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions[:__str__]() == b.dimensions[:__str__]()
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity != in_units(b,a.units).quantity
end

function >=(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity >= in_units(b,a.units).quantity
end

function <=(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity <= in_units(b,a.units).quantity
end

function >(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity > in_units(b,a.units).quantity
end

function <(a::YTQuantity, b::YTQuantity)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Quantities are not in the same dimensions!")
    end
    return a.quantity < in_units(b,a.units).quantity
end

# Mathematical functions

function sqrt(a::YTQuantity)
    c = sqrt(a.quantity)
    units = "\($(a.units[:__str__]())\)**0.5"
    return YTQuantity(c, units)
end

function sqrt(a::YTArray)
    c = sqrt(a.array)
    units = "\($(a.units[:__str__]())\)**0.5"
    return YTArray(c, units)
end

function cbrt(a::YTQuantity)
    return YTQuantity(cbrt(a.quantity), (a.units)^(1/3))
end

function cbrt(a::YTArray)
    c = cbrt(a.array)
    units = cbrt(a.units)
    return YTArray(c, units)
end

maximum(a::YTArray) = YTQuantity(maximum(a.array), a.units)
minimum(a::YTArray) = YTQuantity(minimum(a.array), a.units)

function hypot(a::YTArray, b::YTArray)
    same_dims = a.dimensions == b.dimensions
    if !same_dims
        error("Arrays are not in the same dimensions!")
    end
    c = hypot(a.array, b.array)
    return YTArray(c, a.units)
end

hypot(a::YTArray, b::YTArray, c::YTArray) = hypot(hypot(a,b), c)

# Show

function show(io::IO, a::YTArray)
    num_cells = length(a)
    if num_cells == 0
        println(io, "[] $(a.units)")
        return
    end
    if num_cells == 1
        println(io, "[ $(a.array[1]) ] $(a.units)")
        return
    end
    n = num_cells > 8 ? 5 : num_cells
    println(io, "[ $(a.array[1]),")
    for x in a.array[2:n-1]
        println(io, "  $(x),")
    end
    if num_cells > 8
        println(io, "  ...")
        for x in a.array[num_cells-3:num_cells-1]
            println(io, "  $x,")
        end
    end
    println(io, "  $(a.array[end]) ] $(a.units)")
end

function show(io::IO, q::YTQuantity)
    println(io,"$(q.quantity) $(q.units)")
end

# Array methods

size(a::YTArray) = size(a.array)
size(a::YTArray, n::Integer) = size(a.array, n)

ndims(a::YTArray) = ndims(a.array)

eltype(a::YTArray) = eltype(a.array)

end