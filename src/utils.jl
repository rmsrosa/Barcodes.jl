"""
    barcode_img(pattern; img_height = 50)

Return an image of type `Matrix{Gray{Bool}}` where the number of rows is specified
by `img_height` and where the rows are filled with the `pattern`. Displaying
the image reveals the barcode.

The image has one extra row of white pixels at the top and at the bottom, and each character
of the `pattern` becomes one column: `'1'` is a black pixel (a bar) and `'0'` is a white pixel
(a space). You can save the generated image via `FileIO.save`, using any format accepted
by `FileIO`, and resize it with [JuliaImages](https://juliaimages.org/stable/).

# Examples

```jldoctest
julia> img = Barcodes.barcode_img("0110"; img_height = 3);

julia> size(img)
(5, 4)

julia> Bool.(img) # white is `true` and black is `false`
5×4 BitMatrix:
 1  1  1  1
 1  0  0  1
 1  0  0  1
 1  0  0  1
 1  1  1  1
```
"""
function barcode_img(pattern::AbstractString; img_height = 50)
    img =
        Gray.(
            [
                fill(true, 1, length(pattern))
                repeat(reshape([c == ('0') for c in pattern], 1, :), img_height, 1)
                fill(true, 1, length(pattern))
            ],
        )
    return img
end

"""
    barcode_positions(pattern)

Return the positions and widths of the bars of the `pattern`, as two vectors of integers `x`
and `w`. The `i`-th bar starts at the index `x[i]` of the `pattern` and has width `w[i]`.

This is useful for drawing the barcode with a plotting package, as in the manual.

# Examples

```jldoctest
julia> x, w = Barcodes.barcode_positions("0110100111000")
([2, 5, 8], [2, 1, 3])
```
"""
function barcode_positions(pattern::AbstractString)
    x = Int[]
    w = Int[]

    ind = 1
    
    while ind ≤ length(pattern)
        if pattern[ind] == '1'
            push!(x, ind)
            next_ind = something(findnext(==('0'), pattern, ind), length(pattern) + 1)
            push!(w, next_ind - ind)
            ind = next_ind
        else
            ind += 1
        end
    end
    return x, w
end

"""
    barcode_widths(pattern)

Return the representation of the `pattern` by the widths of its bars and spaces, as a string
of digits, ignoring the quiet zones and the final double bar.

Each symbol has three bars and three spaces, so each symbol gives six digits. For example,
the pattern `11010011100` of `START C` is represented by `211232`: a bar of width 2, a space of
width 1, a bar of width 1, a space of width 2, a bar of width 3, and a space of width 2.

The `pattern` should be a complete barcode pattern, as returned by [`barcode_pattern`](@ref).

# Examples

```jldoctest
julia> pattern = Barcodes.barcode_pattern("12345678", :code128);

julia> Barcodes.barcode_widths(pattern)
"211232112232131123331121241112133121233111"
```
"""
function barcode_widths(pattern::AbstractString)
    io = IOBuffer()

    ind = findfirst(==('1'), pattern)
    while ind !== nothing
        c = pattern[ind]
        next_ind = findnext(!=(c), pattern, ind)
        next_ind !== nothing && print(io, next_ind - ind)
        ind = next_ind
    end
    w = String(take!(io))
    w = w[begin:end-1] # drop the ending `11`, which is a bar with width 2
    return w
end
