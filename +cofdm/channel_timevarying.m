function [y,truth] = channel_timevarying(x,c,p)
% Controlled path-wise phase ramps; not a standardized fading / SFO model.
assert(numel(p.delays)==numel(p.gains) && numel(p.gains)==numel(p.dopplerHz));
assert(all(p.delays>=0 & p.delays==floor(p.delays)));
assert(numel(unique(p.delays))==numel(p.delays));
h=zeros(max(p.delays)+1,1); h(p.delays+1)=p.gains; h=h/norm(h);
v=zeros(numel(x)+max(p.delays),1);
for k=1:numel(p.delays)
    ix=p.delays(k)+(1:numel(x)).';
    phase=exp(2j*pi*p.dopplerHz(k)*(ix-1)/c.fs);
    v(ix)=v(ix)+h(p.delays(k)+1)*x(:).*phase;
end
active=c.frameSamples; if c.variablePayload, active=numel(x)-c.guardSamples; end
power=mean(abs(v(1:active)).^2);
y=[zeros(p.offset,1);v;zeros(64,1)];
y=y.*exp(2j*pi*p.cfoHz*(0:numel(y)-1).'/c.fs);
nv=power*10^(-p.snrDb/10);
y=y+sqrt(nv/2)*(randn(size(y))+1j*randn(size(y)));
truth=struct('noiseVariance',nv,'h',h,'cfoHz',p.cfoHz, ...
    'frameStart',p.offset+1,'dopplerHz',p.dopplerHz);
end
