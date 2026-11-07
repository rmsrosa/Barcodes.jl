using Barcodes
using Test
using FileIO

ENV["GKSwstype"] = "100" # it runs Plots without a display, but it is not needed for the tests, so it will be removed once Documentation is ready
using Plots # it is in runtests.jl just to generate the image for README
            # it will be removed from tests once Documentation is ready

# Tiny deterministic pseudo-random generator (a linear congruential generator),
# so that the randomized tests below are reproducible without depending on `Random`.
mutable struct TestLCG
    state::UInt32
end

function nextint!(r::TestLCG)
    r.state = r.state * 0x0019660d + 0x3c6ef35f
    return Int(r.state >> 16)
end

@testset "Encoding" begin
    @testset "Code128a" begin
        let code = Barcodes.encode("A", :code128a)
            @test code == [
                "START A"
                "A"
                "CHECKSUM 33"
                "STOP"
            ]
        end
        let code = Barcodes.encode("\x02A\x03", :code128a)
            @test code == [
                "START A"
                "STX"
                "A"
                "ETX"
                "CHECKSUM 24"
                "STOP"
            ]
        end
    end

    @testset "Code128b" begin
        let code = Barcodes.encode("A", :code128b)
            @test code == [
                "START B"
                "A"
                "CHECKSUM 34"
                "STOP"
            ]
        end
        let code = Barcodes.encode("aBc", :code128b)
            @test code == [
                "START B"
                "a"
                "B"
                "c"
                "CHECKSUM 26"
                "STOP"
            ]
        end
        let code = Barcodes.encode("a\x7fb", :code128b)
            @test "DEL" in code
        end
    end

    @testset "Code128c" begin
        let code = Barcodes.encode("00", :code128c)
            @test code == [
                "START C"
                "00"
                "CHECKSUM 2"
                "STOP"
            ]
        end
        let code = Barcodes.encode("012345", :code128c)
            @test code == [
                "START C"
                "01"
                "23"
                "45"
                "CHECKSUM 81"
                "STOP"
            ]
        end
    end

    @testset "Code128" begin
        let code = Barcodes.encode("CSE370", :code128)
            @test code == [
                "START B"
                "C"
                "S"
                "E"
                "3"
                "7"
                "0"
                "CHECKSUM 21"
                "STOP"
            ]
        end

        let code = Barcodes.encode("\x02Aa\tA0902a93892\x03000a\x04z", :code128)
            @test code == [
                "START A"
                "STX"
                "A"
                "SHIFT B"
                "a"
                "HT"
                "A"
                "CODE C"
                "09"
                "02"
                "CODE B"
                "a"
                "9"
                "CODE C"
                "38"
                "92"
                "CODE A"
                "ETX"
                "0"
                "0"
                "0"
                "SHIFT B"
                "a"
                "EOT"
                "CODE B"
                "z"
                "CHECKSUM 15"
                "STOP"
            ]
        end

        # a control character in the middle of lowercase letters is reached with SHIFT A
        let code = Barcodes.encode("ab\x01c", :code128)
            @test code[1] == "START B"
            @test "SHIFT A" in code
        end

        # a lowercase letter in the middle of control characters is reached with SHIFT B
        let code = Barcodes.encode("\x01\x02a\x03", :code128)
            @test code[1] == "START A"
            @test "SHIFT B" in code
        end
    end

    @testset "Encoding errors" begin
        # empty message
        for t in (:code128, :code128a, :code128b, :code128c)
            @test_throws ArgumentError Barcodes.encode("", t)
        end

        # non-ASCII message
        for t in (:code128, :code128a, :code128b, :code128c)
            @test_throws ArgumentError Barcodes.encode("é", t)
        end

        # characters not available in the chosen subtype
        @test_throws ArgumentError Barcodes.encode("abc", :code128a) # lowercase
        @test_throws ArgumentError Barcodes.encode("\x01", :code128b) # control character
        @test_throws ArgumentError Barcodes.encode("abc", :code128c) # not digits
        @test_throws ArgumentError Barcodes.encode("123", :code128c) # odd number of digits

        # unknown encoding type
        @test_throws ArgumentError Barcodes.encode("abc", :qrcode)
    end
end

