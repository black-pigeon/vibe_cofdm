module tb_quadrant;
 reg signed [39:0] re,im; wire [1:0] q;
 cofdm_quadrant_select dut(re,im,q);
 task t; input integer a,b; input [1:0] e; begin re=a;im=b; #1; if(q!==e) $fatal(1,"q %0d %0d got %0d",a,b,q); end endtask
 initial begin t(10,2,0);t(-10,2,2);t(2,10,1);t(2,-10,3);$display("PASS quadrant");$finish;end
endmodule
