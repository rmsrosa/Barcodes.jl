# Get pattern

# Pattern from the values of the symbols
function _pattern_from_values(values::AbstractVector{<:Integer})
    _check_framing(values)

    # The quiet zone is at least 10x, where x is the width of each module, assumed here to be
    # one bit. We use 11x just to have the same length as the other symbols (except the double
    # bar termination symbol).
    quiet_zone = "0"^11

    # "END" bars: the STOP symbol is followed by the double bar
    return quiet_zone * join(CODE128_PATTERNS[Int(v)+1] for v in values) * "11" * quiet_zone
end

"""
    barcode_pattern(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)

Return a string with the binary pattern for a given vector of codes following the
specifications determined by the `encoding_type`.

Currently, only Code128 specification is available.

The vector `code` has the names of the symbols, as returned by `encode`. It should start with
either `START A`, `START B`, or `START C`, and end with `STOP`. The element before `STOP` is
the checksum, which should be either `CHECKSUM` or `CHECKSUM n`, and it is always computed.

# Examples

```jldoctest
julia> using Barcodes

julia> pattern = Barcodes.barcode_pattern(
           ["START C", "00", "01", "32", "CHECKSUM", "STOP"],
           :code128
       )
"000000000001101001110011011001100110011011001100011011010111101110110001110101100000000000"

julia> pattern = Barcodes.barcode_pattern(
           ["START A", "A", "B", "C", "CHECKSUM", "STOP"],
           :code128
       )
"000000000001101000010010100011000100010110001000100011011011001100110001110101100000000000"
```
"""
function barcode_pattern(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    return _pattern_from_values(_parse_names(code))
end

"""
    barcode_pattern(msg::AbstractString, encoding_type::Symbol)

Generate the barcode pattern for the given `msg`, according to the encoding Code128.

If `encoding_type` is set to either `:code128a`, `:code128b`, or `:code128c`, it returns
the encoding following the corresponding subtype. It throws an `ArgumentError` if the given
`msg` is not suitable for encoding with the given subtype.

If `encoding_type` is set to `:code128`, it attempts to use either of these subtypes or
a combination of them. It throws an `ArgumentError` if not possible to do so.

The pattern is returned as a string of 0's and 1's, with the proper quiet zones, and the
`START`, `STOP`, checksum, and ending bar patterns.
"""
function barcode_pattern(msg::AbstractString, encoding_type::Symbol)
    return _pattern_from_values(_encode_values(msg, encoding_type))
end

# Values of the symbols from the pattern
function _values_from_pattern(pattern::AbstractString)
    all(d -> d in ('0', '1'), pattern) || throw(
        ArgumentError(
            "A barcode pattern should be made of 0's and 1's only"
        )
    )

    firstbar = findfirst(==('1'), pattern)
    lastbar = findlast(==('1'), pattern)
    (firstbar !== nothing && lastbar - firstbar ≥ 34) || throw(
        ArgumentError(
            "Barcode pattern is too short to be a Code128 barcode pattern"
        )
    )
    pattern[lastbar-1:lastbar] == "11" || throw(
        ArgumentError(
            "Barcode pattern does not end properly with a double bar"
        )
    )
    rem(lastbar - firstbar - 1, 11) == 0 || throw(
        ArgumentError(
            "Barcode pattern contents should have a length multiple of 11"
        )
    )

    values = UInt8[]
    for i in firstbar:11:lastbar-2
        p = pattern[i:i+10]
        v = get(CODE128_PATTERN2VALUE, p, nothing)
        v === nothing && throw(ArgumentError("$p is not a valid CODE128 pattern"))
        push!(values, v)
    end

    _check_framing(values)

    values[end-1] == _checksum(values) ||
        throw(ArgumentError("Barcode checksum does not match computed checksum"))

    return values
end

"""
    barcode_depattern(pattern::AbstractString, encoding_type::Symbol)

Return the code, a vector with the names of the symbols, for the given binary `pattern`.

It throws an `ArgumentError` if the `pattern` is not a valid Code128 pattern, including when
its checksum is wrong.
"""
function barcode_depattern(pattern::AbstractString, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    return _names(_values_from_pattern(pattern))
end

"""
    barcode_decode(pattern::AbstractString, encoding_type::Symbol)

Return the message encoded in the given binary `pattern`.

It throws an `ArgumentError` if the `pattern` is not a valid Code128 pattern, including when
its checksum is wrong.
"""
function barcode_decode(pattern::AbstractString, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    return _decode_values(_values_from_pattern(pattern))
end

# Experimental
# Works nice in some places but in others there is a separation between the lines that breaks the image
function utf8block_pattern(pattern::AbstractString)
    iseven(length(pattern)) || (pattern *= '0')
    a = BitVector(c == '1' for c in pattern)
    s = prod(getindex(" ▐▌█", [[1, 2, 5, 8][2*a[i] + a[i+1] + 1]]) for i in 1:2:length(a))
    return s
end
