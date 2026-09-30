function report = plan_budget()
% PLAN_BUDGET Hypothetical MCS/resource planning; only profile 1 implemented.
c=cofdm.config(); code=cofdm.ldpc_code();
names={'BPSK 1/2','QPSK 1/2','16QAM 1/2','16QAM 3/4','64QAM 2/3','64QAM 3/4'};
bits=[1 2 4 4 6 6]; rates=[1/2 1/2 1/2 3/4 2/3 3/4];
fclk=122.88e6; report=[];
fprintf('MCS (planning)      payload bytes     ideal Mbps    avg cycles/codeword incl header\n');
for k=1:numel(bits)
    nc=numel(c.data)*bits(k)*c.nDataSymbols/code.n;
    payload=(nc*code.n*rates(k)-32)/8;
    rate=payload*8*c.fs/c.slotSamples;
    budget=fclk*c.slotSamples/c.fs/(nc+1);
    fprintf('%-17s %8d          %8.3f             %8.1f\n',names{k},payload,rate/1e6,budget);
    report(k,:)=[bits(k),rates(k),nc,payload,rate,budget]; %#ok<AGROW>
end
fprintf('12 iterations, ideal two-pass NMS core cycles (excluding pipeline, I/O, syndrome):\n');
for P=[1 3 9 27]
    cy=2*code.baseEdges*ceil(code.z/P)*c.ldpcIterations;
    fprintf('%2d lanes: %5d cycles = %.2f us at 122.88 MHz\n',P,cy,cy/fclk*1e6);
end
end
