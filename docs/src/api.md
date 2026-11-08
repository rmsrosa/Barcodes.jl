# API

None of the names is exported, so they are all used with the prefix `Barcodes.`.

## Encoding and decoding

```@docs
Barcodes.encode
Barcodes.decode
Barcodes.checksum(::AbstractVector{<:AbstractString}, ::Symbol)
```

## Patterns

```@docs
Barcodes.barcode_pattern(::AbstractVector{<:AbstractString}, ::Symbol)
Barcodes.barcode_pattern(::AbstractString, ::Symbol)
Barcodes.barcode_depattern
Barcodes.barcode_decode
Barcodes.barcode_widths
Barcodes.barcode_positions
Barcodes.utf8block_pattern
```

## Images

```@docs
Barcodes.barcode_img
```

## The `Code128` type

```@docs
Barcodes.Barcode
Barcodes.Code128
Barcodes.message
Barcodes.codenames
Barcodes.subtype
Barcodes.checksum(::Barcodes.Code128)
Barcodes.barcode_pattern(::Barcodes.Code128)
```

## Internals

These are implementation details, documented for the sake of the developers. They are not part of the stable API and may change without notice.

```@docs
Barcodes.CodeSet
Barcodes.CODE128
Barcodes.CODE128_PATTERNS
Barcodes.CODE128_NAMES
Barcodes.CODE128_NAME2VALUE
Barcodes.CODE128_PATTERN2VALUE
Barcodes._encode_values(::AbstractString, ::Symbol)
```
