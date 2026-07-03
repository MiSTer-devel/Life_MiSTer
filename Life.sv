/*============================================================================
 *  Conway's Game Of Life
 *  Copyright (C) 2020 Hrvoje Cavrak
 *
 *  Please read LICENSE file.
 *============================================================================*/

module emu
(
   `include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_DQ, SDRAM2_A, SDRAM2_BA, SDRAM2_CLK, SDRAM2_nWE, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nCS} = 'Z;
`endif

`ifdef MISTER_FB
assign FB_EN = 0;
assign FB_FORMAT = 0;
assign FB_WIDTH = 0;
assign FB_HEIGHT = 0;
assign FB_BASE = 0;
assign FB_STRIDE = 0;
assign FB_FORCE_BLANK = 0;
`ifdef MISTER_FB_PALETTE
assign FB_PAL_CLK = 0;
assign FB_PAL_ADDR = 0;
assign FB_PAL_DOUT = 0;
assign FB_PAL_WR = 0;
`endif
`endif

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign LED_DISK = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v"
localparam CONF_STR =
{
   "GameOfLife;;",
   "-;",
   "F1,MEM,Load board;",
   "-;",
   "O[4],HighLife,Off,On;",
   "O[3],Running,Yes,No;",
   "O[2],Seed,Off,On;",
   "O[1],Aspect Ratio,16:9,4:3;",
   "-;",
   "T[0],Reset;",
   "v,1;",
   "V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_video;
wire clk_sys = clk_video;

pll pll (
   .refclk(CLK_50M),
   .rst(1'b0),
   .outclk_0(clk_video),
   .reconfig_to_pll(64'd0),
   .reconfig_from_pll()
);

assign CLK_VIDEO = clk_video;
assign CE_PIXEL  = 1'b1;

////////////////////  HPS CONNECTION  //////////////////////

wire [127:0] status;

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_index;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;

wire  [1:0] buttons;
wire        forced_scandoubler;
wire        reset = RESET | status[0] | buttons[1];

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
   .clk_sys(clk_sys),
   .HPS_BUS(HPS_BUS),
   .EXT_BUS(),
   .gamma_bus(),
   .buttons(buttons),
   .status(status),
   .status_in(128'd0),
   .status_set(1'b0),
   .status_menumask(16'd0),
   .forced_scandoubler(forced_scandoubler),
   .video_rotated(1'b0),
   .new_vmode(1'b0),
   .ps2_kbd_led_status(3'd0),
   .ps2_kbd_led_use(3'd0),

   .ioctl_download(ioctl_download),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .ioctl_index(ioctl_index),
   .ioctl_upload_req(1'b0),
   .ioctl_upload_index(8'd0),
   .ioctl_din(8'd0),
   .ioctl_wait(ioctl_wait),

   .info_req(1'b0),
   .info(8'd0)
);

assign LED_USER = ioctl_download;

////////////////////  GAME OF LIFE / VIDEO  //////////////////////

assign VIDEO_ARX = status[1] ? 13'd4 : 13'd16;
assign VIDEO_ARY = status[1] ? 13'd3 : 13'd9;

reg output_pixel;
reg r1p1;
reg r1p2;
reg r2p1;
reg r2p2;
reg r3p1;
reg r3p2;
reg sync_wait;

wire pixel_out_row1;
wire pixel_out_row2;
wire pixel_out_fifo;

reg [6:0] repeat_cnt;

wire board_load_wait = repeat_cnt > 0;
wire core_active = ~reset;
wire conway_enable = core_active & (~ioctl_download) & (~sync_wait);
wire row_enable = core_active & (ioctl_download | conway_enable);

assign ioctl_wait = ioctl_wr | board_load_wait;

always @(posedge clk_sys) begin
   repeat_cnt <= board_load_wait ? repeat_cnt - 1'b1 : 0;

   if (reset) begin
      repeat_cnt <= 0;
      sync_wait <= 1'b0;
   end
   else begin
      if (ioctl_download && ioctl_wr && !board_load_wait) begin
         repeat_cnt <= ioctl_dout[6:0];
      end

      sync_wait <= ioctl_download | (sync_wait & |{hc, vc});
   end
end

/* If uploading new seed state, switch the shift register to the HPS/video
   clock instead of the gated Conway clock. Input feed is switched to data
   received.
*/
localparam [21:0] INITIAL_RING_START_ADDR = 22'd1662;

ring #(
   .START_ADDR(INITIAL_RING_START_ADDR)
) fb_shift_reg (
   .clock(clk_sys),
   .reset(reset),
   .enable(core_active & (ioctl_download ? board_load_wait | ioctl_wr : ~sync_wait)),
   .write_delay(~ioctl_download),
   .shiftin(ioctl_download ? ioctl_dout[7] : output_pixel),
   .shiftout(pixel_out_fifo),
   .status(status)
);

row row1 (
   .clock(clk_video),
   .enable(row_enable),
   .shiftin(r2p1),
   .shiftout(pixel_out_row1)
);

row row2 (
   .clock(clk_video),
   .enable(row_enable),
   .shiftin(status[2] ? random_data[0] : r3p1),
   .shiftout(pixel_out_row2)
);

wire [3:0] neighbor_count_no_fifo_now = r1p1 + r1p2 + pixel_out_row1 + r2p1 + pixel_out_row2 + r3p1 + r3p2;

reg [3:0] neighbor_count_no_fifo;
reg       center_pixel;
reg       fifo_pixel;

wire      life_next_without_fifo = (neighbor_count_no_fifo == 4'd3) || (center_pixel && (neighbor_count_no_fifo == 4'd2));
wire      life_next_with_fifo = (neighbor_count_no_fifo == 4'd2) || (center_pixel && (neighbor_count_no_fifo == 4'd1));
wire      highlife_without_fifo = !center_pixel && (neighbor_count_no_fifo == 4'd6);
wire      highlife_with_fifo = !center_pixel && (neighbor_count_no_fifo == 4'd5);
wire      next_without_fifo = status[3] ? center_pixel : (life_next_without_fifo || (status[4] && highlife_without_fifo));
wire      next_with_fifo = status[3] ? center_pixel : (life_next_with_fifo || (status[4] && highlife_with_fifo));
wire      rule_next = fifo_pixel ? next_with_fifo : next_without_fifo;
wire      next_pixel = status[2] ? random_data[0] : rule_next;

always @(posedge clk_video) begin
   if (reset) begin
      neighbor_count_no_fifo <= 4'd0;
      center_pixel <= 1'b0;
      fifo_pixel <= 1'b0;
   end
   else if (conway_enable) begin
      neighbor_count_no_fifo <= neighbor_count_no_fifo_now;
      center_pixel <= r2p2;
      fifo_pixel <= pixel_out_fifo;
   end
end

/* One large shift register and two row-sized ones enable neighbor counting for one cell each clock. */
always @(posedge clk_video) begin
   if (reset) begin
      r1p1 <= 1'b0;
      r1p2 <= 1'b0;
      r2p1 <= 1'b0;
      r2p2 <= 1'b0;
      r3p1 <= 1'b0;
      r3p2 <= 1'b0;
      output_pixel <= 1'b0;
      fb_pixel <= 8'd0;
   end
   else if (conway_enable) begin
      r1p1 <= r1p2;
      r1p2 <= pixel_out_row1;
      r2p1 <= r2p2;
      r2p2 <= pixel_out_row2;
      r3p1 <= r3p2;
      r3p2 <= pixel_out_fifo;

      output_pixel <= next_pixel;

      /* Monochrome output: live pixels at max brightness, dead pixels at min. */
      fb_pixel <= {8{next_pixel}};
   end
end

//////////////////////////////////////////////////////////////////////
// Video
//////////////////////////////////////////////////////////////////////

reg [11:0] hc;
reg [11:0] vc;
reg  [7:0] fb_pixel;
reg        vga_hs;
reg        vga_vs;

assign VGA_G = fb_pixel;
assign VGA_R = fb_pixel;
assign VGA_B = fb_pixel;
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;
assign VGA_DE = (hc < 12'd1920 && vc < 12'd1080);

wire [30:0] random_data;

random lfsr(
   .clock(clk_video),
   .lfsr(random_data)
);

/* 1080p60: 2200 x 1125 total pixels at 148.5 MHz. */
always @(posedge clk_video) begin
   if (reset) begin
      hc <= 12'd0;
      vc <= 12'd0;
      vga_hs <= 1'b0;
      vga_vs <= 1'b0;
   end
   else begin
      hc <= hc + 1'd1;

      if (hc == 12'd2199) begin
         hc <= 12'd0;
         vc <= (vc == 12'd1124) ? 12'd0 : vc + 1'd1;
      end

      if (hc == 12'd2007) vga_hs <= 1'b1;
      if (hc == 12'd2051) vga_hs <= 1'b0;
      if (vc == 12'd1084) vga_vs <= 1'b1;
      if (vc == 12'd1089) vga_vs <= 1'b0;
   end
end

endmodule
