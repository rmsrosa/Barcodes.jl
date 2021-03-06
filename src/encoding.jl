# Encoding and decoding

# Code128 encoding with subtype Code128A
function _encode_code128a(msg::AbstractString)
    @inbounds for i = 1:ncodeunits(msg)
        codeunit(msg, i) ≤ 0x7f || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given `msg` contains characters outside the ranges 0 - 126 and " * 
                "160 - 255 and cannot be encoded in Code128"
            ),
        )
        codeunit(msg, i) ≤ 0x5f || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given ascii `msg` contains lowercase letters or characters outside " *
                "the ranges 0 - 95 and 160 - 255 and cannot be encoded in subtype Code128A"
            )
        )
        codeunit(msg, i) ≥ 0xa0 && throw(
            ArgumentError(
                "The given ascii `msg` contains extended ascii letters within the range " * 
                "160 - 255 but encoding for that has not yet been implemented"
            )
        )
    end
    
    code = ["START A"]
    @inbounds for i = 1:ncodeunits(msg)
        if 0x20 ≤ codeunit(msg, i) ≤ 0x5f
            push!(code, string(msg[i]))
        elseif codeunit(msg, i) ≤ 0x1f
            push!(code, CODE128[codeunit(msg, i) + 0x41, :code128a])
        else
            throw(
                ArgumentError(
                    "Char in position $i in `msg` cannot be encoded in subtype Code128A"
                )
            )
        end
    end
    append!(code, ["CHECKSUM", "STOP"])

    chk_sum = _checksum_code128(code)
    code[end-1] = "CHECKSUM $chk_sum"

    return code
end

# Code128 encoding with subtype Code128B
function _encode_code128b(msg::AbstractString)
    @inbounds for i = 1:ncodeunits(msg)
        codeunit(msg, i) ≤ 0x7f || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given `msg` contains characters outside the ranges 0 - 126 and " * 
                "160 - 255 and cannot be encoded in Code128"
            ),
        )
        0x20 ≤ codeunit(msg, i) || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given ascii `msg` contains symbology characters or letters outside the ranges " *
                "32 - 127 and 160 - 255 and cannot be fully encoded in subtype Code128B"
            )
        )
        codeunit(msg, i) ≥ 0xa0 && throw(
            ArgumentError(
                "The given ascii `msg` contains extended ascii letters within the range " * 
                "160 - 255 but encoding for that has not yet been implemented"
            )
        )
    end

    code = [
        "START B"
        string.(collect(msg))
        "CHECKSUM"
        "STOP"
    ]
    
    chk_sum = _checksum_code128(code)
    code[end-1] = "CHECKSUM $chk_sum"

    return code
end

# Code128 encoding with subtype Code128C
function _encode_code128c(msg::AbstractString)
    @inbounds for i = 1:ncodeunits(msg)
        codeunit(msg, i) ≤ 0x7f || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given `msg` contains characters outside the ranges 0 - 126 and " * 
                "160 - 255 and cannot be encoded in Code128"
            ),
        )
        codeunit(msg, i) ≥ 0xa0 && throw(
            ArgumentError(
                "The given ascii `msg` contains extended ascii letters within the range " * 
                "160 - 255 but encoding for that has not yet been implemented"
            )
        )
    end
    all(isdigit, msg) || throw(
        ArgumentError(
            "The given `msg` contains characters which are not digits and cannot " *
            "be encoded in subtype Code128C"
        )
    )
    iseven(length(msg)) || throw(
        ArgumentError(
            "The given `msg` contains an odd number of digits and cannot be fully " *
            "encoded in subtype Code128C"
        )
    )

    code = [
        "START C"
        [msg[j:j+1] for j = 1:2:length(msg)]
        "CHECKSUM"
        "STOP"
    ]

    chk_sum = _checksum_code128(code)
    code[end-1] = "CHECKSUM $chk_sum"

    return code
end

