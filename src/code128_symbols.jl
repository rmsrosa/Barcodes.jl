# Code128 symbols
#
# A Code128 barcode is represented internally by the vector of the *values* of its symbols,
# `[START, data..., CHECKSUM, STOP]`, each value being an integer between 0 and 106.
# The meaning of a data symbol depends on the code set (A, B, or C) in which it is read.
# The names of the symbols, such as `"START C"` or `"SHIFT B"`, are only used for display and
# for the (older) interface based on vectors of strings.

"""
    @enum CodeSet SetA SetB SetC

The three code sets of Code128.
"""
@enum CodeSet::UInt8 SetA = 1 SetB = 2 SetC = 3

const STOP_VALUE = 106
const SHIFT_VALUE = 98

# Value of FNC 4 in the code sets A (101) and B (100); there is no FNC 4 in the code set C.
# One FNC 4 adds 128 to the code of the next data character (extended ASCII, ISO/IEC 8859-1),
# and two consecutive FNC 4 switch the extended mode on, or off, for all the following characters.
_fnc4_value(set::CodeSet) = set == SetA ? 101 : 100

# Value of the START symbol of the given code set: 103, 104, 105
_start_value(set::CodeSet) = 102 + Int(set)

# Value of the symbol that switches (latches) to the given code set, from any other code set:
# CODE C is 99 (in sets A and B), CODE B is 100 (in sets A and C), CODE A is 101 (in B and C).
_latch_value(set::CodeSet) = set == SetA ? 101 : set == SetB ? 100 : 99

function _start_set(value::Integer)
    103 ≤ value ≤ 105 ||
        throw(
            ArgumentError(
                "First element of `code` should be either `START A`, `START B` or `START C`"
            )
        )
    return CodeSet(value - 102)
end

# Characters of the symbols with values 0 to 95 in the sets A and B
_char_a(v::Integer) = v < 64 ? Char(v + 32) : Char(v - 64)
_char_b(v::Integer) = Char(v + 32)

# Values for characters
_value_a(c::Integer) = c ≥ 32 ? c - 32 : c + 64 # for 0 ≤ c ≤ 95
_value_b(c::Integer) = c - 32 # for 32 ≤ c ≤ 127

# Read the symbol with value `v` in the code set `active`, when `set` is the code set currently
# latched (`active` differs from `set` right after a SHIFT). Return the new `(set, active)`.
function _step(set::CodeSet, active::CodeSet, v::Integer)
    if active != SetC && v == SHIFT_VALUE
        return set, (active == SetA ? SetB : SetA)
    elseif active != SetC && v == 99 # CODE C
        return SetC, SetC
    elseif active != SetB && v == 100 # CODE B (in set B this is FNC 4)
        return SetB, SetB
    elseif active != SetA && v == 101 # CODE A (in set A this is FNC 4)
        return SetA, SetA
    else
        return set, set
    end
end

# Check that `values` has the form `[START, data..., CHECKSUM, STOP]` with values in the
# proper range. The checksum is checked separately.
function _check_framing(values::AbstractVector{<:Integer})
    length(values) ≥ 4 ||
        throw(ArgumentError("A Code128 needs at least START, one data symbol, CHECKSUM, and STOP"))
    all(v -> 0 ≤ v ≤ STOP_VALUE, values) ||
        throw(ArgumentError("The values of Code128 symbols should be between 0 and 106"))
    _start_set(values[1])
    values[end] == STOP_VALUE ||
        throw(ArgumentError("Last element of `code` should be `STOP`"))
    any(v -> v == STOP_VALUE, @view values[1:end-1]) &&
        throw(ArgumentError("""There should be only one "STOP" in the encoding sequence"""))
    any(v -> 103 ≤ v ≤ 105, @view values[2:end]) &&
        throw(ArgumentError("There should be only one r\"START [ABC]\" in the encoding sequence"))
    return nothing
end

# Checksum of `values`, which is `[START, data..., CHECKSUM, STOP]`. The value in the position
# of the checksum is ignored.
function _checksum(values::AbstractVector{<:Integer})
    chk_sum = Int(values[1])
    for p in 2:length(values)-2
        chk_sum += (p - 1) * Int(values[p])
    end
    return chk_sum % 103
