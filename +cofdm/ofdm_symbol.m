function x = ofdm_symbol(c,activeValues)
f=zeros(c.nfft,1); f(c.activeBins)=activeValues;
v=ifft(f)*sqrt(c.nfft)*c.txScale;
x=[v(end-c.ncp+1:end);v];
end