@testset "Decoding" begin
    for msg in (
        "ABC",
        "abc",
        "0123",
        "\x02ABC\x03",
        "\x02ABcZ\x03",
        "\x02AB012345\x03",
        "A b!\t0012\nZ z@\t0013\nAz `\t9999\naA \x7f\t1357"
    )
        code = Barcodes.encode(msg, :code128)
        @test msg == Barcodes.decode(code, :code128)
    end

    @testset "subtypes" begin
        for msg in ("ABC", "\x02ABC\x03", "A B_", "\x00\x1f _")
            code = Barcodes.encode(msg, :code128a)
            @test msg == Barcodes.decode(code, :code128a)
        end
        for msg in ("abc", "aBc 123~", "a\x7fb", "~ ")
            code = Barcodes.encode(msg, :code128b)
            @test msg == Barcodes.decode(code, :code128b)
        end
        for msg in ("00", "0123", "0123456789")
            code = Barcodes.encode(msg, :code128c)
            @test msg == Barcodes.decode(code, :code128c)
        end
    end

    @testset "SHIFT" begin
        for msg in ("ab\x01c", "\x01\x02a\x03", "abc\x01def\x02ghi")
            code = Barcodes.encode(msg, :code128)
            @test msg == Barcodes.decode(code, :code128)
        end
    end

    @testset "randomized round trips" begin
        rng = TestLCG(0x00012345)
        alphabet = vcat(
            collect(Char(0):Char(31)), # control characters
            collect(' ':'~'),
            ['\x7f'],
            repeat(collect('0':'9'), 8), # make digit runs likely
        )
        for _ in 1:300
            len = 1 + nextint!(rng) % 25
            msg = String([alphabet[1 + nextint!(rng) % length(alphabet)] for _ in 1:len])
            code = Barcodes.encode(msg, :code128)
            @test Barcodes.decode(code, :code128) == msg
            pattern = Barcodes.barcode_pattern(code, :code128)
            @test Barcodes.barcode_decode(pattern, :code128) == msg
        end
    end

    @testset "Decoding errors" begin
        @test_throws ArgumentError Barcodes.decode(["A", "STOP"], :code128)
        @test_throws ArgumentError Barcodes.decode(["START B", "A", "STOP"], :qrcode)
    end
end

@testset "Patterns" begin

    @testset "code128 subtypes" begin
        let pattern = Barcodes.barcode_pattern("A", :code128a)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010000100" * # START A
                "10100011000" * # A
                "10100011000" * # checksum 33 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern("a", :code128b)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010010000" * # START B
                "10010110000" * # a
                "10010000110" * # checksum 66 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern("00", :code128c)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010011100" * # START C
                "11011001100" * # 00
                "11001100110" * # checksum 2 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end
    end

    @testset "code128 auto" begin
        let pattern = Barcodes.barcode_pattern("A", :code128)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010010000" * # START B
                "10100011000" * # A
                "10001011000" * # checksum 34 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern("a", :code128)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010010000" * # START B
                "10010110000" * # a
                "10010000110" * # checksum 66 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern("00", :code128)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010011100" * # START C
                "11011001100" * # 00
                "11001100110" * # checksum 2 pattern
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern("\x02A\tB\x07\x03", :code128)
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010000100" * # START A
                "10010000110" * # \x02 = STX = Start of Text
                "10100011000" * # A
                "10000110100" * # \t = Horizontal Tab
                "10001011000" * # B
                "10011010000" * # \x07 = BEL = Bell
                "10000101100" * # \x03 = ETX = End of Text
                "10001100100" * # CHECKSUM 8
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end
    end

    @testset "mixed subtypes" begin

        let pattern = Barcodes.barcode_pattern(
                [
                    "START A"
                    "A"
                    "B"
                    "SHIFT B"
                    "a"
                    "A"
                    "CODE C"
                    "00"
                    "CHECKSUM"
                    "STOP"
                ],
                :code128
            )
            @test pattern ==
                "00000000000" * # Quiet zone
                "11010000100" * # "START A" (103)
                "10100011000" * # "A" (33)
                "10001011000" * # "B" (34)
                "11110100010" * # "SHIFT B" (98)
                "10010110000" * # "a" (65)
                "10100011000" * # "A" (33)
                "10111011110" * # "CODE C" (99)
                "11011001100" * # "00" (0)
                "11000010010" * # CHECKSUM (75)
                # ( 103 + 1 * 33 + 2 * 34 + 3 * 98 + 4 * 65 + 5 * 33 + 6 * 99 + 7 * 0 ) % 103
                "11000111010" * # STOP
                "11" * # END
                "00000000000" # Quiet zone
        end

        let pattern = Barcodes.barcode_pattern(
                [
                    "START C"
                    "FNC 1"
                    "42"
                    "18"
                    "40"
                    "20"
                    "50"
                    "CODE A"
                    "0"
                    "CHECKSUM"
                    "STOP"
                ],
                :code128,
            )
            # 11 symbols of 11 modules each, plus the END bars and the two quiet zones
            @test length(pattern) == 22 + 11 * 11 + 2
            @test all(c -> c in ('0', '1'), pattern)
        end
    end

    @testset "Pattern errors" begin
        # unknown encoding type
        @test_throws ArgumentError Barcodes.barcode_pattern(["START B", "A", "CHECKSUM", "STOP"], :qrcode)
        @test_throws ArgumentError Barcodes.barcode_pattern("A", :qrcode)

        # malformed codes
        @test_throws ArgumentError Barcodes.barcode_pattern(["A", "B"], :code128) # no START
        @test_throws ArgumentError Barcodes.barcode_pattern(["START B", "A", "CHECKSUM"], :code128) # no STOP
        @test_throws ArgumentError Barcodes.barcode_pattern(["START B", "A", "STOP", "STOP"], :code128) # two STOPs
        @test_throws ArgumentError Barcodes.barcode_pattern(["START C", "A", "CHECKSUM", "STOP"], :code128) # "A" not in subtype C
    end
