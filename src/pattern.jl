# Get pattern

function _barcode_pattern_code128(code::Vector{<:AbstractString})

    m = match(r"^START (A|B|C)$", first(code))
    m !== nothing || throw(
        ArgumentError(
            "First element of `code` should be either `START A`, `START B` or `START C`",
        ),
    )

    last(code) == "STOP" ||
        throw(ArgumentError("Last element of `code` should be `STOP`"))

    count(code .== "STOP") == 1 ||
        throw(ArgumentError("""There should be only one "STOP" in the encoding sequence"""))

    count(match.(r"^START [ABC]$", code) .!== nothing) == 1 ||
        throw(
            ArgumentError(
                "There should be only one r\"START [ABC]\" in the encoding sequence"
            )
        )

    subtype = Symbol("code128$(lowercase(m.captures[1]))")
    nextsubtype = subtype

    # initialize pattern with the quiet zone, which is at least 10x, where x is
    # the width of each module, assumed here to be one bit. We use 11x just to have the
    # same length as the other symbols (except the double bar termination symbol).
    quiet_zone = "0"^11
    pattern = [quiet_zone]

    nrow = findfirst(==(first(code)), CODE128[!, subtype])
    push!(pattern, CODE128.pattern[nrow])
    chk_sum = CODE128.value[nrow]
    multiplier = 0

    for c in code[2:end]

        multiplier += 1

        if startswith(c, "CHECKSUM")
            push!(pattern, CODE128.pattern[rem(chk_sum, 103)+1])
            chk_sum += multiplier * chk_sum
        else
            nrow = findfirst(==(c), CODE128[!, nextsubtype])
            nrow === nothing && throw(
                ArgumentError(
                    "$c is not part of subtype $(titlecase(string(nextsubtype))) of Code128",
                ),
            )
            push!(pattern, CODE128.pattern[nrow])
            chk_sum += multiplier * CODE128.value[nrow]

            nextsubtype = subtype
            m = match(r"^CODE (A|B|C)$", c)
            if m !== nothing
                subtype = nextsubtype = Symbol("code128$(lowercase(m.captures[1]))")
            end

            m = match(r"^SHIFT (A|B)$", c)
            if m !== nothing
                nextsubtype = Symbol("code128$(lowercase(m.captures[1]))")
            end

        end
    end
    # "END" bars
    push!(pattern, "11")

    # Quiet zone
    push!(pattern, quiet_zone)

    pattern = prod(pattern)
    return pattern
end

"""
    barcode_pattern(code::Vector{<:AbstractString}, encoding_type::Symbol)

Return a string with the binary pattern for a given vector of codes 
following the specifications determined by the `encoding_type`.

Currently, only Code128 specification is available.

If `encoding_type` is either `:code128a`, `:code128b`, or `:code128c`, it returns the
encoding following the corresponding subtype. If `encoding_type` is `:code128`, it returns
an optimized encoding, possibily mixing different subtypes. This strategy follows
the specifications in "GS1 General Specifications, Version 13, Issue 1, Jan-2013,
Section 5.4.7.7. Use of Start, Code Set, and Shift symbols to Minimize Symbol Length
(Informative), pages 268 to 269."

It is assumed that `code` starts with either `START A`, `START B`, or `START C` and that
it ends with `STOP`.

The checksum must either be already computed or one can add an element `CHECKSUM`
for the check sum to be computed and included where this directive appears.

# Examples

```jldoctest
julia> pattern = barcode_pattern(
           ["START C", "00", "01", "32", "CHECKSUM", "STOP"],
           :code128
       )
"000000000001101001110011011001100110011011001100011011010111101110110001110101100000000000"

julia> pattern = barcode_pattern(
           ["START A", "A", "B", "C", "CHECKSUM", "STOP"],
           :code128
       )
"000000000001101000010010100011000100010110001000100011011011001100110001110101100000000000"
```
"""
function barcode_pattern(code::Vector{<:AbstractString}, encoding_type::Symbol)
    if encoding_type in (:code128, :code128a, :code128b, :code128c)
        pattern = _barcode_pattern_code128(code)
    else
        throw(
            ArgumentError(
                "Pattern encoding for encoding type `$encoding_type` not implemented"
            )
        )
    end
    return pattern
end

"""
    barcode_pattern(msg::AbstractString, encoding_type::Symbol)

Generate the barcode pattern for the given `msg`, according to the encoding Code128.

If `encoding_type` is set to either `:code128a`, `:code128b`, or `:code128c`, it returns
the encoding following the corresponding subtype. It throws an `ArgumentError` if the given
`msg` is not suitable for encoding with the given subtype.

If `encoding_type` is set to `:code128`, it attempts to use either of these subtypes or
a combination of them. It throws an `ArgumentError` if not possible to do so.

The encoding is returned as a vector of string patterns, with each element corresponding
to the encoding of each symbol in `code`, and appended with the proper quiet zones and the
`START`, `STOP`, checksum, and ending bar patterns.
"""
function barcode_pattern(msg::AbstractString, encoding_type::Symbol)
    code = encode(msg, encoding_type)
    return barcode_pattern(code, encoding_type)
