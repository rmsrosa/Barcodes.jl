# Encoding and decoding
#
# The encoders and decoders work with the values of the symbols (see code128_symbols.jl).
# The functions `encode`, `decode`, and `checksum` at the end of this file are the interface
# based on the names of the symbols.

const CODE128_TYPES = (:code128, :code128a, :code128b, :code128c)

function _check_encoding_type(encoding_type::Symbol)
    encoding_type in CODE128_TYPES || throw(
        ArgumentError(
            "Encoding type `$(repr(encoding_type))` not implemented"
        )
    )
    return nothing
end

# Characters of the message, as integers. Only the characters of ISO/IEC 8859-1 (Latin-1), that is,
# the code points up to U+00FF, can be encoded. The ones above 127 need the directive FNC 4.
function _message_chars(msg::AbstractString)
    isempty(msg) && throw(ArgumentError("msg cannot be empty"))
    all(c -> c ≤ '\u00ff', msg) || throw(
        ArgumentError(
            "`msg` must contain only Latin-1 characters (code points up to U+00FF)"
        )
    )
    return Int[Int(c) for c in msg]
end

# [START, body..., CHECKSUM, STOP]
function _frame(start::CodeSet, body::AbstractVector{<:Integer})
    values = UInt8[_start_value(start); body; 0; STOP_VALUE]
    values[end-1] = _checksum(values)
    return values
end

# Code128 encoding with subtype Code128A. The characters above 127 use FNC 4.
function _encode_values_a(chars::Vector{Int})
    all(c -> c & 0x7f ≤ 95, chars) || throw(
        ArgumentError(
            "`msg` contains lowercase letters or DEL and cannot be encoded in subtype Code128A"
        )
    )
    return _encode_values_auto(chars, (SetA,))
end

# Code128 encoding with subtype Code128B. The characters above 127 use FNC 4.
function _encode_values_b(chars::Vector{Int})
    all(c -> c & 0x7f ≥ 32, chars) || throw(
        ArgumentError(
            "`msg` contains control characters and cannot be encoded in subtype Code128B"
        )
    )
    return _encode_values_auto(chars, (SetB,))
end

# Code128 encoding with subtype Code128C
function _encode_values_c(chars::Vector{Int})
    all(c -> 48 ≤ c ≤ 57, chars) || throw(
        ArgumentError(
            "The given `msg` contains characters which are not digits and cannot " *
            "be encoded in subtype Code128C"
        )
    )
    iseven(length(chars)) || throw(
        ArgumentError(
            "The given `msg` contains an odd number of digits and cannot be fully " *
            "encoded in subtype Code128C"
        )
    )
    return _frame(SetC, [10 * (chars[j] - 48) + chars[j+1] - 48 for j in 1:2:length(chars)])
end

# Can the base character `b` (that is, `c & 0x7f`, with 0 ≤ b ≤ 127) be a data symbol in the code
# set number `k` (1 for A, 2 for B)?
_in_set(b::Integer, k::Integer) = k == 1 ? b ≤ 95 : b ≥ 32

_isdigit(c::Integer) = 48 ≤ c ≤ 57