end

@testset "Depattern" begin
    for msg in (
        "ABC",
        "abc",
        "0123",
        "\x02ABC\x03",
        "\x02ABcZ\x03",
        "\x02AB012345\x03",
        "A b!\t0012\nZ z@\t0013\nAz `\t9999\naA \x7f\t1357"
    )
        code = Barcodes.encode(msg, :code128)
        pattern = Barcodes.barcode_pattern(code, :code128)
        @test msg == Barcodes.barcode_decode(pattern, :code128)
        @test code == Barcodes.barcode_depattern(pattern, :code128)
    end

    @testset "subtypes" begin
        for (msg, t) in (("ABC", :code128a), ("aBc 1~", :code128b), ("0123", :code128c))
            code = Barcodes.encode(msg, t)
            pattern = Barcodes.barcode_pattern(code, t)
            @test Barcodes.barcode_depattern(pattern, t) == code
            @test Barcodes.barcode_decode(pattern, t) == msg
        end
    end

    @testset "Depattern errors" begin
        @test_throws ArgumentError Barcodes.barcode_depattern("0101", :qrcode)
        @test_throws ArgumentError Barcodes.barcode_decode("0101", :qrcode)

        # not made of 0's and 1's
        @test_throws ArgumentError Barcodes.barcode_depattern("012", :code128)

        # too short
        @test_throws ArgumentError Barcodes.barcode_depattern("000" * "1"^5 * "000", :code128)

        # does not end with a double bar
        @test_throws ArgumentError Barcodes.barcode_depattern("0"^3 * "1" * "0"^40 * "01", :code128)

        # wrong checksum: "A" with the checksum pattern for 33 instead of 34
        let bad_pattern =
                "0"^11 *
                "11010010000" * # START B
                "10100011000" * # A
                "10100011000" * # wrong checksum (33)
                "11000111010" * # STOP
                "11" *
                "0"^11
            @test_throws ArgumentError Barcodes.barcode_depattern(bad_pattern, :code128)
            @test_throws ArgumentError Barcodes.barcode_decode(bad_pattern, :code128)
        end
    end
end

@testset "Checksum" begin
    let code = Barcodes.encode("A", :code128)
        @test Barcodes.checksum(code, :code128) == 34
    end
    let code = Barcodes.encode("A", :code128a)
        @test Barcodes.checksum(code, :code128a) == 33
    end
    let code = Barcodes.encode("a", :code128b)
        @test Barcodes.checksum(code, :code128b) == 66
    end
    let code = Barcodes.encode("00", :code128c)
        @test Barcodes.checksum(code, :code128c) == 2
    end
    let code =
        [
            "START A"
            "A"
            "B"
            "SHIFT B"
            "a"
            "A"
            "CODE C"
            "00"
            "CHECKSUM"
            "STOP"
        ]
        @test Barcodes.checksum(code, :code128) == 75
    end

    @testset "Checksum errors and warnings" begin
        @test_throws ArgumentError Barcodes.checksum(["START B", "A", "CHECKSUM", "STOP"], :qrcode)
        @test_throws ArgumentError Barcodes.checksum(["A", "B", "C"], :code128) # no START
        @test_throws ArgumentError Barcodes.checksum(["START B", "~~", "CHECKSUM", "STOP"], :code128) # invalid symbol

        # a wrong checksum value in the code gives a warning, and the computed value is returned
        let code = ["START B", "A", "CHECKSUM 99", "STOP"]
            chk = @test_logs (:warn, r"does not match") Barcodes.checksum(code, :code128)
            @test chk == 34
        end
    end
end

