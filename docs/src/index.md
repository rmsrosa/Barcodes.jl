# Barcodes.jl

A pure [Julia](https://julialang.org) generator of [Code 128](https://en.wikipedia.org/wiki/Code_128) barcodes, with no dependencies other than a type for the pixels of the images.

!!! note
    This package is under development and is not yet registered. Install it with
    ```julia
    julia> using Pkg; Pkg.add(url = "https://github.com/rmsrosa/barcodes.jl")
    ```

With it, you can

* encode a message as the sequence of the symbols of a Code 128 barcode, choosing automatically the code sets (A, B, C) that give the shortest barcode, including the extended (Latin-1) characters, with the directive FNC 4;
* turn this sequence into the pattern of bars and spaces, and into an image;
* go the other way, from the pattern or from the sequence of symbols back to the message;
* handle all that with a single type, [`Barcodes.Code128`](@ref).

```jldoctest
julia> using Barcodes

julia> Barcodes.barcode_pattern("12345678", :code128)
"00000000000110100111001011001110010001011000111000101101100001010010001110110110001110101100000000000"
```

See the [Manual](manual.md) for the details and the [API](api.md) for the list of functions.

## Related packages

[`ZXingCPP.jl`](https://github.com/rakeshksr/ZXingCPP.jl) is a wrapper of the C++ library [`zxing-cpp`](https://github.com/zxing-cpp/zxing-cpp) that reads and writes many barcode formats, and is a better choice if you need more than Code 128 (or need to *read* barcodes from images). For QR codes, there is also [`QRCoders.jl`](https://juliaimages.org/QRCoders.jl/dev/).