# Optimized Code128 (actually GS1-128) mixed-subtype encoding following the rules in 
# "GS1 General Specifications, Version 13, Issue 1, Jan-2013, Section 5.4.7.7.
# Use of Start, Code Set, and Shift symbols to Minimize Symbol Length (Informative),
# pages 268 to 269."
function _encode_code128(msg)
    @inbounds for i = 1:ncodeunits(msg)
        codeunit(msg, i) ≤ 0x7f || 0xa0 ≤ codeunit(msg, i) ≤ 0xff || throw(
            ArgumentError(
                "The given `msg` contains characters outside the ranges 0 - 126 and " * 
                "160 - 255 and cannot be encoded in Code128"
            ),
        )
        codeunit(msg, i) ≥ 0xa0 && throw(
            ArgumentError(
                "The given ascii `msg` contains extended ascii letters within the range " * 
                "160 - 255 but encoding for that has not yet been implemented"
            )
        )
    end
    code = String[]

    len_msg = length(msg)
    are_digits = [isdigit(d) for d in msg]

    # Determine start character:
    if (length(are_digits) == 2 && are_digits == [1, 1]) || (
        length(are_digits) ≥ 4 && are_digits[1:4] == [1, 1, 1, 1]
    ) # Determine whether there are enough digits
        subtype = :code128c
    elseif UInt8(first(msg)) ≤ 0x1f # check whether it is a symbology element (NUL to US)
        subtype = :code128a
    else
        subtype = :code128b
    end

    push!(code, "START $(uppercase(string(subtype)[end]))")
    ind = 1
    nextsubtype = subtype

    while ind ≤ length(msg)
        # Determine whether it needs to change or shift subtype
        if nextsubtype == :code128c && (len_msg == ind || (len_msg > ind && are_digits[ind:ind+1] != [1, 1]))
            if codeunit(msg, ind) ≤ 0x1f ||
                    (codeunit(msg, ind) ≤ 0x5f && len_msg > ind &&
                        0 ≤ codeunit(msg, ind+1) ≤ 0x1f)
                push!(code, "CODE A")
                nextsubtype = subtype = :code128a
            else
                push!(code, "CODE B")
                nextsubtype = subtype = :code128b
            end             
        elseif nextsubtype != :code128c && are_digits[ind] && (
                (
                    findnext(iszero, are_digits, ind) !== nothing &&
                    (0, 2) ≤ reverse(divrem(findnext(iszero, are_digits, ind) - ind, 2)) < (1, 0)
                    # iseven(findnext(iszero, are_digits, ind) - ind)
                ) ||
                    
                (
                    findnext(iszero, are_digits, ind) === nothing &&
                    (0, 2) ≤ reverse(divrem(len_msg - ind + 1, 2)) < (1, 0)
                    # len_msg > ind && isodd(len_msg - ind)
                )
            )
            push!(code, "CODE C")
            nextsubtype = subtype = :code128c
        elseif nextsubtype != :code128a && codeunit(msg, ind) ≤ 0x1f # check for symbology
            if nextsubtype == :code128b &&
                    len_msg > ind && 0x60 ≤ codeunit(msg, ind+1) ≤ 0x7f
                push!(code, "SHIFT A")
                nextsubtype = :code128a
            else
                push!(code, "CODE A")
                subtype = nextsubtype = :code128a
            end
        elseif nextsubtype != :code128b && 96 ≤ Int(msg[ind]) ≤ 126 # check for lowercase
            if nextsubtype == :code128a && len_msg > ind && 0 ≤ Int(msg[ind+1]) ≤ 31
                push!(code, "SHIFT B")
                nextsubtype = :code128b
            else
                push!(code, "CODE B")
                subtype = nextsubtype = :code128b
            end
        end

        # encode msg chunk
        if nextsubtype == :code128c
            push!(code, string(msg[ind:ind+1]))
            ind += 2
        elseif nextsubtype == :code128a
            if codeunit(msg, ind) ≤ 0x1f
                push!(code, CODE128[codeunit(msg, ind) + 65, :code128a])
            else
                push!(code, string(msg[ind]))
            end
            ind += 1
        else
            if codeunit(msg, ind) == 0x7f
                push!(code, "DEL")
            else
                push!(code, string(msg[ind]))
            end
            ind += 1
        end
        nextsubtype = subtype
    end
    append!(code, ["CHECKSUM", "STOP"])

    chk_sum = _checksum_code128(code)
    code[end-1] = "CHECKSUM $chk_sum"

    return code
end

"""
    encode(msg::AbstractString, encoding_type::Symbol)

Return the encoded sequence from the given `msg`, following the specifications determined
by the `encoding_type`.

Currently, only Code128 specification is available.

If `encoding_type` is either `:code128a`, `:code128b`, or `:code128c`, it returns the
encoding following the corresponding subtype. If `encoding_type` is `:code128`, it will
return an optimized encoding, possibily mixing different subtypes. This strategy
follows the specifications in "GS1 General Specifications, Version 13, Issue 1, Jan-2013,
Section 5.4.7.7. Use of Start, Code Set, and Shift symbols to Minimize Symbol Length
(Informative), pages 268 to 269."

The `msg` needs to be a string of ascii characteres to be encoded, otherwise the method
throws an `ArgumentError`.

# Examples

```jldoctest
julia> code = encode("000132", :code128c)
6-element Vector{String}:
 "START C"
 "00"
 "01"
 "32"
 "CHECKSUM"
 "STOP"

julia> code = encode("ABC", :code128a)
6-element Vector{String}:
 "START A"
 "A"
 "B"
 "C"
 "CHECKSUM"
 "STOP"

julia> code = encode("AaBC\x02", :code128)
9-element Vector{String}:
 "START B"
 "A"
 "a"
 "B"
 "C"
 "CODE A"
 "\x02"
 "CHECKSUM"
 "STOP"
```
"""
function encode(msg::AbstractString, encoding_type::Symbol)
    if encoding_type == :code128
        return _encode_code128(msg)
    elseif encoding_type == :code128a
        return _encode_code128a(msg)
    elseif encoding_type == :code128b
        return _encode_code128b(msg)
    elseif encoding_type == :code128c
        return _encode_code128c(msg)
    else
        throw(
            ArgumentError(
                "Encoding type `$(Meta.quot(mode))` not implemented"
            )
        )
    end