# Optimized Code128 (actually GS1-128) mixed-subtype encoding.
#
# The encoding with the minimal number of symbols is found with dynamic programming, over
# the position in the message and the current state, which is the code set (1, 2, 3 for A, B, C)
# and whether the extended mode (two consecutive FNC 4) is on (1 for off, 2 for on). The costs
# are computed backwards, and the encoding is then built forward, choosing among the optimal
# options with the following preferences, which mimic the rules in "GS1 General Specifications,
# Version 13, Issue 1, Jan-2013, Section 5.4.7.7. Use of Start, Code Set, and Shift symbols
# to Minimize Symbol Length (Informative), pages 268 to 269.":
#
# * START C if the message begins with four or more digits, and otherwise the start code set
#   that has the first character (START B over START A), in case of a tie;
# * remain in the current code set as long as possible, except that a run of an even number
#   of four or more digits goes in code set C (and, for an odd number of digits, the first
#   digit is left to the current code set, except at the beginning of the message);
# * for a character that is not in the current code set, use SHIFT if the next character
#   returns to the current code set, and otherwise switch the code set (CODE A/B/C).
#
# Characters above 127 are the base character (c - 128) with the extended mode: either a single
# FNC 4 before the character (before the SHIFT, if there is one), or two FNC 4 to switch the
# extended mode on (or off), which stays on across changes of the code set. The extended mode is
# only switched when this is strictly better than using single FNC 4.
#
# The code sets in `allowed` are the only ones that can be used. Both ways of encoding the
# same message have the same length when there is a tie.
function _encode_values_auto(chars::Vector{Int}, allowed = (SetA, SetB, SetC))
    n = length(chars)
    INF = typemax(Int) ÷ 4
    ok = [CodeSet(k) in allowed for k in 1:3]

    # State (k, e) is the node 3(e - 1) + k. The shortest cost `dist` of changing the state, at the
    # same position of the message, by CODE symbols (cost 1) and by switching the extended mode
    # with two FNC 4 (cost 2, only in the code sets A and B).
    node(k, e) = 3 * (e - 1) + k
    dist = fill(INF, 6, 6)
    for e in 1:2, k in 1:3
        dist[node(k, e), node(k, e)] = 0
        ok[k] || continue
        for j in 1:3
            j != k && ok[j] && (dist[node(k, e), node(j, e)] = 1)
        end
        k ≤ 2 && (dist[node(k, e), node(k, 3 - e)] = 2)
    end
    for m in 1:6, a in 1:6, b in 1:6
        dist[a, b] = min(dist[a, b], dist[a, m] + dist[m, b])
    end

    # h[i, k, e]: minimal number of symbols to encode chars[i:n] starting in the state (k, e),
    #             without any change of state before the character i (but with a SHIFT and/or a
    #             single FNC 4 for the character i, if needed)
    # f[i, k, e]: the same, but allowing for changes of state before the character i
    # f0[i, k, e]: the same, but only with CODE symbols before the character i
    h = fill(INF, n, 3, 2)
    f = zeros(Int, n + 1, 3, 2)
    f0 = zeros(Int, n + 1, 3, 2)

    # run[i]: number of consecutive digits starting at the character i
    run = zeros(Int, n + 1)

    for i in n:-1:1
        c = chars[i]
        x = c ≥ 128 ? 2 : 1 # extended mode of the character
        b = c & 0x7f # base character
        run[i] = _isdigit(c) ? run[i+1] + 1 : 0
        for e in 1:2
            fnc4 = x == e ? 0 : 1 # a single FNC 4 is needed
            for k in 1:2
                ok[k] || continue
                if _in_set(b, k)
                    h[i, k, e] = fnc4 + 1 + f[i+1, k, e]
                elseif ok[3-k] && _in_set(b, 3 - k)
                    h[i, k, e] = fnc4 + 2 + f[i+1, k, e] # SHIFT and the character
                end
            end
            if ok[3] && i < n && _isdigit(c) && _isdigit(chars[i+1])
                h[i, 3, e] = 1 + f[i+2, 3, e] # a pair of digits
            end
        end
        for e in 1:2, k in 1:3
            f0[i, k, e] = h[i, k, e]
            for j in 1:3
                j != k && (f0[i, k, e] = min(f0[i, k, e], 1 + h[i, j, e]))
            end
            f[i, k, e] = minimum(
                dist[node(k, e), node(j, d)] + h[i, j, d] for j in 1:3 for d in 1:2
            )
        end
    end

    # Start code set, with the extended mode off
    start_cost = [ok[k] ? 1 + f[1, k, 1] : INF for k in 1:3]
    best_start = minimum(start_cost)
    k = if run[1] ≥ 4 && start_cost[3] == best_start
        3
    else
        # among the best ones, prefer a code set that has the first character
        candidates = [k for k in (2, 1, 3) if start_cost[k] == best_start]
        ind = findfirst(k -> k ≤ 2 && _in_set(chars[1] & 0x7f, k), candidates)
        candidates[something(ind, 1)]
    end
    start = CodeSet(k)
    e = 1

    body = UInt8[]
    i = 1
    while i ≤ n
        c = chars[i]
        x = c ≥ 128 ? 2 : 1
        b = c & 0x7f

        if f0[i, k, e] > f[i, k, e]
            # the extended mode needs to be switched, on or off, before the character i
            # (possibly after a change of code set): take the first step of a shortest path
            j = findfirst(
                j -> j != k && ok[j] && 1 + f[i, j, e] == f[i, k, e], (2, 1, 3)
            )
            if j !== nothing
                latch_to = (2, 1, 3)[j]
                push!(body, _latch_value(CodeSet(latch_to)))
                k = latch_to
            else
                # two FNC 4 (we are in the code set A or B, because the sum of the cost of
                # the other options is larger)
                push!(body, _fnc4_value(CodeSet(k)), _fnc4_value(CodeSet(k)))
                e = 3 - e
            end
            continue
        end

        is_shift = k ≤ 2 && !_in_set(b, k)

        # the best way of changing the code set before the character i, preferring, in case
        # of a tie, a code set that has the character i (rather than needing a SHIFT)
        latch_cost = minimum(1 + h[i, j, e] for j in 1:3 if j != k)
        latch_options = [j for j in (2, 1, 3) if j != k && 1 + h[i, j, e] == latch_cost]
        ind = findfirst(
            j -> j == 3 ? (i < n && _isdigit(c) && _isdigit(chars[i+1])) : _in_set(b, j),
            latch_options
        )
        latch_to = latch_options[something(ind, 1)]

        # a run of an even number of four or more digits is better in code set C, if it
        # costs no more
        prefer_c = ok[3] && k ≤ 2 && run[i] ≥ 4 && iseven(run[i]) && 1 + h[i, 3, e] == latch_cost
        prefer_c && (latch_to = 3)

        use_latch = if h[i, k, e] > f0[i, k, e]
            true # the CODE symbol is strictly better
        elseif prefer_c && latch_cost == f0[i, k, e]
            true # a tie between the digits in the current code set and CODE C
        elseif is_shift && latch_cost == f0[i, k, e]
            # a tie between SHIFT and CODE: use SHIFT if the next character is back in
            # the current code set
            !(i < n && _in_set(chars[i+1] & 0x7f, k))
        else
            false
        end

        if use_latch
            push!(body, _latch_value(CodeSet(latch_to)))
            k = latch_to
        elseif k == 3
            push!(body, 10 * (chars[i] - 48) + chars[i+1] - 48)
            i += 2
        else
            x == e || push!(body, _fnc4_value(CodeSet(k))) # a single FNC 4
            if is_shift
                push!(body, SHIFT_VALUE)
                push!(body, 3 - k == 1 ? _value_a(b) : _value_b(b))
            else
                push!(body, k == 1 ? _value_a(b) : _value_b(b))
            end
            i += 1
        end
    end

    return _frame(start, body)
