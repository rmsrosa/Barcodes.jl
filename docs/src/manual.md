# Manual

```@meta
DocTestSetup = :(using Barcodes)
```

A Code 128 barcode is a sequence of *symbols*: a `START` symbol, the data symbols, a `CHECKSUM`, and a `STOP`. Each symbol is drawn as three bars and three spaces, in a total width of 11 modules. This package works with the sequence of symbols in two ways: as a vector of *names* such as `"START C"` or `"CODE B"`, which is easy to read, and as a vector of *values* (from 0 to 106), which is what enters the checksum and is what the [`Barcodes.Code128`](@ref) type stores.

## From a message to a barcode

[`Barcodes.encode`](@ref) gives the names of the symbols of the barcode of a message, and [`Barcodes.barcode_pattern`](@ref) gives the pattern of bars (`1`) and spaces (`0`), with the quiet zones on both sides:

```jldoctest manual
julia> zip_code = replace("12.345-678", r"\s|\.|\-" => "")
"12345678"

julia> code = Barcodes.encode(zip_code, :code128)
7-element Vector{String}:
 "START C"
 "12"
 "34"
 "56"
 "78"
 "CHECKSUM 47"
 "STOP"

julia> pattern = Barcodes.barcode_pattern(zip_code, :code128)
"00000000000110100111001011001110010001011000111000101101100001010010001110110110001110101100000000000"

julia> Barcodes.barcode_pattern(code, :code128) == pattern
true
```