end

function _decode_code128(code::Vector{String})
    m = match(r"^START (A|B|C)$", first(code))
    m !== nothing || throw(
        ArgumentError(
            "First element of `code` should be either `START A`, `START B` or `START C`"
        ),
    )
    subtype = Symbol("code128$(lowercase(m.captures[1]))")
    nextsubtype = subtype    
    msg = ""

    for c in code
        if startswith(c, r"^CODE [A|B|C]$")
            nextsubtype = subtype = Symbol("code128$(lowercase(c[end]))")
        elseif startswith(c, r"^SHIFT [A|B|C]$")
            nextsubtype = Symbol("code128$(lowercase(c[end]))")
        elseif nextsubtype == :code128a && !startswith(c, "CHECKSUM")
            val = CODE128.value[CODE128.code128a .== c][1]
            if val ≤ 0x3f # check if ≤ 63
                msg *= Char(val + 0x20) # add 32
            elseif val ≤ 0x5f # check if ≤ 95
                msg *= Char(val - 0x40) # subtract 64
            end
        elseif nextsubtype == :code128b && !startswith(c, "CHECKSUM")
            if CODE128.value[CODE128.code128b .== c][1] ≤ 94
                msg *= c
            elseif c == CODE128.code128b[96]
                msg *= "\x7f" # DEL
            end
        elseif nextsubtype == :code128c && all(isdigit, c)
            msg *= c
        end
    end
    return msg
end

"""
    decode(code::Vector{String}, encoding_type::Symbol)

Decode the gived encoded sequence, following the specifications determined by the
`encoding_type`.

Currently, only Code128 specification is available.

# Examples

```jldoctest
ulia> code = encode("000132", :code128)
6-element Vector{String}:
 "START C"
 "00"
 "01"
 "32"
 "CHECKSUM"
 "STOP"

julia> msg = decode(code, :code128)
"000132"

julia> code = encode("\x02ABC\x03", :code128)
8-element Vector{String}:
 "START A"
 "STX"
 "A"
 "B"
 "C"
 "ETX"
 "CHECKSUM"
 "STOP"

julia> msg = decode(code, :code128)
"\x02ABC\x03"

julia> code = encode("\x02Abc\x03", :code128)
10-element Vector{String}:
 "START A"
 "STX"
 "A"
 "CODE B"
 "b"
 "c"
 "CODE A"
 "ETX"
 "CHECKSUM"
 "STOP"
"""
function decode(code::Vector{String}, encoding_type::Symbol)
    encoding_type in (:code128, :code128a, :code128b, :code128c) ||
        throw(
            ArgumentError(
                "Decoding type `$(Meta.quot(mode))` not implemented"
            )
        )
    return _decode_code128(code::Vector{String})
end

function _checksum_code128(code::Vector{String})
    m = match(r"^START (A|B|C)$", first(code))
    m !== nothing || throw(
        ArgumentError(
            "First element of `code` should be either `START A`, `START B` or `START C`"
        ),
    )

    nextsubtype = subtype = Symbol("code128$(lowercase(first(code)[end]))")

    nrow = findfirst(==(first(code)), CODE128[:, subtype])
    chk_sum = CODE128.value[nrow]
    multiplier = 0

    # skip first START [A|B|C]
    # and stop before CHECKSUM and STOP
    for c in code[2:end-2]

        multiplier += 1

        nrow = findfirst(==(c), CODE128[:, nextsubtype])
        nrow !== nothing || throw(
            ArgumentError(
                "$c is not a valid CODE128 code",
            ),
        )
        chk_sum += multiplier * CODE128.value[nrow]

        nextsubtype = subtype

        c == "SHIFT A" && (nextsubtype = :code128a)
        c == "SHIFT B" && (nextsubtype = :code128b)
        c == "CODE A" && (subtype = nextsubtype = :code128a)
        c == "CODE B" && (subtype = nextsubtype = :code128b)
        c == "CODE C" && (subtype = nextsubtype = :code128c)
        c == "FNC 1" && (subtype = nextsubtype = :code128a)
    end

    chk_sum = chk_sum % 103
    m = match(r"(\d+)", code[end-1])
    m === nothing || parse(Int, m.captures[1]) == chk_sum || @warn "Code checksum does not match computed checksum"
    return chk_sum
end

"""
    checksum(code::Vector{String}, encoding_type::Symbol)

Return the checksum of the given `code` according to the chosen `encoding_type`.

The returned checksum is of type `Int`.

If the given code already contains the value of the checksum, this value is compared
against the computed checksum and a warning is showed in case they differ.

The only encoding types implemented so far are `:code128`, `:code128a`, `:code128b`, and `:code128c`, but the subtypes are not enforced.
"""
function checksum(code::Vector{String}, encoding_type::Symbol)
    encoding_type in (:code128, :code128a, :code128b, :code128c) ||
        throw(
            ArgumentError(
                "Decoding type `$(Meta.quot(mode))` not implemented"
            )
        )
    
    return _checksum_code128(code)
end