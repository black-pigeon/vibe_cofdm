function p = pilot_values(c,symbolIndex)
% Deterministic time-varying BPSK; index includes headers and midambles.
b=cofdm.prbs(numel(c.pilots)*symbolIndex,53);
p=1-2*double(b(end-numel(c.pilots)+1:end));
end