end

# Same as above, but also checking that the stored checksum is correct
function _check_values(values::AbstractVector{<:Integer})
    _check_framing(values)
    values[end-1] == _checksum(values) ||
        throw(ArgumentError("Checksum does not match computed checksum"))
    return nothing
end

# Names of the symbols, as a vector of strings
function _names(values::AbstractVector{<:Integer})
    _check_framing(values)
    n = length(values)
    names = Vector{String}(undef, n)
    set = active = _start_set(values[1])
    names[1] = CODE128_NAMES[1][values[1]+1]
    for i in 2:n
        v = Int(values[i])
        if i == n - 1
            names[i] = "CHECKSUM $v"
        else
            names[i] = CODE128_NAMES[Int(active)][v+1]
            set, active = _step(set, active, v)
        end
    end
    return names
end

# Values of the symbols, from a vector of names. The value of the checksum is always the
# computed one, and the checksum symbol may be either "CHECKSUM", or "CHECKSUM n", which is then
# compared with the computed value (with a warning in case of a mismatch).
function _parse_names(code::AbstractVector{<:AbstractString})
    isempty(code) && throw(ArgumentError("`code` cannot be empty"))

    m = match(r"^START ([ABC])$", first(code))
    m !== nothing || throw(
        ArgumentError(
            "First element of `code` should be either `START A`, `START B` or `START C`"
        )
    )

    last(code) == "STOP" ||
        throw(ArgumentError("Last element of `code` should be `STOP`"))

    count(==("STOP"), code) == 1 ||
        throw(ArgumentError("""There should be only one "STOP" in the encoding sequence"""))

    count(c -> occursin(r"^START [ABC]$", c), code) == 1 ||
        throw(
            ArgumentError(
                "There should be only one r\"START [ABC]\" in the encoding sequence"
            )
        )

    n = length(code)
    n ≥ 4 || throw(ArgumentError("A Code128 needs at least START, one data symbol, CHECKSUM, and STOP"))

    set = active = CodeSet(Int(m.captures[1][1]) - Int('A') + 1)
    values = Vector{UInt8}(undef, n)
    values[1] = _start_value(set)
    values[n] = STOP_VALUE
    given_checksum = nothing

    # the checksum directive is either "CHECKSUM" or "CHECKSUM n"
    mc = match(r"^CHECKSUM(?: (\d+))?$", code[n-1])
    mc !== nothing || throw(
        ArgumentError("The element before the last one in `code` should be `CHECKSUM`")
    )
    mc.captures[1] === nothing || (given_checksum = parse(Int, mc.captures[1]))

    for i in 2:n-2
        c = code[i]
        v = get(CODE128_NAME2VALUE[Int(active)], c, nothing)
        v === nothing && throw(
            ArgumentError(
                "$c is not part of subtype Code128$(string(active)[end]) of Code128"
            )
        )
        values[i] = v
        set, active = _step(set, active, v)
    end

    chk_sum = _checksum(values)
    values[n-1] = chk_sum
    given_checksum === nothing || given_checksum == chk_sum ||
        @warn "Code checksum does not match computed checksum; using computed checksum."

    return values
end

# Decode the values into the message
function _decode_values(values::AbstractVector{<:Integer})
    _check_framing(values)
    io = IOBuffer()
    set = active = _start_set(values[1])
    extended = false # extended mode latched by two consecutive FNC 4
    next_extended = false # a single FNC 4 waiting for the next data character
    for i in 2:length(values)-2
        v = Int(values[i])
        if active == SetC
            v ≤ 99 && print(io, lpad(v, 2, '0'))
        elseif v ≤ 95
            c = Int(active == SetA ? _char_a(v) : _char_b(v))
            extended ⊻ next_extended && (c += 128)
            next_extended = false
            print(io, Char(c))
        elseif v == _fnc4_value(active)
            # a second FNC 4 in a row latches (or unlatches) the extended mode
            if next_extended
                extended = !extended
                next_extended = false
            else
                next_extended = true
            end
        end
        # the other symbols (SHIFT, CODE A/B/C, FNC 1-3) do not have a character
        set, active = _step(set, active, v)
    end
    return String(take!(io))
end
