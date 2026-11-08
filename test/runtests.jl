using Barcodes
using Test
using FileIO

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

    @testset "Code128 ties" begin
        # same number of symbols with different choices: prefer the start code set that has
        # the first character, and CODE (rather than SHIFT) unless the next character returns
        # to the current code set
        @test Barcodes.encode("\x02Abc\x03", :code128) == [
            "START A", "STX", "A", "CODE B", "b", "c", "CODE A", "ETX", "CHECKSUM 46", "STOP"
        ]
        @test Barcodes.encode("\x02abc1234\x03", :code128) == [
            "START A", "STX", "CODE B", "a", "b", "c", "CODE C", "12", "34", "CODE A", "ETX",
            "CHECKSUM 87", "STOP"
        ]
        @test Barcodes.encode("AaBC\x02", :code128) == [
            "START B", "A", "a", "B", "C", "CODE A", "STX", "CHECKSUM 71", "STOP"
        ]
        @test Barcodes.encode("a\x01", :code128) == [
            "START B", "a", "CODE A", "SOH", "CHECKSUM 51", "STOP"
        ]
        @test Barcodes.encode("ab\x01c", :code128) == [
            "START B", "a", "b", "SHIFT A", "SOH", "c", "CHECKSUM 57", "STOP"
        ]

        # digits: three of them are not worth CODE C, an odd number at the beginning goes
        # with START C and the last one with CODE B
        @test Barcodes.encode("123", :code128) == ["START B", "1", "2", "3", "CHECKSUM 8", "STOP"]
        @test Barcodes.encode("1234567", :code128) == [
            "START C", "12", "34", "56", "CODE B", "7", "CHECKSUM 44", "STOP"
        ]
    end

    @testset "Code128 is the shortest" begin
        # independent shortest-path search, to compare with the number of symbols
        function min_symbols(chars)
            n = length(chars)
            isa_(c) = c ≤ 95
            isb_(c) = c ≥ 32
            dig(c) = 48 ≤ c ≤ 57
            queue = [(1, 1, k) for k in 1:3] # (cost, position, code set), after START
            seen = Set{Tuple{Int,Int}}()
            while !isempty(queue)
                sort!(queue)
                cost, i, k = popfirst!(queue)
                (i, k) in seen && continue
                push!(seen, (i, k))
                i == n + 1 && return cost
                c = chars[i]
                k == 1 && isa_(c) && push!(queue, (cost + 1, i + 1, k))
                k == 2 && isb_(c) && push!(queue, (cost + 1, i + 1, k))
                k == 3 && i < n && dig(c) && dig(chars[i+1]) && push!(queue, (cost + 1, i + 2, k))
                k == 1 && isb_(c) && push!(queue, (cost + 2, i + 1, k)) # SHIFT
                k == 2 && isa_(c) && push!(queue, (cost + 2, i + 1, k)) # SHIFT
                for j in 1:3
                    j != k && push!(queue, (cost + 1, i, j)) # CODE
                end
            end
        end

        rng = TestLCG(0x0000abcd)
        alphabet = vcat(
            collect(Char(0):Char(31)), collect(' ':'~'), ['\x7f'], repeat(collect('0':'9'), 8)
        )
        for _ in 1:200
            len = 1 + nextint!(rng) % 14
            msg = String([alphabet[1 + nextint!(rng) % length(alphabet)] for _ in 1:len])
            code = Barcodes.encode(msg, :code128)
            @test length(code) - 2 == min_symbols(Int.(collect(msg))) # no CHECKSUM and STOP
        end
    end

    @testset "FNC4" begin
        # hand-checked: a single FNC 4 adds 128 to the next character
        @test Barcodes.encode("é", :code128b) == ["START B", "FNC 4", "i", "CHECKSUM 41", "STOP"]
        @test Barcodes.encode("\u0080", :code128a) == ["START A", "FNC 4", "NUL", "CHECKSUM 23", "STOP"]
        @test Barcodes.encode("é", :code128) == ["START B", "FNC 4", "i", "CHECKSUM 41", "STOP"]
        @test Barcodes.encode("Héllo", :code128) ==
            ["START B", "H", "FNC 4", "i", "l", "l", "o", "CHECKSUM 73", "STOP"]

        # a single FNC 4 for each extended character is shorter than latching for two of them
        @test Barcodes.encode("éÉ", :code128) ==
            ["START B", "FNC 4", "i", "FNC 4", "I", "CHECKSUM 93", "STOP"]

        # two FNC 4 latch the extended mode
        @test Barcodes.encode("ÿÿÿÿ", :code128) ==
            ["START B", "FNC 4", "FNC 4", "DEL", "DEL", "DEL", "DEL", "CHECKSUM 54", "STOP"]
        @test Barcodes.encode("\u0080\u0081\u0082", :code128) ==
            ["START A", "FNC 4", "FNC 4", "NUL", "SOH", "STX", "CHECKSUM 55", "STOP"]

        # decoding
        for (msg, type) in (
            ("é", :code128b), ("\u0080", :code128a), ("Héllo", :code128), ("ÿÿÿÿ", :code128),
            ("aéb", :code128b), ("12é34", :code128), ("ÀÉÎÕÜ", :code128a), ("¡¢£¤¥¦", :code128b),
            ("\u0080a\u0081", :code128), ("é1234567é", :code128), ("12345678é", :code128),
        )
            code = Barcodes.encode(msg, type)
            @test Barcodes.decode(code, type) == msg
            @test Barcodes.message(Barcodes.Code128(msg, type)) == msg
        end

        # latching and unlatching the extended mode: an FNC 4 after the two that latch it
        # gives a single non-extended character
        let values = UInt8[104, 100, 100, 73, 100, 73, 73, 0, 106] # START B, FNC4 FNC4, "i", FNC4 "i", "i"
            values[end-1] = Barcodes._checksum(values)
            @test Barcodes._decode_values(values) == "éié"
        end
        let values = UInt8[104, 100, 100, 73, 100, 100, 73, 0, 106] # START B, FNC4 FNC4, "i", FNC4 FNC4, "i"
            values[end-1] = Barcodes._checksum(values)
            @test Barcodes._decode_values(values) == "éi"
        end

        # the extended mode survives a change of the code set, and is not applied to code set C
        let values = UInt8[103, 101, 101, 33, 99, 12, 34, 100, 33, 0, 106] # START A, FNC4 FNC4, "A", C, "1234", B, "A"
            values[end-1] = Barcodes._checksum(values)
            @test Barcodes._decode_values(values) == "\u00c1" * "1234" * "\u00c1"
        end

        # FNC 4 can be followed by a SHIFT: FNC 4, SHIFT, "a" (from the code set B), then "A" in the code set A
        let values = UInt8[103, 101, 98, 65, 33, 0, 106]
            values[end-1] = Barcodes._checksum(values)
            @test Barcodes._decode_values(values) == "\u00e1A"
        end

        # the type holds the values, and `message` gives them back
        let b = Barcodes.Code128("Ça va? Très bien.")
            @test Barcodes.message(b) == "Ça va? Très bien."
            @test Barcodes.Code128(Barcodes.codenames(b)) == b
            @test Barcodes.barcode_decode(Barcodes.barcode_pattern(b), :code128) == "Ça va? Très bien."
        end

        # the encoding is the shortest, with an independent search that counts FNC 4 symbols
        # (a single FNC 4 sets a flag for the next character, and a second one in a row flips
        # the latched extended mode)
        function min_symbols_fnc4(chars)
            n = length(chars)
            isa_(b) = b ≤ 95
            isb_(b) = b ≥ 32
            dig(c) = 48 ≤ c ≤ 57
            queue = [(1, 1, k, 0, 0) for k in 1:3] # (cost, position, code set, latched, flag)
            seen = Set{NTuple{4,Int}}()
            while !isempty(queue)
                sort!(queue)
                cost, i, k, lat, flag = popfirst!(queue)
                (i, k, lat, flag) in seen && continue
                push!(seen, (i, k, lat, flag))
                i == n + 1 && flag == 0 && return cost
                if i ≤ n
                    c = chars[i]
                    b = c & 0x7f
                    x = c ≥ 128 ? 1 : 0
                    if k ≤ 2 && (lat ⊻ flag) == x
                        k == 1 && isa_(b) && push!(queue, (cost + 1, i + 1, k, lat, 0))
                        k == 2 && isb_(b) && push!(queue, (cost + 1, i + 1, k, lat, 0))
                        k == 1 && isb_(b) && push!(queue, (cost + 2, i + 1, k, lat, 0)) # SHIFT
                        k == 2 && isa_(b) && push!(queue, (cost + 2, i + 1, k, lat, 0)) # SHIFT
                    end
                    if k == 3 && i < n && dig(c) && dig(chars[i+1])
                        push!(queue, (cost + 1, i + 2, k, lat, flag))
                    end
                end
                if flag == 0
                    for j in 1:3
                        j != k && push!(queue, (cost + 1, i, j, lat, 0)) # CODE
                    end
                end
                if k ≤ 2
                    # FNC 4: either set the flag, or flip the latched mode if the flag was set
                    push!(queue, (cost + 1, i, k, flag == 1 ? 1 - lat : lat, 1 - flag))
                end
            end
        end

        rng = TestLCG(0x0000fa4c)
        alphabet = vcat(
            collect(Char(0):Char(31)), collect(' ':'~'), ['\x7f'], collect(Char(128):Char(255)),
            repeat(collect('0':'9'), 6)
        )
        for _ in 1:300
            len = 1 + nextint!(rng) % 14
            msg = String([alphabet[1 + nextint!(rng) % length(alphabet)] for _ in 1:len])
            code = Barcodes.encode(msg, :code128)
            @test length(code) - 2 == min_symbols_fnc4(Int.(collect(msg))) # no CHECKSUM and STOP
            @test Barcodes.decode(code, :code128) == msg
            @test Barcodes.message(Barcodes.Code128(msg)) == msg
        end
    end

    @testset "Encoding errors" begin
        # empty message
        for t in (:code128, :code128a, :code128b, :code128c)
            @test_throws ArgumentError Barcodes.encode("", t)
        end

        # characters outside of Latin-1 (code points above U+00FF)
        for t in (:code128, :code128a, :code128b, :code128c)
            @test_throws ArgumentError Barcodes.encode("ā", t)
            @test_throws ArgumentError Barcodes.encode("€", t)
        end

        # Latin-1 characters in the subtype C, and in the wrong subtype
        @test_throws ArgumentError Barcodes.encode("é", :code128c)
        @test_throws ArgumentError Barcodes.encode("é", :code128a) # base character "i" is lowercase
        @test_throws ArgumentError Barcodes.encode("\u00e9\x01", :code128b) # control character

        # characters not available in the chosen subtype
        @test_throws ArgumentError Barcodes.encode("abc", :code128a) # lowercase
        @test_throws ArgumentError Barcodes.encode("\x01", :code128b) # control character
        @test_throws ArgumentError Barcodes.encode("abc", :code128c) # not digits
        @test_throws ArgumentError Barcodes.encode("123", :code128c) # odd number of digits

        # unknown encoding type
        @test_throws ArgumentError Barcodes.encode("abc", :qrcode)
    end