The pattern can be turned into an image with [`Barcodes.barcode_img`](@ref), which can then be saved with [FileIO](https://github.com/JuliaIO/FileIO.jl) in any format that it supports, or resized with [JuliaImages](https://juliaimages.org/stable/):

```@example manual
using Barcodes, Images
pattern = Barcodes.barcode_pattern("12345678", :code128)
img = Barcodes.barcode_img(pattern)
```

```julia
julia> using FileIO

julia> FileIO.save("zipcode.png", img)
```

## Code sets

Code 128 has three code sets, A, B, and C. The set C encodes two digits per symbol; the set B has the printable ASCII characters (from space to `~` and DEL); and the set A has the upper case letters, the digits, the punctuation, and the control characters (from NUL to US). The symbols `CODE A`, `CODE B`, and `CODE C` switch from one set to another, and `SHIFT` takes a single character from the other set between A and B.

The encoding type `:code128` chooses the sets, and where to switch them, so that the barcode has the minimal number of symbols. If there is more than one way of doing that, it follows the conventions of the GS1 General Specifications.

```jldoctest manual
julia> msg = "\x02abc1234\x03";

julia> Barcodes.encode(msg, :code128)
13-element Vector{String}:
 "START A"
 "STX"
 "CODE B"
 "a"
 "b"
 "c"
 "CODE C"
 "12"
 "34"
 "CODE A"
 "ETX"
 "CHECKSUM 87"
 "STOP"
```

To force one of the sets, use `:code128a`, `:code128b`, or `:code128c`. An `ArgumentError` is thrown if the message cannot be encoded in the chosen set:

```jldoctest manual
julia> Barcodes.encode("ABC", :code128a)
6-element Vector{String}:
 "START A"
 "A"
 "B"
 "C"
 "CHECKSUM 0"
 "STOP"

julia> Barcodes.encode("abc", :code128a)
ERROR: ArgumentError: `msg` contains lowercase letters or DEL and cannot be encoded in subtype Code128A
[...]
```

## Extended characters

The message can have any character of ISO/IEC 8859-1 (Latin-1), that is, with code points up to `U+00FF`. The characters above `U+007F` are encoded with the directive `FNC 4`: one `FNC 4` before a character adds 128 to its code, and two `FNC 4` in a row switch an extended mode on, until two more of them switch it off. The encoder uses whichever gives the shortest barcode:

```jldoctest manual
julia> Barcodes.encode("Héllo", :code128)
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

julia> Barcodes.encode("ÿÿÿÿ", :code128)
9-element Vector{String}:
 "START B"
 "FNC 4"
 "FNC 4"
 "DEL"
 "DEL"
 "DEL"
 "DEL"
 "CHECKSUM 54"
 "STOP"
```

Not every barcode reader supports `FNC 4`. Some of them simply ignore it, and read `"Héllo"` as `"Hillo"`. Characters outside of Latin-1 cannot be encoded.

## GS1-128

A [GS1-128](https://www.gs1.org/standards/barcodes/application-identifiers) is a Code 128 whose data is organized in *element strings*, each one being an Application Identifier (AI, with 2 to 4 digits) followed by its data, like the GTIN `(01)09501101530003`. It is marked by the function character `FNC 1` right after the `START` symbol, and a data field of variable length is followed by another `FNC 1`, as a separator, unless it is the last one. Use the encoding type `:gs1128`, and the `FNC 1` symbols are added for you:

```jldoctest manual
julia> Barcodes.encode("(01)09501101530003(10)ABC123", :gs1128)
20-element Vector{String}:
 "START C"
 "FNC 1"
 "01"
 "09"
 "50"
 "11"
 "01"
 "53"
 "00"
 "03"
 "10"
 "CODE B"
 "A"
 "B"
 "C"
 "1"
 "2"
 "3"
 "CHECKSUM 66"
 "STOP"
```

The message can be written in the human readable form above, with the AIs between parentheses, or as the concatenation of the element strings, with the character GS (`'\x1d'`) as the separator, which is the form that a barcode reader sends to the computer, and is what is returned when decoding. The function [`Barcodes.gs1_element_string`](@ref) converts the first form into the second one:

```jldoctest manual
julia> es = Barcodes.gs1_element_string("(10)ABC123(21)XYZ(01)09501101530003")
"10ABC123\x1d21XYZ\x1d0109501101530003"

julia> gs1_code = Barcodes.encode(es, :gs1128);

julia> gs1_code[1:3]
3-element Vector{String}:
 "START B"
 "FNC 1"
 "1"

julia> Barcodes.decode(gs1_code, :gs1128) == es
true

julia> gs1 = Barcodes.Code128("(01)09501101530003", :gs1128);

julia> Barcodes.isgs1128(gs1)
true

julia> Barcodes.message(gs1)
"0109501101530003"
```

There is no table of all the Application Identifiers in this package. The only ones that are known are the ones with a predefined length (00, 01, 02, 03, 04, 11 to 20, 31 to 36, and 41), which are checked to have the right number of digits and are not followed by a separator. All the other ones are treated as having a variable length. Neither the check digits, nor the contents of the data, are validated, and the characters are restricted to the ASCII ones from space to `~`, since GS1-128 does not use `FNC 4`.

## From a barcode back to a message

The inverse of each step above is available:

```jldoctest manual
julia> code_back = Barcodes.barcode_depattern(pattern, :code128);

julia> code_back == code
true

julia> Barcodes.decode(code_back, :code128)
"12345678"

julia> Barcodes.barcode_decode(pattern, :code128)
"12345678"
```

The pattern is checked along the way: the symbols should be valid, with a `START` at the beginning and a `STOP` at the end, and the checksum should match. Otherwise, an `ArgumentError` is thrown.

## Widths of bars and spaces

Another representation of the barcode is with the widths of the bars and of the spaces between them. The pattern `11010011100` of `START C`, for instance, is represented by `211232`: the bars and spaces `11`, `0`, `1`, `00`, `111`, `00` have widths 2, 1, 1, 2, 3, 2. Each symbol has exactly three bars and three spaces. This representation is given by [`Barcodes.barcode_widths`](@ref), and the positions and the widths of the bars by [`Barcodes.barcode_positions`](@ref), which is useful to draw the barcode with a plotting package:

```jldoctest manual
julia> Barcodes.barcode_widths(pattern)
"211232112232131123331121241112133121233111"

julia> x, w = Barcodes.barcode_positions(pattern);

julia> length(x) == length(w)
true

julia> (x[1], w[1])
(12, 2)
```

```julia
julia> using Plots

julia> plot(
           [x'; x' + w'], ones(2, length(x)), color = :black, fill = true,
           xlims = (1, length(pattern)), ylims = (0, 1), border = :none, legend = nothing
       )
```

## The `Code128` type

A [`Barcodes.Code128`](@ref) stores a barcode as the vector of the values of its symbols. It can be created from a message, from the names of the symbols, or from the values themselves, and the other properties are obtained with functions, so the representation is always consistent:

```jldoctest manual
julia> b = Barcodes.Code128("Héllo");

julia> println(b)
Code128("Héllo")

julia> Barcodes.message(b)
"Héllo"

julia> Barcodes.subtype(b)
:code128b

julia> Barcodes.checksum(b)
73

julia> Barcodes.Code128(Barcodes.codenames(b)) == b
true

julia> Barcodes.Code128(b.values) == b
true
```

At the REPL, a `Code128` is displayed with a simple drawing of the bars, using Unicode blocks:

```julia
julia> Barcodes.Code128("12345678")
Code128: 12345678

     ▐▌▌▐█ ▌█ █▌▐ ▐▐▌ █▌ ▌█▐▌ ▐▐ ▌ █▌█▐▌ █▌▌█      
```

```@meta
DocTestSetup = nothing
```
