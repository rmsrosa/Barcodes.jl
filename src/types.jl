"""
    abstract type Barcode end

Abstract supertype for all the barcodes.
"""
abstract type Barcode end

"""
    struct Code128 <: Barcode

Composite type for Code128 barcode.

Fields:
    subtype::Symbol
        Either :code128A, :code128B, :code128C, or just :code128 for the mixed subtypes.
    message::String
        String with the message encoded
    code::Vector{String}
        Encoded message.
"""
struct Code128 <: Barcode
    subtype::Symbol
    message::String
    code::Vector{String}
    
    function Code128(msg::String, encoding_type::Symbol=:code128)
        code = encode(msg, encoding_type)

        a = any(∈(("START A", "CODE A", "SHIFT A")), code)
        b = any(∈(("START B", "CODE B", "SHIFT B")), code)
        c = any(∈(("START C", "CODE C", "SHIFT C")), code)
        subtype = a + b + c > 1 ? :code128 :
            a === true ? :code128a :
            b === true ? :code128b :
            c === true ? :code128c :
            nothing
        new(subtype, msg, code)
    end

    function Code128(code::Vector{String})
        code = copy(code) # not to modify the input code
        chk_sum = checksum(code, :code128)
        m = match(r"CHECKSUM (\d+)", code[end-1])
        m === nothing || parse(Int, m.captures[1]) == chk_sum || @warn "Code checksum does not match computed checksum; using computed checksum."
        code[end-1] == "CHECKSUM" && (code[end-1] = "$(code[end-1]) $chk_sum")

        msg = decode(code, :code128)

        subtype = any(c -> (startswith(c, "SHIFT") | startswith(c, "CODE")), code) ? :code128 :
            code[1] == "START A" ? :code128a :
            code[1] == "START B" ? :code128b :
            code[1] == "START C" ? :code128c :
            throw(ArgumentError("Not a valid Code128"))

        new(subtype, msg, code)
    end
end

# Short one-line form. Used by `print`, `repr`, string interpolation, and when
# the barcode is an element of an array or other container.
function Base.show(io::IO, barcode::Code128)
    print(io, "Code128(", repr(barcode.message), ")")
end

# Multi-line form. The REPL (and `display`) call this one for a top-level value.
function Base.show(io::IO, ::MIME"text/plain", barcode::Code128)
    pattern = barcode_pattern(barcode.code, barcode.subtype)
    s = utf8block_pattern(pattern)
    if get(io, :detailed, false)
        println(io, "Barcode type: ", uppercasefirst(string(barcode.subtype)))
        print(io, "Message: ")
        printstyled(io, barcode.message, reverse = true)
        println(io)
        println(io, "Code:")
        for c in barcode.code
            println(io, '\t', c)
        end
        println(io, "Barcode pattern:")
        print(io, s)
    else
        print(io, "Code128: ")
        printstyled(io, barcode.message, reverse = true)
        print(io, "\n\n", s)
    end
end