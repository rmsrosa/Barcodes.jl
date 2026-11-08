# GS1-128
#
# A GS1-128 is a Code128 with the function character FNC 1 right after the START symbol, and
# with the data organized in "element strings", each one being an Application Identifier (AI,
# 2 to 4 digits) followed by its data. An element string that does not have a predefined length
# is followed by FNC 1, unless it is the last one.
#
# Here, the message of a GS1-128 is the concatenation of the element strings, with the character
# GS (group separator, U+001D) for the separator FNC 1, as in the data transmitted by the barcode
# readers. The first FNC 1, right after START, is not part of the message. There is no table
# of all the AIs: just the ones that have a predefined length, to know where the separators go.

# Predefined lengths of the element strings (the AI and its data together), according to
# the first two digits of the AI, as in the GS1 General Specifications, Figure 5.10.1-2 (or
# Figure 7.8.5-2, in the newest releases)
const _GS1_PREDEFINED_LENGTH = Dict{String,Int}(
    "00" => 20, "01" => 16, "02" => 16, "03" => 16, "04" => 18,
    "11" => 8, "12" => 8, "13" => 8, "14" => 8, "15" => 8, "16" => 8, "17" => 8, "18" => 8,
    "19" => 8, "20" => 4,
    "31" => 10, "32" => 10, "33" => 10, "34" => 10, "35" => 10, "36" => 10,
    "41" => 16,
)

# number of digits of the AIs with predefined length: three in 41n, four in 31nn-36nn, and two in the others
_gs1_ai_length(prefix::AbstractString) =
    prefix == "41" ? 3 : prefix in ("31", "32", "33", "34", "35", "36") ? 4 : 2

"""
    gs1_element_string(hri::AbstractString)

Return the concatenation of the element strings in the `hri`, a string in the human readable
form of the GS1 Application Identifiers, with the AIs between parentheses, like
`"(01)09501101530003(10)ABC123"`, with the separator character GS (`'\\x1d'`) after
each element string that does not have a predefined length, except for the last one.

This is the message to be encoded with the `:gs1128` encoding type, and it is also what
is returned when decoding a GS1-128.

There is no table of the Application Identifiers. The only ones that are known are the ones that
have a predefined length (00, 01, 02, 03, 04, 11-20, 31-36, and 41), which should have the
right number of digits, and do not need a separator. All the others are assumed to be of
variable length and are followed by a separator, if they are not the last ones.
The data cannot have parentheses.

It throws an `ArgumentError` if the `hri` is not of that form.

# Examples

```jldoctest
julia> Barcodes.gs1_element_string("(01)09501101530003(17)140704")
"010950110153000317140704"

julia> Barcodes.gs1_element_string("(10)ABC123(21)XYZ")
"10ABC123\\x1d21XYZ"
```
"""
function gs1_element_string(hri::AbstractString)
    elements = collect(eachmatch(r"\(([0-9]{2,4})\)([^()]+)", hri))
    (!isempty(elements) && join(m.match for m in elements) == hri) || throw(
        ArgumentError(
            "`hri` should be a sequence of Application Identifiers between parentheses, each " *
            "one followed by its data, as in \"(01)09501101530003(10)ABC123\""
        )
    )
    io = IOBuffer()
    for (j, m) in enumerate(elements)
        ai, data = m.captures
        print(io, ai, data)
        total = get(_GS1_PREDEFINED_LENGTH, ai[1:2], nothing)
        if total === nothing
            j < length(elements) && print(io, _GS)
        elseif length(ai) != _gs1_ai_length(ai[1:2]) ||
                length(ai) + length(data) != total || !all(isdigit, data)
            throw(
                ArgumentError(
                    "AI ($ai) should have $(_gs1_ai_length(ai[1:2])) digits and be followed " *
                    "by exactly $(total - _gs1_ai_length(ai[1:2])) digits, but got \"($ai)$data\""
                )
            )
        end
    end
    return String(take!(io))
end

# Values of a GS1-128. The `msg` is either the concatenation of the element strings, with
# GS for the separators, or the human readable form, with the AIs between parentheses.
function _encode_values_gs1(msg::AbstractString)
    element_string = startswith(msg, '(') ? gs1_element_string(msg) : String(msg)
    isempty(element_string) && throw(ArgumentError("msg cannot be empty"))
    isdigit(first(element_string)) || throw(
        ArgumentError("A GS1-128 message should start with an Application Identifier (digits)")
    )
    all(c -> ' ' ≤ c ≤ '~' || c == _GS, element_string) || throw(
        ArgumentError(
            "A GS1-128 message can only have the ASCII characters from space to `~`, " *
            "and the separator GS (U+001D)"
        )
    )
    (first(element_string) != _GS && last(element_string) != _GS &&
        !occursin(_GS * _GS, element_string)) || throw(
        ArgumentError("The separator GS cannot be at the beginning, nor at the end, nor repeated")
    )
    chars = Int[c == _GS ? _FNC1 : Int(c) for c in element_string]
    return _encode_values_auto(pushfirst!(chars, _FNC1))
end
