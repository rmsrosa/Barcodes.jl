"""
    abstract type Barcode end

Abstract supertype for all the barcodes.
"""
abstract type Barcode end

"""
    struct Code128 <: Barcode

Composite type for Code128 barcode.

The only field is `values`, a vector with the values (from 0 to 106) of the symbols of the
barcode, in the form `[START, data..., CHECKSUM, STOP]`. The other properties of the
barcode are obtained from it with the functions [`message`](@ref), [`subtype`](@ref),
[`codenames`](@ref), [`checksum`](@ref), and [`barcode_pattern`](@ref).

A `Code128` can be created from

* a message: `Code128(msg)`, or `Code128(msg, encoding_type)`, with `encoding_type` being
  either `:code128` (the default, which chooses the code sets with the minimal number of symbols),
  `:code128a`, `:code128b`, or `:code128c`, or `:gs1128` for a GS1-128, see [`gs1_element_string`](@ref);
* a vector with the names of the symbols, as returned by `Barcodes.encode`;
* a vector with the values of the symbols.

It throws an `ArgumentError` if the message cannot be encoded, or if the code is not a valid
Code128 (for instance, if it does not start with a `START` symbol, or if the checksum is wrong).

# Examples

```jldoctest
julia> b = Barcodes.Code128("12345678");

julia> println(b)
Code128("12345678")

julia> b.values
7-element Vector{UInt8}:
 0x69
 0x0c
 0x22
 0x38
 0x4e
 0x2f
 0x6a

julia> Barcodes.Code128(Barcodes.codenames(b)) == b
true

julia> Barcodes.Code128(b.values) == b
true

julia> println(Barcodes.Code128("ABC", :code128a))
Code128("ABC")
```
"""
struct Code128 <: Barcode
    values::Vector{UInt8}

    function Code128(values::AbstractVector{<:Integer})
        all(v -> 0 ≤ v ≤ STOP_VALUE, values) ||
            throw(ArgumentError("The values of Code128 symbols should be between 0 and 106"))
        values = collect(UInt8, values)
        _check_values(values)
        return new(values)
    end
end

Code128(msg::AbstractString, encoding_type::Symbol = :code128) =
    Code128(_encode_values(msg, encoding_type))

Code128(code::AbstractVector{<:AbstractString}) = Code128(_parse_names(code))

"""
    message(barcode::Code128)

Return the message encoded in the `barcode`.

# Examples

```jldoctest
julia> Barcodes.message(Barcodes.Code128("\\x02abc1234\\x03"))
"\\x02abc1234\\x03"
```
"""
message(barcode::Code128) = _decode_values(barcode.values)

"""
    codenames(barcode::Code128)

Return the names of the symbols of the `barcode`, as a vector of strings.

# Examples

```jldoctest
julia> Barcodes.codenames(Barcodes.Code128("Héllo"))
9-element Vector{String}:
 "START B"
 "H"
 "FNC 4"
 "i"
 "l"
 "l"
 "o"
 "CHECKSUM 73"
 "STOP"
```
"""
codenames(barcode::Code128) = _names(barcode.values)

"""
    checksum(barcode::Code128)

Return the checksum of the `barcode`, an integer between 0 and 102. It is the remainder of the
division by 103 of the value of the `START` symbol plus the sum of the values of the other
symbols, each one multiplied by its position (starting with 1 for the first symbol after
`START`).

# Examples

```jldoctest
julia> Barcodes.checksum(Barcodes.Code128("12345678"))
47
```
"""
checksum(barcode::Code128) = Int(barcode.values[end-1])

"""
    subtype(barcode::Code128)

Return either `:code128a`, `:code128b`, `:code128c`, or just `:code128` if the barcode
mixes different code sets.

# Examples

```jldoctest
julia> Barcodes.subtype(Barcodes.Code128("12345678"))
:code128c

julia> Barcodes.subtype(Barcodes.Code128("ABC", :code128a))
:code128a

julia> Barcodes.subtype(Barcodes.Code128("abc1234"))
:code128
```
"""
function subtype(barcode::Code128)
    values = barcode.values
    set = active = _start_set(values[1])
    used = Set{CodeSet}((set,))
    for i in 2:length(values)-2
        set, active = _step(set, active, values[i])
        push!(used, set, active)
    end
    return length(used) > 1 ? :code128 :
        set == SetA ? :code128a :
        set == SetB ? :code128b :
        :code128c
end

"""
    isgs1128(barcode::Code128)

Return `true` if the `barcode` is a GS1-128, that is, if it has the function character FNC 1
right after the START symbol.

# Examples

```jldoctest
julia> Barcodes.isgs1128(Barcodes.Code128("0109501101530003", :gs1128))
true

julia> Barcodes.isgs1128(Barcodes.Code128("0109501101530003"))
false
```
"""
isgs1128(barcode::Code128) = _is_gs1(barcode.values)

"""
    barcode_pattern(barcode::Code128)

Return the barcode pattern of the `barcode`, a string of 0's and 1's, as in
[`barcode_pattern(::AbstractString, ::Symbol)`](@ref).

# Examples

```jldoctest
julia> Barcodes.barcode_pattern(Barcodes.Code128("ABC")) == Barcodes.barcode_pattern("ABC", :code128)
true
```
"""
barcode_pattern(barcode::Code128) = _pattern_from_values(barcode.values)

Base.:(==)(a::Code128, b::Code128) = a.values == b.values
Base.hash(a::Code128, h::UInt) = hash(a.values, hash(:Code128, h))

# Short one-line form. Used by `print`, `repr`, string interpolation, and when
# the barcode is an element of an array or other container.
function Base.show(io::IO, barcode::Code128)
    print(io, "Code128(", repr(message(barcode)), isgs1128(barcode) ? ", :gs1128" : "", ")")
end

# Multi-line form. The REPL (and `display`) call this one for a top-level value.
function Base.show(io::IO, ::MIME"text/plain", barcode::Code128)
    s = utf8block_pattern(barcode_pattern(barcode))
    if get(io, :detailed, false)
        println(
            io, "Barcode type: ",
            isgs1128(barcode) ? "GS1-128" : uppercasefirst(string(subtype(barcode)))
        )
        print(io, "Message: ")
        printstyled(io, message(barcode), reverse = true)
        println(io)
        println(io, "Code:")
        for c in codenames(barcode)
            println(io, '\t', c)
        end
        println(io, "Barcode pattern:")
        print(io, s)
    else
        print(io, isgs1128(barcode) ? "GS1-128: " : "Code128: ")
        printstyled(io, message(barcode), reverse = true)
        print(io, "\n\n", s)
    end
end
