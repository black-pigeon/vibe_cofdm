# A failed $fatal/$finish must never look like a passing regression.
run all
set f [open rtl_status.txt w]
puts $f [get_value -radix unsigned /tb_phy_rx_v2_payload_top/test_pass]
close $f
quit
