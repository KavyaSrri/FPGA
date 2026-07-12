module timing_waveform(
    input clk,
    input sdout,
    output sclk,
    output sdin,
    output sync_n,
    output ldac_n,
    output rst
);

wire [11:0] counter_out;
wire en_c, en_w;
wire ready, frame_done;

assign rst = 1'b1;
wire load_c = 1'b0;
wire up_down = 1'b1;
wire [11:0] data_in_c = 12'd0;

counter u_counter (
    .clk(clk),
    .en_c(en_c),
    .LOAD_C(load_c),
    .up_down(up_down),
    .DATA_IN_C(data_in_c),
    .count(counter_out)
);

waveform u_waveform (
    .clk(clk),
    .sdout(sdout),
 //   .en_w(en_w),
    .data(counter_out),
    .sdin(sdin),
    .sync_n(sync_n),
    .sclk(sclk),
    .ready(ready),
    .ldac_n(ldac_n),
    .frame_done(frame_done)
);

handshake u_handshake (
    .clk(clk),
    .ready(ready),
    .frame_done(frame_done),
    .en_c(en_c)
);

endmodule

// Counter module
module counter(
    input clk, en_c, LOAD_C, up_down,
    input [11:0] DATA_IN_C,
    output reg [11:0] count
);
    initial count = 12'd0;

    always @(posedge clk) begin
        if (en_c) begin
            if (LOAD_C)
                count <= DATA_IN_C;
            else begin
                if (up_down)
                    count <= count + 1;
                else
                    count <= count - 1;
            end
        end
    end
endmodule

// Handshake module
module handshake(
    input clk, ready, frame_done,
    output reg en_c = 0
);
    reg [1:0] state = 2'b00;
    localparam IDLE=0, ENABLE=1, WAIT_DONE=2;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                if (ready==1) begin
                    en_c <= 1;
                    state <= ENABLE;
                end
            end
            ENABLE: begin
                en_c <= 0;
                state <= WAIT_DONE;
            end
            WAIT_DONE: begin
                if (frame_done)
                    state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
endmodule

// waveform module 
module waveform(
    input clk,
    input sdout,
    input [11:0] data,
    output reg sdin,
    output reg sync_n,
    output reg sclk,
    output reg ready,
    output ldac_n,
    output reg frame_done
);

assign ldac_n = 0;
reg en_w=1;

reg clk_gen = 0;
reg [23:0] clk_div = 0;
parameter N = 12500;

always @(posedge clk) begin
    if (clk_div >= N-1) begin
        clk_div <= 0;
        clk_gen <= ~clk_gen;
    end else begin
        clk_div <= clk_div + 1;
    end
end

reg [1:0] state = 2'b00;
parameter IDLE=2'b00, WAIT=2'b01, SYNC_LOW=2'b10;

reg [29:0] count = 0;
reg [4:0] bit_index = 0;
reg [4:0] dout_bit_index = 5'd0;

reg [3:0] command = 4'b1001;
reg [3:0] dac_select = 4'b0001;

reg [23:0] ip_shift_reg;
reg [23:0] dout_shift_reg;
reg [23:0] received_data;
reg first_frame_sent = 0;

reg clk_gen_d = 0;
wire sclk_rise_edge = (clk_gen == 1 && clk_gen_d == 0);
wire sclk_fall_edge = (clk_gen == 0 && clk_gen_d == 1);

always @(posedge clk) begin
    clk_gen_d <= clk_gen;
end

always @(posedge clk) begin
    if (en_w) begin
        case (state)
            IDLE: begin
                count <= count + 1;
                sync_n <= 0;
                dout_bit_index <= 0;
                if (count == 30'd31249) begin
                    count <= 0;
                    state <= WAIT;
                end
                bit_index <= 0;
            end

            WAIT: begin
                count <= count + 1;
                sync_n <= 1;
                frame_done <= 0;
                if (count == 30'd184999) begin
                    count <= 0;
                    ip_shift_reg <= {command, dac_select,data, 4'b0000};
                    state <= SYNC_LOW;
                end
            end

            SYNC_LOW: begin
                sync_n <= 0;
                sclk <= clk_gen;

                if (sclk_rise_edge) begin
                    sdin <= ip_shift_reg[23 - bit_index];
                end

                if (sclk_fall_edge) begin
                    if (bit_index < 23) begin
                        bit_index <= bit_index + 1;
                        ready <= 1;
                    end else begin
                        bit_index <= 0;
                        state <= WAIT;
                        if (!first_frame_sent)begin
                            first_frame_sent <= 1;
							   end
                        ready <= 0;
                        frame_done <= 1;
                    end
						  if(ready)begin
						     dout_shift_reg<={dout_shift_reg[22:0],sdout};
							  dout_bit_index<=dout_bit_index+1;
							  if(bit_index==23)begin
							     received_data<={dout_shift_reg[22:0],sdout};
								  dout_bit_index<=0;
								  ready<=0;
								  frame_done<=1;
							  end 
						  end 
                end
            end

            default: state <= IDLE;

        endcase
    end
end

endmodule

   