end

"""
    _encode_values(msg::AbstractString, encoding_type::Symbol)

Return the values of the symbols of the Code128 for the given `msg`, including the START,
CHECKSUM, and STOP symbols.
"""
function _encode_values(msg::AbstractString, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    chars = _message_chars(msg)
    if encoding_type == :code128
        return _encode_values_auto(chars)
    elseif encoding_type == :code128a
        return _encode_values_a(chars)
    elseif encoding_type == :code128b
        return _encode_values_b(chars)
    else
        return _encode_values_c(chars)
    end
end

"""
    encode(msg::AbstractString, encoding_type::Symbol)

Return the encoded sequence from the given `msg`, following the specifications determined
by the `encoding_type`, as a vector with the names of the symbols.

Currently, only Code128 specification is available.

If `encoding_type` is either `:code128a`, `:code128b`, or `:code128c`, it returns the
encoding following the corresponding subtype. If `encoding_type` is `:code128`, it will
return an optimized encoding, possibly mixing different subtypes, with the minimal number
of symbols.

The `msg` needs to be a non-empty string of Latin-1 characters (ISO/IEC 8859-1, that is, code
points up to `'\u00ff'`) to be encoded, otherwise the method throws an `ArgumentError`. The
characters above `'\x7f'` are encoded with the directive FNC 4, either one for each character,
or two to switch an extended mode on, whatever uses fewer symbols. In the subtypes
`:code128a` and `:code128b`, the characters should be those of the subtype, possibly with FNC 4.

# Examples

```jldoctest
julia> code = Barcodes.encode("000132", :code128c)
6-element Vector{String}:
 "START C"
 "00"
 "01"
 "32"
 "CHECKSUM 100"
 "STOP"

julia> code = Barcodes.encode("ABC", :code128a)
6-element Vector{String}:
 "START A"
 "A"
 "B"
 "C"
 "CHECKSUM 0"
 "STOP"

julia> code = Barcodes.encode("é", :code128)
5-element Vector{String}:
 "START B"
 "FNC 4"
 "i"
 "CHECKSUM 41"
 "STOP"
```
"""
function encode(msg::AbstractString, encoding_type::Symbol)
    return _names(_encode_values(msg, encoding_type))
end

"""
    decode(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)

Decode the given encoded sequence, a vector with the names of the symbols, following the
specifications determined by the `encoding_type`.

Currently, only Code128 specification is available.

# Examples

```jldoctest
julia> code = Barcodes.encode("\\x02ABC\\x03", :code128)
8-element Vector{String}:
 "START A"
 "STX"
 "A"
 "B"
 "C"
 "ETX"
 "CHECKSUM 91"
 "STOP"

julia> Barcodes.decode(code, :code128)
"\\x02ABC\\x03"
```
"""
function decode(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    return _decode_values(_parse_names(code))
end

"""
    checksum(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)

Return the checksum of the given `code`, a vector with the names of the symbols, according
to the chosen `encoding_type`.

The returned checksum is of type `Int`.

If the given code already contains the value of the checksum, as in `"CHECKSUM 34"`, this
value is compared against the computed checksum and a warning is showed in case they differ.

The only encoding types implemented so far are `:code128`, `:code128a`, `:code128b`, and
`:code128c`, but the subtypes are not enforced.

# Examples

```jldoctest
julia> Barcodes.checksum(["START C", "00", "01", "32", "CHECKSUM", "STOP"], :code128)
100
```
"""
function checksum(code::AbstractVector{<:AbstractString}, encoding_type::Symbol)
    _check_encoding_type(encoding_type)
    return _checksum(_parse_names(code))
end
