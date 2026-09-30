function s = synchronize(y,c)
% Acquisition has no access to channel truth or transmitted payload.
% The event fields are intentionally populated even on a failed capture.  They
% make the estimator usable as a MATLAB regression oracle for the RTL capture
% controller (STF hit -> LTF hit -> final lock), rather than exposing only the
% final boolean result.
s=struct('ok',false,'reason','STF not found', ...
    'stfDetected',false,'stfStart',NaN,'stfMetric',0, ...
    'ltfDetected',false,'ltfPeakStart',NaN,'peak',0, ...
    'coarseCfoHz',NaN,'fineCfoHz',NaN,'cfoHz',NaN, ...
    'frameStart',NaN,'ltfUsefulStart',NaN,'window',NaN, ...
    'corrected',[]);
y=y(:);
L=c.stfPeriod; W=4*L;
required=c.frameSamples;
if c.variablePayload
    required=c.stfPeriod*c.stfRepeats+(2+c.nHeaderSymbols)*(c.nfft+c.ncp);
end
if numel(y)<required, s.reason='capture too short'; return; end
v=y(1:end-L); w=y(1+L:end);
P=conv(conj(v).*w,ones(W,1),'valid');
E1=conv(abs(v).^2,ones(W,1),'valid');
E2=conv(abs(w).^2,ones(W,1),'valid');
metric=abs(P).^2./max(E1.*E2,1e-30);
gate=metric>c.syncThreshold & E1>0.1*max(E1);
run=conv(double(gate),ones(c.syncMinRun,1),'valid');
start=find(run>=c.syncMinRun,1);
if isempty(start), return; end
s.stfDetected=true; s.stfStart=start; s.stfMetric=metric(start);
s.coarseCfoHz=angle(sum(P(start:start+c.syncMinRun-1)))*c.fs/(2*pi*L);
n=(0:numel(y)-1).';
v=y.*exp(-1j*2*pi*s.coarseCfoHz*n/c.fs);
t=cofdm.training(c); ref=t.ltfTime(:,1);
nominal=start+numel(t.stf)+c.ncp;
lo=max(1,nominal-96); hi=min(numel(y)-c.nfft+1,nominal+96);
score=zeros(hi-lo+1,1);
for k=lo:hi
    a=v(k:k+c.nfft-1);
    score(k-lo+1)=abs(ref'*a)^2/max(sum(abs(ref).^2)*sum(abs(a).^2),1e-30);
end
[s.peak,j]=max(score); first=lo+j-1;
if s.peak<c.syncPeakThreshold, s.reason='LTF correlation too weak'; return; end
s.ltfDetected=true; s.ltfPeakStart=first;
s.frameStart=first-c.ncp-numel(t.stf);
if s.frameStart<1 || s.frameStart+required-1>numel(y)
    s.reason='frame outside capture'; return;
end
if strcmp(c.fftWindowMode,'energy')
    [first,s.window]=cofdm.choose_fft_window(score,lo,j,c);
else
    assert(strcmp(c.fftWindowMode,'peak'));
end
second=first+c.nfft+c.ncp;
A=fft(v(first:first+c.nfft-1))/sqrt(c.nfft);
B=fft(v(second:second+c.nfft-1))/sqrt(c.nfft);
H1=A(c.activeBins)./t.ltf(:,1); H2=B(c.activeBins)./t.ltf(:,2);
s.fineCfoHz=angle(sum(H2.*conj(H1)))*c.fs/(2*pi*(c.nfft+c.ncp));
s.cfoHz=s.coarseCfoHz+s.fineCfoHz;
s.corrected=y.*exp(-1j*2*pi*s.cfoHz*n/c.fs);
s.ltfUsefulStart=first; s.ok=true; s.reason='';
end