@testset "Utils" begin
    @testset "barcode_positions" begin
        let (x, w) = Barcodes.barcode_positions("0110100")
            @test x == [2, 5]
            @test w == [2, 1]
        end
        # a pattern ending in a bar
        let (x, w) = Barcodes.barcode_positions("01101")
            @test x == [2, 5]
            @test w == [2, 1]
        end
    end

    @testset "barcode_widths" begin
        # each of the k symbols has 11 modules, whose widths are 6 digits adding up to 11
        let pattern = Barcodes.barcode_pattern("12345678", :code128)
            k = (length(pattern) - 24) ÷ 11
            w = Barcodes.barcode_widths(pattern)
            @test length(w) == 6k
            @test sum(c -> parse(Int, c), w) == 11k
            @test all(c -> c in '1':'4', w)
            @test startswith(w, "211232") # START C = 11010011100
        end
    end

    @testset "barcode_img" begin
        let pattern = Barcodes.barcode_pattern("12345678", :code128)
            img = Barcodes.barcode_img(pattern)
            @test size(img) == (52, length(pattern))

            img = Barcodes.barcode_img(pattern; img_height = 10)
            @test size(img) == (12, length(pattern))

            # first and last rows are blank padding, the rest repeat the pattern
            @test all(img[1, :] .== img[1, 1])
            @test all(img[end, :] .== img[1, 1])
            @test all(r -> img[r, :] == img[2, :], 2:size(img, 1)-1)

            # the quiet zone looks like the padding, and a bar does not
            @test img[2, 1] == img[1, 1]
            firstbar = findfirst(==('1'), pattern)
            @test img[2, firstbar] != img[1, firstbar]
        end
    end

    @testset "utf8block_pattern" begin
        @test Barcodes.utf8block_pattern("1100") == "█ "
        @test Barcodes.utf8block_pattern("0110") == "▐▌"
    end
end

@testset "Code128 type" begin
    @testset "from a message" begin
        let b = Barcodes.Code128("12345678")
            @test b.message == "12345678"
            @test b.subtype == :code128c
            @test b.code == Barcodes.encode("12345678", :code128)
        end

        let b = Barcodes.Code128("\x02abc1234\x03")
            @test b.subtype == :code128
        end

        let b = Barcodes.Code128("ABC", :code128a)
            @test b.subtype == :code128a
        end

        @test_throws ArgumentError Barcodes.Code128("é")
        @test_throws ArgumentError Barcodes.Code128("")
    end

    @testset "from a code" begin
        let b = Barcodes.Code128(Barcodes.encode("ABC", :code128a))
            @test b.message == "ABC"
            @test b.subtype == :code128a
        end

        # the input code is not modified, and the checksum is filled in the stored code
        let code = ["START B", "A", "CHECKSUM", "STOP"]
            b = Barcodes.Code128(code)
            @test code == ["START B", "A", "CHECKSUM", "STOP"]
            @test b.code[end-1] == "CHECKSUM 34"
            @test b.message == "A"
            @test b.subtype == :code128b
        end
    end

    @testset "show" begin
        b = Barcodes.Code128("12345678")

        # one-line form
        @test sprint(show, b) == "Code128(\"12345678\")"
        @test occursin("Code128(\"12345678\")", sprint(show, [b]))
        @test !occursin('\n', sprint(show, [b]))

        # multi-line form
        let s = sprint(show, MIME("text/plain"), b)
            @test startswith(s, "Code128: 12345678")
            @test !occursin("Code:", s)
            @test !endswith(s, "\n")
        end

        # detailed form
        let s = sprint(show, MIME("text/plain"), b; context = :detailed => true)
            @test occursin("Barcode type: Code128c", s)
            @test occursin("Message: 12345678", s)
            @test occursin("START C", s)
            @test occursin("STOP", s)
        end
    end
end

@testset "Images" begin
    @testset "save Images.jl" begin
        let zip_code = "12.345-678"
            zip_code = replace(zip_code, r"\s|\.|\-" => "")
            pattern = Barcodes.barcode_pattern(zip_code, :code128)
            img = Barcodes.barcode_img(pattern)
            mktempdir() do dir
                path = joinpath(dir, "zipcode_img.png")
                FileIO.save(path, img)
                @test isfile(path)
                @test filesize(path) > 0
                @test FileIO.load(path) == img
            end
        end

        let pattern = Barcodes.barcode_pattern("\x02abc1234\x03", :code128)
            img = Barcodes.barcode_img(pattern)
            mktempdir() do dir
                path = joinpath(dir, "abc1234.png")
                FileIO.save(path, img)
                @test isfile(path)
                @test filesize(path) > 0
                @test FileIO.load(path) == img
            end
        end
    end

    @testset "Plot barcode" begin
        let zip_code = "12.345-678"
            zip_code = replace(zip_code, r"\s|\.|\-" => "")
            pattern = Barcodes.barcode_pattern(zip_code, :code128)
            x, w = Barcodes.barcode_positions(pattern)
            p = Plots.plot(
                [x'; x' + w'], ones(2, length(x)), color = :black, fill = true,
                xlims = (1, length(pattern)),  ylims = (0, 1), border = :none,
                legend = nothing, size = (400, 150)
            )
            mktempdir() do dir
                path = joinpath(dir, "zipcode_plot.png")
                Plots.savefig(p, path)
                @test isfile(path)
                @test filesize(path) > 0
            end
        end
    end
end
