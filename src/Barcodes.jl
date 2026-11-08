module Barcodes

using Images: Gray

include("code128_charset.jl")
include("code128_symbols.jl")
include("encoding.jl")
include("gs1.jl")
include("pattern.jl")
include("utils.jl")
include("types.jl")

end
