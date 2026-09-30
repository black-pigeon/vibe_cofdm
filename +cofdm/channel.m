function [y,truth] = channel(x,c,p)
% Integer-delay static multipath + CFO + burst offset + AWGN.
% SNR is average RX ACTIVE FRAME complex-sample SNR, not Eb/N0.
assert(numel(p.delays)==numel(p.gains));
assert(all(p.delays>=0 & p.delays==floor(p.delays)));
h=zeros(max(p.delays)+1,1);
for k=1:numel(p.delays), h(p.delays(k)+1)=h(p.delays(k)+1)+p.gains(k); end
h=h/norm(h);
v=conv(x,h);
frameSamples=c.frameSamples;
if c.variablePayload, frameSamples=numel(x)-c.guardSamples; end
power=mean(abs(v(1:frameSamples)).^2);
y=[zeros(p.offset,1);v;zeros(64,1)];
y=y.*exp(1j*2*pi*p.cfoHz*(0:numel(y)-1).'/c.fs);
nv=power*10^(-p.snrDb/10);
y=y+sqrt(nv/2)*(randn(size(y))+1j*randn(size(y)));
truth.noiseVariance=nv; truth.h=h; truth.cfoHz=p.cfoHz;
truth.frameStart=p.offset+1;
end
