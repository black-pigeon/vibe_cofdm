function t = training(c)
% Frequency-domain known values; useful-symbol templates have no CP.
n=(0:c.zcLength-1).';
for k=1:2
    z=exp(-1j*pi*c.zcRoots(k)*n.*(n+1)/c.zcLength);
    z((c.zcLength+1)/2)=[];
    t.ltf(:,k)=z;
    f=zeros(c.nfft,1); f(c.activeBins)=z;
    t.ltfTime(:,k)=ifft(f)*sqrt(c.nfft)*c.txScale;
end
% 12 tones on multiples of 16 => exact 16-sample repetition.
tones=[-96:16:-16 16:16:96].';
f=zeros(c.nfft,1);
f(mod(tones,c.nfft)+1)=1-2*double(cofdm.prbs(numel(tones),37));
x=ifft(f)*sqrt(c.nfft);
x=x/sqrt(mean(abs(x).^2))*sqrt(numel(c.active)/c.nfft)*c.txScale;
t.stf=repmat(x(1:c.stfPeriod),c.stfRepeats,1);
end
