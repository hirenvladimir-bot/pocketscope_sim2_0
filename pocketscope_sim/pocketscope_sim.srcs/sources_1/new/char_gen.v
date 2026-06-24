`timescale 1ns / 1ps
// Simple 8x8 Character Generator for VGA text overlay
// ASCII 0x20-0x5F supported (space through underscore), 64 chars total
// Font ROM: 512 bytes (64 chars × 8 rows)

module char_gen
(
    input  wire          clk,
    input  wire [7:0]    char_code,     // ASCII character
    input  wire [2:0]    char_row,      // row within char (0-7)
    input  wire [2:0]    char_col,      // column within char (0-7)
    output wire          pixel_on
);

    // 8x8 font ROM: 64 characters (0x20-0x5F), 8 bytes each = 512 bytes
    reg [7:0] font_rom [0:511];

    //=====================================================================
    // Font bitmap data — each character is 8 bytes (one per row, top to bottom)
    // Each byte: bit7=leftmost pixel, bit0=rightmost pixel
    //=====================================================================

    initial begin
        // ---- 0x20 Space ----
        font_rom[0]=8'h00; font_rom[1]=8'h00; font_rom[2]=8'h00; font_rom[3]=8'h00;
        font_rom[4]=8'h00; font_rom[5]=8'h00; font_rom[6]=8'h00; font_rom[7]=8'h00;
        // ---- 0x21 ! ----
        font_rom[8]=8'h18; font_rom[9]=8'h3C; font_rom[10]=8'h3C; font_rom[11]=8'h18;
        font_rom[12]=8'h18; font_rom[13]=8'h00; font_rom[14]=8'h18; font_rom[15]=8'h00;
        // ---- 0x22 " ----
        font_rom[16]=8'h66; font_rom[17]=8'h66; font_rom[18]=8'h24; font_rom[19]=8'h00;
        font_rom[20]=8'h00; font_rom[21]=8'h00; font_rom[22]=8'h00; font_rom[23]=8'h00;
        // ---- 0x23 # ----
        font_rom[24]=8'h00; font_rom[25]=8'h00; font_rom[26]=8'h00; font_rom[27]=8'h00;
        font_rom[28]=8'h00; font_rom[29]=8'h00; font_rom[30]=8'h00; font_rom[31]=8'h00;
        // ---- 0x24 $ ----
        font_rom[32]=8'h00; font_rom[33]=8'h00; font_rom[34]=8'h00; font_rom[35]=8'h00;
        font_rom[36]=8'h00; font_rom[37]=8'h00; font_rom[38]=8'h00; font_rom[39]=8'h00;
        // ---- 0x25 % ----
        font_rom[40]=8'h00; font_rom[41]=8'h00; font_rom[42]=8'h00; font_rom[43]=8'h00;
        font_rom[44]=8'h00; font_rom[45]=8'h00; font_rom[46]=8'h00; font_rom[47]=8'h00;
        // ---- 0x26 & ----
        font_rom[48]=8'h00; font_rom[49]=8'h00; font_rom[50]=8'h00; font_rom[51]=8'h00;
        font_rom[52]=8'h00; font_rom[53]=8'h00; font_rom[54]=8'h00; font_rom[55]=8'h00;
        // ---- 0x27 ' ----
        font_rom[56]=8'h00; font_rom[57]=8'h00; font_rom[58]=8'h00; font_rom[59]=8'h00;
        font_rom[60]=8'h00; font_rom[61]=8'h00; font_rom[62]=8'h00; font_rom[63]=8'h00;
        // ---- 0x28 ( ----
        font_rom[64]=8'h00; font_rom[65]=8'h00; font_rom[66]=8'h00; font_rom[67]=8'h00;
        font_rom[68]=8'h00; font_rom[69]=8'h00; font_rom[70]=8'h00; font_rom[71]=8'h00;
        // ---- 0x29 ) ----
        font_rom[72]=8'h00; font_rom[73]=8'h00; font_rom[74]=8'h00; font_rom[75]=8'h00;
        font_rom[76]=8'h00; font_rom[77]=8'h00; font_rom[78]=8'h00; font_rom[79]=8'h00;
        // ---- 0x2A * ----
        font_rom[80]=8'h00; font_rom[81]=8'h00; font_rom[82]=8'h00; font_rom[83]=8'h00;
        font_rom[84]=8'h00; font_rom[85]=8'h00; font_rom[86]=8'h00; font_rom[87]=8'h00;
        // ---- 0x2B + ----
        font_rom[88]=8'h00; font_rom[89]=8'h00; font_rom[90]=8'h00; font_rom[91]=8'h00;
        font_rom[92]=8'h00; font_rom[93]=8'h00; font_rom[94]=8'h00; font_rom[95]=8'h00;
        // ---- 0x2C , ----
        font_rom[96]=8'h00; font_rom[97]=8'h00; font_rom[98]=8'h00; font_rom[99]=8'h00;
        font_rom[100]=8'h00; font_rom[101]=8'h00; font_rom[102]=8'h00; font_rom[103]=8'h00;
        // ---- 0x2D - ----
        font_rom[104]=8'h00; font_rom[105]=8'h00; font_rom[106]=8'h00; font_rom[107]=8'h00;
        font_rom[108]=8'h00; font_rom[109]=8'h00; font_rom[110]=8'h00; font_rom[111]=8'h00;
        // ---- 0x2E . ----
        font_rom[112]=8'h00; font_rom[113]=8'h00; font_rom[114]=8'h00; font_rom[115]=8'h00;
        font_rom[116]=8'h00; font_rom[117]=8'h00; font_rom[118]=8'h18; font_rom[119]=8'h00;
        // ---- 0x2F / ----
        font_rom[120]=8'h00; font_rom[121]=8'h00; font_rom[122]=8'h00; font_rom[123]=8'h00;
        font_rom[124]=8'h00; font_rom[125]=8'h00; font_rom[126]=8'h00; font_rom[127]=8'h00;

        // ---- 0x30 0 ----
        font_rom[128]=8'h3C; font_rom[129]=8'h66; font_rom[130]=8'h6E; font_rom[131]=8'h76;
        font_rom[132]=8'h66; font_rom[133]=8'h66; font_rom[134]=8'h3C; font_rom[135]=8'h00;
        // ---- 0x31 1 ----
        font_rom[136]=8'h18; font_rom[137]=8'h38; font_rom[138]=8'h18; font_rom[139]=8'h18;
        font_rom[140]=8'h18; font_rom[141]=8'h18; font_rom[142]=8'h7E; font_rom[143]=8'h00;
        // ---- 0x32 2 ----
        font_rom[144]=8'h3C; font_rom[145]=8'h66; font_rom[146]=8'h0C; font_rom[147]=8'h18;
        font_rom[148]=8'h30; font_rom[149]=8'h60; font_rom[150]=8'h7E; font_rom[151]=8'h00;
        // ---- 0x33 3 ----
        font_rom[152]=8'h3C; font_rom[153]=8'h66; font_rom[154]=8'h06; font_rom[155]=8'h1C;
        font_rom[156]=8'h06; font_rom[157]=8'h66; font_rom[158]=8'h3C; font_rom[159]=8'h00;
        // ---- 0x34 4 ----
        font_rom[160]=8'h0C; font_rom[161]=8'h1C; font_rom[162]=8'h2C; font_rom[163]=8'h4C;
        font_rom[164]=8'h7E; font_rom[165]=8'h0C; font_rom[166]=8'h0C; font_rom[167]=8'h00;
        // ---- 0x35 5 ----
        font_rom[168]=8'h7E; font_rom[169]=8'h60; font_rom[170]=8'h7C; font_rom[171]=8'h06;
        font_rom[172]=8'h06; font_rom[173]=8'h66; font_rom[174]=8'h3C; font_rom[175]=8'h00;
        // ---- 0x36 6 ----
        font_rom[176]=8'h1C; font_rom[177]=8'h30; font_rom[178]=8'h60; font_rom[179]=8'h7C;
        font_rom[180]=8'h66; font_rom[181]=8'h66; font_rom[182]=8'h3C; font_rom[183]=8'h00;
        // ---- 0x37 7 ----
        font_rom[184]=8'h7E; font_rom[185]=8'h06; font_rom[186]=8'h0C; font_rom[187]=8'h18;
        font_rom[188]=8'h30; font_rom[189]=8'h30; font_rom[190]=8'h30; font_rom[191]=8'h00;
        // ---- 0x38 8 ----
        font_rom[192]=8'h3C; font_rom[193]=8'h66; font_rom[194]=8'h66; font_rom[195]=8'h3C;
        font_rom[196]=8'h66; font_rom[197]=8'h66; font_rom[198]=8'h3C; font_rom[199]=8'h00;
        // ---- 0x39 9 ----
        font_rom[200]=8'h3C; font_rom[201]=8'h66; font_rom[202]=8'h66; font_rom[203]=8'h3E;
        font_rom[204]=8'h06; font_rom[205]=8'h0C; font_rom[206]=8'h38; font_rom[207]=8'h00;

        // ---- 0x3A : ----
        font_rom[208]=8'h00; font_rom[209]=8'h00; font_rom[210]=8'h18; font_rom[211]=8'h00;
        font_rom[212]=8'h00; font_rom[213]=8'h00; font_rom[214]=8'h18; font_rom[215]=8'h00;
        // ---- 0x3B ; ----
        font_rom[216]=8'h00; font_rom[217]=8'h00; font_rom[218]=8'h00; font_rom[219]=8'h00;
        font_rom[220]=8'h00; font_rom[221]=8'h00; font_rom[222]=8'h00; font_rom[223]=8'h00;
        // ---- 0x3C < ----
        font_rom[224]=8'h00; font_rom[225]=8'h00; font_rom[226]=8'h00; font_rom[227]=8'h00;
        font_rom[228]=8'h00; font_rom[229]=8'h00; font_rom[230]=8'h00; font_rom[231]=8'h00;
        // ---- 0x3D = ----
        font_rom[232]=8'h00; font_rom[233]=8'h00; font_rom[234]=8'h00; font_rom[235]=8'h00;
        font_rom[236]=8'h00; font_rom[237]=8'h00; font_rom[238]=8'h00; font_rom[239]=8'h00;
        // ---- 0x3E > ----
        font_rom[240]=8'h00; font_rom[241]=8'h00; font_rom[242]=8'h00; font_rom[243]=8'h00;
        font_rom[244]=8'h00; font_rom[245]=8'h00; font_rom[246]=8'h00; font_rom[247]=8'h00;
        // ---- 0x3F ? ----
        font_rom[248]=8'h00; font_rom[249]=8'h00; font_rom[250]=8'h00; font_rom[251]=8'h00;
        font_rom[252]=8'h00; font_rom[253]=8'h00; font_rom[254]=8'h00; font_rom[255]=8'h00;

        // ---- 0x40 @ ----
        font_rom[256]=8'h00; font_rom[257]=8'h00; font_rom[258]=8'h00; font_rom[259]=8'h00;
        font_rom[260]=8'h00; font_rom[261]=8'h00; font_rom[262]=8'h00; font_rom[263]=8'h00;
        // ---- 0x41 A ----
        font_rom[264]=8'h18; font_rom[265]=8'h3C; font_rom[266]=8'h66; font_rom[267]=8'h66;
        font_rom[268]=8'h7E; font_rom[269]=8'h66; font_rom[270]=8'h66; font_rom[271]=8'h00;
        // ---- 0x42 B ----
        font_rom[272]=8'h7C; font_rom[273]=8'h66; font_rom[274]=8'h66; font_rom[275]=8'h7C;
        font_rom[276]=8'h66; font_rom[277]=8'h66; font_rom[278]=8'h7C; font_rom[279]=8'h00;
        // ---- 0x43 C ----
        font_rom[280]=8'h3C; font_rom[281]=8'h66; font_rom[282]=8'h60; font_rom[283]=8'h60;
        font_rom[284]=8'h60; font_rom[285]=8'h66; font_rom[286]=8'h3C; font_rom[287]=8'h00;
        // ---- 0x44 D ----
        font_rom[288]=8'h78; font_rom[289]=8'h6C; font_rom[290]=8'h66; font_rom[291]=8'h66;
        font_rom[292]=8'h66; font_rom[293]=8'h6C; font_rom[294]=8'h78; font_rom[295]=8'h00;
        // ---- 0x45 E ----
        font_rom[296]=8'h7E; font_rom[297]=8'h60; font_rom[298]=8'h60; font_rom[299]=8'h7C;
        font_rom[300]=8'h60; font_rom[301]=8'h60; font_rom[302]=8'h7E; font_rom[303]=8'h00;
        // ---- 0x46 F ----
        font_rom[304]=8'h7E; font_rom[305]=8'h60; font_rom[306]=8'h60; font_rom[307]=8'h7C;
        font_rom[308]=8'h60; font_rom[309]=8'h60; font_rom[310]=8'h60; font_rom[311]=8'h00;
        // ---- 0x47 G ----
        font_rom[312]=8'h3C; font_rom[313]=8'h66; font_rom[314]=8'h60; font_rom[315]=8'h6E;
        font_rom[316]=8'h66; font_rom[317]=8'h66; font_rom[318]=8'h3C; font_rom[319]=8'h00;
        // ---- 0x48 H ----
        font_rom[320]=8'h66; font_rom[321]=8'h66; font_rom[322]=8'h66; font_rom[323]=8'h7E;
        font_rom[324]=8'h66; font_rom[325]=8'h66; font_rom[326]=8'h66; font_rom[327]=8'h00;
        // ---- 0x49 I ----
        font_rom[328]=8'h00; font_rom[329]=8'h00; font_rom[330]=8'h00; font_rom[331]=8'h00;
        font_rom[332]=8'h00; font_rom[333]=8'h00; font_rom[334]=8'h00; font_rom[335]=8'h00;
        // ---- 0x4A J ----
        font_rom[336]=8'h00; font_rom[337]=8'h00; font_rom[338]=8'h00; font_rom[339]=8'h00;
        font_rom[340]=8'h00; font_rom[341]=8'h00; font_rom[342]=8'h00; font_rom[343]=8'h00;
        // ---- 0x4B K ----
        font_rom[344]=8'h66; font_rom[345]=8'h6C; font_rom[346]=8'h78; font_rom[347]=8'h70;
        font_rom[348]=8'h78; font_rom[349]=8'h6C; font_rom[350]=8'h66; font_rom[351]=8'h00;
        // ---- 0x4C L ----
        font_rom[352]=8'h00; font_rom[353]=8'h00; font_rom[354]=8'h00; font_rom[355]=8'h00;
        font_rom[356]=8'h00; font_rom[357]=8'h00; font_rom[358]=8'h00; font_rom[359]=8'h00;
        // ---- 0x4D M ----
        font_rom[360]=8'h00; font_rom[361]=8'h00; font_rom[362]=8'h00; font_rom[363]=8'h00;
        font_rom[364]=8'h00; font_rom[365]=8'h00; font_rom[366]=8'h00; font_rom[367]=8'h00;
        // ---- 0x4E N ----
        font_rom[368]=8'h00; font_rom[369]=8'h00; font_rom[370]=8'h00; font_rom[371]=8'h00;
        font_rom[372]=8'h00; font_rom[373]=8'h00; font_rom[374]=8'h00; font_rom[375]=8'h00;
        // ---- 0x4F O ----
        font_rom[376]=8'h00; font_rom[377]=8'h00; font_rom[378]=8'h00; font_rom[379]=8'h00;
        font_rom[380]=8'h00; font_rom[381]=8'h00; font_rom[382]=8'h00; font_rom[383]=8'h00;
        // ---- 0x50 P ----
        font_rom[384]=8'h00; font_rom[385]=8'h00; font_rom[386]=8'h00; font_rom[387]=8'h00;
        font_rom[388]=8'h00; font_rom[389]=8'h00; font_rom[390]=8'h00; font_rom[391]=8'h00;
        // ---- 0x51 Q ----
        font_rom[392]=8'h00; font_rom[393]=8'h00; font_rom[394]=8'h00; font_rom[395]=8'h00;
        font_rom[396]=8'h00; font_rom[397]=8'h00; font_rom[398]=8'h00; font_rom[399]=8'h00;
        // ---- 0x52 R ----
        font_rom[400]=8'h00; font_rom[401]=8'h00; font_rom[402]=8'h00; font_rom[403]=8'h00;
        font_rom[404]=8'h00; font_rom[405]=8'h00; font_rom[406]=8'h00; font_rom[407]=8'h00;
        // ---- 0x53 S ----
        font_rom[408]=8'h3C; font_rom[409]=8'h66; font_rom[410]=8'h60; font_rom[411]=8'h3C;
        font_rom[412]=8'h06; font_rom[413]=8'h66; font_rom[414]=8'h3C; font_rom[415]=8'h00;
        // ---- 0x54 T ----
        font_rom[416]=8'h7E; font_rom[417]=8'h18; font_rom[418]=8'h18; font_rom[419]=8'h18;
        font_rom[420]=8'h18; font_rom[421]=8'h18; font_rom[422]=8'h18; font_rom[423]=8'h00;
        // ---- 0x55 U ----
        font_rom[424]=8'h00; font_rom[425]=8'h00; font_rom[426]=8'h00; font_rom[427]=8'h00;
        font_rom[428]=8'h00; font_rom[429]=8'h00; font_rom[430]=8'h00; font_rom[431]=8'h00;
        // ---- 0x56 V ----
        font_rom[432]=8'h66; font_rom[433]=8'h66; font_rom[434]=8'h66; font_rom[435]=8'h66;
        font_rom[436]=8'h66; font_rom[437]=8'h3C; font_rom[438]=8'h18; font_rom[439]=8'h00;
        // ---- 0x57 W ----
        font_rom[440]=8'h00; font_rom[441]=8'h00; font_rom[442]=8'h00; font_rom[443]=8'h00;
        font_rom[444]=8'h00; font_rom[445]=8'h00; font_rom[446]=8'h00; font_rom[447]=8'h00;
        // ---- 0x58 X ----
        font_rom[448]=8'h00; font_rom[449]=8'h00; font_rom[450]=8'h00; font_rom[451]=8'h00;
        font_rom[452]=8'h00; font_rom[453]=8'h00; font_rom[454]=8'h00; font_rom[455]=8'h00;
        // ---- 0x59 Y ----
        font_rom[456]=8'h00; font_rom[457]=8'h00; font_rom[458]=8'h00; font_rom[459]=8'h00;
        font_rom[460]=8'h00; font_rom[461]=8'h00; font_rom[462]=8'h00; font_rom[463]=8'h00;
        // ---- 0x5A Z ----
        font_rom[464]=8'h7E; font_rom[465]=8'h06; font_rom[466]=8'h0C; font_rom[467]=8'h18;
        font_rom[468]=8'h30; font_rom[469]=8'h60; font_rom[470]=8'h7E; font_rom[471]=8'h00;
        // ---- 0x5B [ ----
        font_rom[472]=8'h00; font_rom[473]=8'h00; font_rom[474]=8'h00; font_rom[475]=8'h00;
        font_rom[476]=8'h00; font_rom[477]=8'h00; font_rom[478]=8'h00; font_rom[479]=8'h00;
        // ---- 0x5C \ ----
        font_rom[480]=8'h00; font_rom[481]=8'h00; font_rom[482]=8'h00; font_rom[483]=8'h00;
        font_rom[484]=8'h00; font_rom[485]=8'h00; font_rom[486]=8'h00; font_rom[487]=8'h00;
        // ---- 0x5D ] ----
        font_rom[488]=8'h00; font_rom[489]=8'h00; font_rom[490]=8'h00; font_rom[491]=8'h00;
        font_rom[492]=8'h00; font_rom[493]=8'h00; font_rom[494]=8'h00; font_rom[495]=8'h00;
        // ---- 0x5E ^ ----
        font_rom[496]=8'h00; font_rom[497]=8'h00; font_rom[498]=8'h00; font_rom[499]=8'h00;
        font_rom[500]=8'h00; font_rom[501]=8'h00; font_rom[502]=8'h00; font_rom[503]=8'h00;
        // ---- 0x5F _ ----
        font_rom[504]=8'h00; font_rom[505]=8'h00; font_rom[506]=8'h00; font_rom[507]=8'h00;
        font_rom[508]=8'h00; font_rom[509]=8'h00; font_rom[510]=8'h7E; font_rom[511]=8'h00;
    end

    //=====================================================================
    // ROM address: char_idx = (char_code - 0x20), bounded to 0-63
    // Only characters in range 0x20-0x5F are valid
    //=====================================================================
    wire [5:0] char_idx = char_code[5:0] - 6'h20;  // 0x20→0, 0x21→1, ..., 0x5F→63
    wire [8:0] rom_addr = {char_idx, char_row};     // char_idx * 8 + row
    wire [7:0] row_data = font_rom[rom_addr];

    // Output: extract the column bit (MSB = leftmost pixel)
    assign pixel_on = row_data[7 - char_col];

endmodule
