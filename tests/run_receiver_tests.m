function run_receiver_tests()
% Independent estimator/phase checks and both receivers' end-to-end tests.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
c=cofdm.receiver_config(cofdm.config(),'proposed'); code=cofdm.ldpc_code();
cofdm.seed_rng(20260925);
% Paths on both sides of strongest-path timing; unobserved bins are excluded.
F=exp(-1j*2*pi/c.nfft*(c.active*[-23 0 29]));
H=F*[0.15*exp(0.4j);1;0.2*exp(-0.7j)];
[hat,v]=cofdm.estimate_channel(H,0,c);
assert(norm(hat-H)/norm(H)<1e-6 && all(v>=0));
rawError=0; denoisedError=0;
for k=1:100
    raw=H+sqrt(0.1/2)*(randn(size(H))+1j*randn(size(H)));
    [hat,v]=cofdm.estimate_channel(raw,0.1,c);
    rawError=rawError+norm(raw-H)^2;
    denoisedError=denoisedError+norm(hat-H)^2;
    assert(all(isfinite(hat)) && all(v>=0 & v<=0.1+eps));
end
assert(denoisedError<0.6*rawError);
fprintf('PASS channel estimator: paired MSE ratio %.3f\n',denoisedError/rawError);
% Known phase crossing the +/-pi branch, and nonzero phase slope.
Y=H.*exp(1j*(3.05+0.006*c.active));
Y(c.pilotInActive)=Y(c.pilotInActive).*cofdm.pilot_values(c,1);
[~,phi,slope]=cofdm.track_pilots(Y,H,1e-5,zeros(size(H)),c,1);
assert(abs(angle(exp(1j*(phi-3.05))))<0.02 && abs(slope-0.006)<5e-4);
fprintf('PASS circular phase: intercept error %.5g slope error %.5g\n', ...
    angle(exp(1j*(phi-3.05))),slope-0.006);
for quantized=[false true]
    c.quantizedDecoder=quantized;
    payload=uint8(randi([0 255],c.payloadBytes,1));
    wave=cofdm.tx(payload,27,c,code);
    p=struct('snrDb',20,'cfoHz',-220e3,'offset',37,'delays',[0 3 9], ...
        'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
    y=cofdm.channel(wave,c,p); r=cofdm.rx(y,c,code);
    assert(r.ok && isequal(r.payload,payload));
    fprintf('PASS proposed end-to-end quantized=%d\n',quantized);
end
fprintf('All receiver enhancement tests passed.\n');
end
