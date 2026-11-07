using Barcodes
using Test
using FileIO

ENV["GKSwstype"] = "100" # it runs Plots without a display, but it is not needed for the tests, so it will be removed once Documentation is ready
using Plots # it is in runtests.jl just to generate the image for README
            # it will be removed from tests once Documentation is ready

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

        end
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