end

function _split_pattern_code128(pattern::AbstractString)
    all(d -> d in ('0', '1'), pattern) || throw(
        ArgumentError(
            "A barcode pattern should be made of 0's and 1's only"
        )
    )

    firstbar = findfirst(==('1'), pattern)
    lastbar = findlast(==('1'), pattern)
    lastbar - firstbar ≥ 34 || throw(
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
    
    core_patterns = [pattern[i:i+10] for i in firstbar:11:lastbar-2]

    first(core_patterns) in CODE128[104:106, :pattern] || throw(
        ArgumentError(
            "Barcode pattern should start with a pattern for either `START A`, " *
            "`START B`, or `START C`" 
        )
    )

    last(core_patterns) == CODE128[107, :pattern] || throw(
        ArgumentError(
            "Barcode pattern should end with the pattern for `STOP`"
        )
    )

    count(core_patterns .== CODE128[107, :pattern]) == 1 ||
        throw(ArgumentError("There should be only one pattern for \"STOP\""))

    count([p in CODE128[104:106, :pattern] for p in core_patterns]) == 1 ||
        throw(ArgumentError("There should be only one pattern for r\"START [ABC]\""))

    splited_pattern = [
        pattern[begin:firstbar-1]
        core_patterns
        "11"
        pattern[lastbar+1:end]
    ]

    return splited_pattern
end

function _barcode_depattern_code128(pattern::AbstractString)

    splited_pattern = _split_pattern_code128(pattern)

    # initialize code with the subtype START code
    code = CODE128.code128a[CODE128[!, :pattern] .== splited_pattern[2]]
    nextsubtype = subtype = Symbol("code128$(lowercase(first(code)[end]))")

    nrow = findfirst(==(first(code)), CODE128[!, subtype])
    chk_sum = CODE128.value[nrow]
    multiplier = 0

    # skip quiet zone and START [ABC]
    # stop before CHECKSUM, STOP, END, and last quiet zone
    for p in splited_pattern[3:end-4]

        multiplier += 1

        nrow = findfirst(==(p), CODE128[!, :pattern])
        nrow === nothing && throw(
            ArgumentError(
                "$p is not a valid CODE128 pattern",
            ),
        )
        push!(code, CODE128[nrow, nextsubtype])
        chk_sum += multiplier * CODE128.value[nrow]

        nextsubtype = subtype

        p == CODE128.pattern[99] && (
            (subtype == :code128a && (nextsubtype = :code128b)) ||
            (subtype == :code128b && (nextsubtype = :code128a))
        )
        p == CODE128.pattern[100] && subtype in (:code128a, :code128b) &&
            (subtype = nextsubtype = :code128c)
        p == CODE128.pattern[101] && subtype in (:code128a, :code128c) &&
            (subtype = nextsubtype = :code128b)
        p == CODE128.pattern[102] && subtype in (:code128b, :code128c) &&
            (subtype = nextsubtype = :code128a)
    end

    chk_sum = chk_sum % 103
    CODE128.value[CODE128.pattern .== splited_pattern[end-3]][1] == chk_sum ||
        throw(ArgumentError("Barcode checksum does not match computed checksum"))
    push!(code, "CHECKSUM $chk_sum")
    push!(code, "STOP")

    return code
end

function barcode_depattern(pattern::AbstractString, encoding_type::Symbol)
    encoding_type in (:code128, :code128a, :code128b, :code128c) || throw(
        ArgumentError(
            "Decoding type `$(repr(encoding_type))` not implemented"
        )
    )
    encoding_type == :code128 && (code = _barcode_depattern_code128(pattern))

    return code
end
    
function barcode_decode(pattern::AbstractString, encoding_type::Symbol)
    encoding_type in (:code128, :code128a, :code128b, :code128c) || throw(
        ArgumentError(
            "Decoding type `$(repr(encoding_type))` not implemented"
        )
    )
    encoding_type == :code128 && (code = _barcode_depattern_code128(pattern))
    
    msg = decode(code, encoding_type)

    return msg
end

# Experimental
# Works nice in some places but in others there is a separation between the lines that breaks the image
function utf8block_pattern(pattern::String)
    iseven(length(pattern)) || (pattern *= '0')
    a = BitVector(c == '1' for c in pattern * '0'^isodd(length(pattern)))
    s = prod(getindex(" ▐▌█", [[1, 2, 5, 8][2*a[i] + a[i+1] + 1]]) for i in 1:2:length(a))
    return s
end
