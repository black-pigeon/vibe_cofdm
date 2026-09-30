function [H,errorVariance,d] = fir_channel_fixed(raw,nv,c)
% Stage-quantized FIR reference, exact binary arithmetic in double.
% FFT/LS input generation and noise variance remain floating point.
assert(strcmp(c.channelEstimator,'fir7'));
assert(c.channelWordBits+c.coefficientWordBits+1<=53);
assert(c.channelAccumulatorBits+c.coefficientWordBits<=53);
assert(c.channelAccumulatorBits>=c.channelWordBits+6);
B=c.channelWordBits; F=c.channelFractionBits;
C=c.coefficientWordBits; G=c.coefficientFractionBits;
d=struct('saturations',0,'stageSaturations',zeros(1,5));
[raw,d.stageSaturations(1)]=cofdm.quantize_signed(raw,B,F);
rotation=cofdm.quantize_signed(exp(1j*2*pi*c.active*c.smoothingCenterDelay/c.nfft),C,G);
[centered,d.stageSaturations(2)]=cofdm.quantize_signed(raw.*rotation,B,F);
grid=(min(c.active):max(c.active)).'; idx=c.active-min(c.active)+1;
samples=zeros(size(grid)); valid=zeros(size(grid));
samples(idx)=centered; valid(idx)=1;
kernel=[1;6;15;20;15;6;1]; weight=conv(valid,kernel,'same');
numerator=conv(samples,kernel,'same');
[numerator,d.stageSaturations(3)]=cofdm.quantize_signed(numerator,c.channelAccumulatorBits,F);
reciprocal=cofdm.quantize_signed(1./max(weight,1),C,G);
[smooth,d.stageSaturations(4)]=cofdm.quantize_signed(numerator.*reciprocal,B,F);
[H,d.stageSaturations(5)]=cofdm.quantize_signed(smooth(idx).*conj(rotation),B,F);
% Return the same approximate noise model used by the float algorithm.
% This is not an integer variance/LLR implementation.
variance=nv*conv(valid,kernel.^2,'same')./max(weight.^2,1);
errorVariance=variance(idx);
d.saturations=sum(d.stageSaturations);
end
