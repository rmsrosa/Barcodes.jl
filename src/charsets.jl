# 

"""
This dictionary gives the binary representation of digits and flow control symbols according
to the 128C standard representation.

From `00` to `99`, the key represents the digits in the code, while from `100` to `102`,
the key represents the value of the check symbol. From `START C` onwards, the key is
the character.
"""
const CODE128C = Dict(
    "00" => "11011001100",
    "01" => "11001101100",
    "02" => "11001100110",
    "03" => "10010011000",
    "04" => "10010001100",
    "05" => "10001001100",
    "06" => "10011001000",
    "07" => "10011000100",
    "08" => "10001100100",
    "09" => "11001001000",
    "10" => "11001000100",
    "11" => "11000100100",
    "12" => "10110011100",
    "13" => "10011011100",
    "14" => "10011001110",
    "15" => "10111001100",
    "16" => "10011101100",
    "17" => "10011100110",
    "18" => "11001110010",
    "19" => "11001011100",
    "20" => "11001001110",
    "21" => "11011100100",
    "22" => "11001110100",
    "23" => "11101101110",
    "24" => "11101001100",
    "25" => "11100101100",
    "26" => "11100100110",
    "27" => "11101100100",
    "28" => "11100110100",
    "29" => "11100110010",
    "30" => "11011011000",
    "31" => "11011000110",
    "32" => "11000110110",
    "33" => "10100011000",
    "34" => "10001011000",
    "35" => "10001000110",
    "36" => "10110001000",
    "37" => "10001101000",
    "38" => "10001100010",
    "39" => "11010001000",
    "40" => "11000101000",
    "41" => "11000100010",
    "42" => "10110111000",
    "43" => "10110001110",
    "44" => "10001101110",
    "45" => "10111011000",
    "46" => "10111000110",
    "47" => "10001110110",
    "48" => "11101110110",
    "49" => "11010001110",
    "50" => "11000101110",
    "51" => "11011101000",
    "52" => "11011100010",
    "53" => "11011101110",
    "54" => "11101011000",
    "55" => "11101000110",
    "56" => "11100010110",
    "57" => "11101101000",
    "58" => "11101100010",
    "59" => "11100011010",
    "60" => "11101111010",
    "61" => "11001000010",
    "62" => "11110001010",
    "63" => "10100110000",
    "64" => "10100001100",
    "65" => "10010110000",
    "66" => "10010000110",
    "67" => "10000101100",
    "68" => "10000100110",
    "69" => "10110010000",
    "70" => "10110000100",
    "71" => "10011010000",
    "72" => "10011000010",
    "73" => "10000110100",
    "74" => "10000110010",
    "75" => "11000010010",
    "76" => "11001010000",
    "77" => "11110111010",
    "78" => "11000010100",
    "79" => "10001111010",
    "80" => "10100111100",
    "81" => "10010111100",
    "82" => "10010011110",
    "83" => "10111100100",
    "84" => "10011110100",
    "85" => "10011110010",
    "86" => "11110100100",
    "87" => "11110010100",
    "88" => "11110010010",
    "89" => "11011011110",
    "90" => "11011110110",
    "91" => "11110110110",
    "92" => "10101111000",
    "93" => "10100011110",
    "94" => "10001011110",
    "95" => "10111101000",
    "96" => "10111100010",
    "97" => "11110101000",
    "98" => "11110100010",
    "99" => "10111011110",
    "100" => "10111101110",
    "101" => "11101011110",
    "102" => "11110101110",
    "START C" => "11010011100",
    "STOP" => "11000111010",
    "END" => "11"
)

const charset = DataFrame(
    value = 0:106,
    code128a = [
        string.(' ':'_');
        [
            "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "HT", "LF", "VT",
            "FF", "CR", "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
            "CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US", "FNC 3", "FNC 2", "Shift B",
            "Code C", "Code B", "FNC 4", "FNC 1", "START A", "START B", "START C", "STOP"
        ]
    ],
    code128b = [
        string.(' ':'~');
        ["DEL", "FNC 3", "FNC 2", "Shift A", "Code C", "FNC 4", "Code A", "FNC 1"];
        ["START A", "START B", "START C", "STOP"]
    ],
    code128c = [
        replace.(lpad.(0:99, 2), ' '  => '0');
        string.(100:102);
        ["START A", "START B", "START C", "STOP"]
    ],
    pattern = [
        "11011001100",
        "11001101100",
        "11001100110",
        "10010011000",
        "10010001100",
        "10001001100",
        "10011001000",
        "10011000100",
        "10001100100",
        "11001001000",
        "11001000100",
        "11000100100",
        "10110011100",
        "10011011100",
        "10011001110",
        "10111001100",
        "10011101100",
        "10011100110",
        "11001110010",
        "11001011100",
        "11001001110",
        "11011100100",
        "11001110100",
        "11101101110",
        "11101001100",
        "11100101100",
        "11100100110",
        "11101100100",
        "11100110100",
        "11100110010",
        "11011011000",
        "11011000110",
        "11000110110",
        "10100011000",
        "10001011000",
        "10001000110",
        "10110001000",
        "10001101000",
        "10001100010",
        "11010001000",
        "11000101000",
        "11000100010",
        "10110111000",
        "10110001110",
        "10001101110",
        "10111011000",
        "10111000110",
        "10001110110",
        "11101110110",
        "11010001110",
        "11000101110",
        "11011101000",
        "11011100010",
        "11011101110",
        "11101011000",
        "11101000110",
        "11100010110",
        "11101101000",
        "11101100010",
        "11100011010",
        "11101111010",
        "11001000010",
        "11110001010",
        "10100110000",
        "10100001100",
        "10010110000",
        "10010000110",
        "10000101100",
        "10000100110",
        "10110010000",
        "10110000100",
        "10011010000",
        "10011000010",
        "10000110100",
        "10000110010",
        "11000010010",
        "11001010000",
        "11110111010",
        "11000010100",
        "10001111010",
        "10100111100",
        "10010111100",
        "10010011110",
        "10111100100",
        "10011110100",
        "10011110010",
        "11110100100",
        "11110010100",
        "11110010010",
        "11011011110",
        "11011110110",
        "11110110110",
        "10101111000",
        "10100011110",
        "10001011110",
        "10111101000",
        "10111100010",
        "11110101000",
        "11110100010",
        "10111011110",
        "10111101110",
        "11101011110",
        "11110101110",
        "11010000100",
        "11010010000",
        "11010011100",
        "11000111010"
    ]
)