end

@testset "GS1-128" begin
    @testset "gs1_element_string" begin
        @test Barcodes.gs1_element_string("(01)09501101530003") == "0109501101530003"
        # fixed-length element strings are not followed by a separator
        @test Barcodes.gs1_element_string("(01)09501101530003(17)140704") == "010950110153000317140704"
        @test Barcodes.gs1_element_string("(11)200101(15)210101(20)12") == "112001011521010120" * "12"
        @test Barcodes.gs1_element_string("(3103)000123(410)1234567890128") == "3103000123" * "4101234567890128"
        # variable-length element strings are followed by a separator, except the last one
        @test Barcodes.gs1_element_string("(10)ABC123(21)XYZ") == "10ABC123\x1d21XYZ"
        @test Barcodes.gs1_element_string("(10)ABC123") == "10ABC123"
        @test Barcodes.gs1_element_string("(01)09501101530003(10)ABC123(21)XYZ") ==
            "0109501101530003" * "10ABC123\x1d21XYZ"
        @test Barcodes.gs1_element_string("(240)ABC(10)123") == "240ABC\x1d10123"

        # errors
        @test_throws ArgumentError Barcodes.gs1_element_string("")
        @test_throws ArgumentError Barcodes.gs1_element_string("0109501101530003")
        @test_throws ArgumentError Barcodes.gs1_element_string("(01)09501101530003 (10)ABC")
        @test_throws ArgumentError Barcodes.gs1_element_string("(0x)12")
        @test_throws ArgumentError Barcodes.gs1_element_string("(10)")
        @test_throws ArgumentError Barcodes.gs1_element_string("(01)123") # wrong length
        @test_throws ArgumentError Barcodes.gs1_element_string("(01)0950110153000x") # not digits
        @test_throws ArgumentError Barcodes.gs1_element_string("(31)123456") # AI should be 31nn
        @test_throws ArgumentError Barcodes.gs1_element_string("(410)123456789012") # one digit short
    end

    @testset "Encoding and decoding" begin
        # hand-checked: ( 105 + 1 * 102 + 2 * 1 + 3 * 9 + 4 * 50 + 5 * 11 + 6 * 1 + 7 * 53 + 8 * 0 + 9 * 3 ) % 103 = 71
        @test Barcodes.encode("(01)09501101530003", :gs1128) ==
            ["START C", "FNC 1", "01", "09", "50", "11", "01", "53", "00", "03", "CHECKSUM 71", "STOP"]
        # the element string is the same as the human readable form
        @test Barcodes.encode("0109501101530003", :gs1128) == Barcodes.encode("(01)09501101530003", :gs1128)

        # FNC 1 as a separator, and the digits are in pairs between separators
        # ( 104 + 1 * 102 + 2 * 17 + 3 * 16 + 4 * 33 + 5 * 34 + 6 * 35 + 7 * 17 + 8 * 18 + 9 * 19 + 10 * 102 + 11 * 18 + 12 * 17 + 13 * 56 + 14 * 57 + 15 * 58 ) % 103 = 5
        @test Barcodes.encode("(10)ABC123(21)XYZ", :gs1128) ==
            ["START B", "FNC 1", "1", "0", "A", "B", "C", "1", "2", "3", "FNC 1", "2", "1", "X", "Y", "Z", "CHECKSUM 5", "STOP"]
        @test Barcodes.encode("(01)09501101530003(17)140704(10)ABC123", :gs1128) ==
            [
                "START C", "FNC 1", "01", "09", "50", "11", "01", "53", "00", "03", "17", "14", "07", "04",
                "10", "CODE B", "A", "B", "C", "1", "2", "3", "CHECKSUM 45", "STOP"
            ]

        for msg in (
            "(01)09501101530003", "(00)340123450000000015", "(21)12345678", "(37)5(10)12345",
            "(10)ABC123(21)XYZ(01)09501101530003", "(01)09501101530003(10)AB(21)12", "(240)abc def~",
        )
            code = Barcodes.encode(msg, :gs1128)
            @test code[1] in ("START B", "START C")
            @test code[2] == "FNC 1"
            es = Barcodes.gs1_element_string(msg)
            @test Barcodes.decode(code, :gs1128) == es
            # also with the other encoding types, since there is nothing but the FNC 1
            @test Barcodes.decode(code, :code128) == es
            pattern = Barcodes.barcode_pattern(msg, :gs1128)
            @test pattern == Barcodes.barcode_pattern(code, :gs1128)
            @test Barcodes.barcode_decode(pattern, :gs1128) == es
            @test Barcodes.barcode_depattern(pattern, :gs1128) == code
        end

        # the quiet zones, START, FNC 1, 01, ..., CHECKSUM, STOP, and the end bar
        pattern = Barcodes.barcode_pattern("(21)12", :gs1128)
        @test startswith(
            pattern,
            "00000000000" * "11010011100" * "11110101110" *
            Barcodes.CODE128_PATTERNS[21+1] * Barcodes.CODE128_PATTERNS[12+1]
        )
        @test endswith(pattern, "11000111010" * "11" * "00000000000")

        # errors
        @test_throws ArgumentError Barcodes.encode("", :gs1128)
        @test_throws ArgumentError Barcodes.encode("ABC", :gs1128) # no Application Identifier
        @test_throws ArgumentError Barcodes.encode("\x1d12", :gs1128)
        @test_throws ArgumentError Barcodes.encode("12\x1d", :gs1128)
        @test_throws ArgumentError Barcodes.encode("12\x1d\x1d34", :gs1128)
        @test_throws ArgumentError Barcodes.encode("12é", :gs1128) # no FNC 4 in GS1-128
        @test_throws ArgumentError Barcodes.encode("12\x01", :gs1128)
        @test_throws ArgumentError Barcodes.encode("(01)123", :gs1128)
        # not a GS1-128
        @test_throws ArgumentError Barcodes.decode(Barcodes.encode("1234", :code128), :gs1128)
        @test_throws ArgumentError Barcodes.barcode_decode(
            Barcodes.barcode_pattern("1234", :code128), :gs1128
        )
        @test_throws ArgumentError Barcodes.barcode_depattern(
            Barcodes.barcode_pattern("1234", :code128), :gs1128
        )
    end

    @testset "FNC 1 in the other encoding types" begin
        # FNC 1 right after START is not part of the message, but in any other place it is a separator
        values(names) = Barcodes._parse_names(names)
        @test Barcodes.decode(["START C", "FNC 1", "12", "34", "CHECKSUM", "STOP"], :code128) == "1234"
        @test Barcodes.decode(["START C", "12", "FNC 1", "34", "CHECKSUM", "STOP"], :code128) == "12\x1d34"
        @test Barcodes.decode(["START B", "A", "FNC 1", "B", "CHECKSUM", "STOP"], :code128) == "A\x1dB"
        @test Barcodes.decode(["START A", "A", "FNC 1", "B", "CHECKSUM", "STOP"], :code128) == "A\x1dB"
        @test Barcodes.decode(["START B", "A", "CODE C", "FNC 1", "12", "CHECKSUM", "STOP"], :code128) == "A\x1d12"
    end

    @testset "Code128 type" begin
        b = Barcodes.Code128("(01)09501101530003(10)AB", :gs1128)
        @test Barcodes.isgs1128(b)
        @test Barcodes.message(b) == "0109501101530003" * "10AB"
        @test Barcodes.message(Barcodes.Code128("(10)AB(21)CD", :gs1128)) == "10AB\x1d21CD"
        @test Barcodes.Code128(Barcodes.codenames(b)) == b
        @test Barcodes.Code128(b.values) == b
        @test Barcodes.Code128("0109501101530003" * "10AB", :gs1128) == b
        @test Barcodes.barcode_pattern(b) == Barcodes.barcode_pattern("(01)09501101530003(10)AB", :gs1128)
        @test Barcodes.checksum(b) == Barcodes._checksum(b.values)
        @test Barcodes.subtype(b) == :code128 # it uses the code sets C and B
        @test Barcodes.subtype(Barcodes.Code128("(21)12345678", :gs1128)) == :code128c
        @test !Barcodes.isgs1128(Barcodes.Code128("0109501101530003"))
        @test Barcodes.Code128("0109501101530003") != Barcodes.Code128("0109501101530003", :gs1128)

        @test occursin("Code128(\"0109501101530003" , sprint(show, b))
        @test occursin(":gs1128)", sprint(show, b))
        @test occursin("GS1-128", sprint(show, MIME("text/plain"), b))
        @test occursin("GS1-128", sprint(show, MIME("text/plain"), b; context = :detailed => true))
        @test !occursin("GS1-128", sprint(show, MIME("text/plain"), Barcodes.Code128("123456")))
    end

    @testset "GS1-128 is the shortest" begin
        # independent search: the minimum number of symbols (without START, CHECKSUM, and STOP), where
        # FNC 1 (represented by 0) is in all the code sets and breaks the pairs of digits
        function min_symbols_gs1(chars)
            n = length(chars)
            isa_(c) = c ≤ 95
            isb_(c) = c ≥ 32
            dig(c) = 48 ≤ c ≤ 57
            queue = [(1, 1, k) for k in 1:3] # (cost, position, code set); the START
            seen = Set{Tuple{Int,Int}}()
            while !isempty(queue)
                sort!(queue)
                cost, i, k = popfirst!(queue)
                (i, k) in seen && continue
                push!(seen, (i, k))
                i == n + 1 && return cost
                c = chars[i]
                if c == 0
                    push!(queue, (cost + 1, i + 1, k))
                else
                    k == 1 && isa_(c) && push!(queue, (cost + 1, i + 1, k))
                    k == 2 && isb_(c) && push!(queue, (cost + 1, i + 1, k))
                    k == 1 && isb_(c) && push!(queue, (cost + 2, i + 1, k)) # SHIFT
                    k == 2 && isa_(c) && push!(queue, (cost + 2, i + 1, k)) # SHIFT
                    if k == 3 && i < n && dig(c) && dig(chars[i+1])
                        push!(queue, (cost + 1, i + 2, k))
                    end
                end
                for j in 1:3
                    j != k && push!(queue, (cost + 1, i, j)) # CODE
                end
            end
        end

        rng = TestLCG(0x00006511)
        alphabet = vcat(collect('0':'9'), collect('0':'9'), collect('0':'9'), collect('A':'Z'), collect('a':'e'), [' ', '~', '#'])
        for _ in 1:300
            nelements = 1 + nextint!(rng) % 4
            elements = map(1:nelements) do _
                len = 1 + nextint!(rng) % 8
                String([alphabet[1 + nextint!(rng) % length(alphabet)] for _ in 1:len])
            end
            # the first character should be a digit
            elements[1] = string('0' + nextint!(rng) % 10) * elements[1]
            msg = join(elements, '\x1d')
            code = Barcodes.encode(msg, :gs1128)
            chars = [c == '\x1d' ? 0 : Int(c) - 0 for c in msg]
            # the (leading) FNC 1 is one more symbol
            @test length(code) - 2 == min_symbols_gs1(pushfirst!(chars, 0))
            @test Barcodes.decode(code, :gs1128) == msg
            @test Barcodes.message(Barcodes.Code128(msg, :gs1128)) == msg
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
            @test Barcodes.message(b) == "12345678"
            @test Barcodes.subtype(b) == :code128c
            @test Barcodes.codenames(b) == Barcodes.encode("12345678", :code128)
        end

        let b = Barcodes.Code128("\x02abc1234\x03")
            @test Barcodes.subtype(b) == :code128
        end

        let b = Barcodes.Code128("ABC", :code128a)
            @test Barcodes.subtype(b) == :code128a
        end

        @test_throws ArgumentError Barcodes.Code128("€")
        @test_throws ArgumentError Barcodes.Code128("")
    end

    @testset "from a code" begin
        let b = Barcodes.Code128(Barcodes.encode("ABC", :code128a))
            @test Barcodes.message(b) == "ABC"
            @test Barcodes.subtype(b) == :code128a
        end

        # the input code is not modified, and the checksum is filled in the stored code
        let code = ["START B", "A", "CHECKSUM", "STOP"]
            b = Barcodes.Code128(code)
            @test code == ["START B", "A", "CHECKSUM", "STOP"]
            @test Barcodes.codenames(b)[end-1] == "CHECKSUM 34"
            @test Barcodes.message(b) == "A"
            @test Barcodes.subtype(b) == :code128b
        end
    end

    @testset "from values" begin
        # START B, "A" (33), CHECKSUM (104 + 33) % 103 = 34, STOP
        let b = Barcodes.Code128(UInt8[104, 33, 34, 106])
            @test Barcodes.message(b) == "A"
            @test Barcodes.checksum(b) == 34
            @test Barcodes.subtype(b) == :code128b
            @test Barcodes.codenames(b) == ["START B", "A", "CHECKSUM 34", "STOP"]
            @test b == Barcodes.Code128("A")
            @test hash(b) == hash(Barcodes.Code128("A"))
            @test Barcodes.barcode_pattern(b) == Barcodes.barcode_pattern("A", :code128)
        end

        @test_throws ArgumentError Barcodes.Code128([104, 33, 35, 106]) # wrong checksum
        @test_throws ArgumentError Barcodes.Code128([104, 33, 34]) # no STOP
        @test_throws ArgumentError Barcodes.Code128([33, 33, 34, 106]) # no START
        @test_throws ArgumentError Barcodes.Code128([104, 200, 34, 106]) # out of range
        @test_throws ArgumentError Barcodes.Code128([104, 106, 106]) # too short
    end

    @testset "subtype" begin
        @test Barcodes.subtype(Barcodes.Code128("ABC", :code128a)) == :code128a
        @test Barcodes.subtype(Barcodes.Code128("abc", :code128b)) == :code128b
        @test Barcodes.subtype(Barcodes.Code128("1234", :code128c)) == :code128c
        @test Barcodes.subtype(Barcodes.Code128("ab\x01c")) == :code128 # uses SHIFT
        @test Barcodes.subtype(Barcodes.Code128("1234567")) == :code128 # C and B
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
end
