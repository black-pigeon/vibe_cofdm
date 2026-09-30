function run_compact_tests()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
c=cofdm.receiver_config(cofdm.config(),'compact'); code=cofdm.ldpc_code();
cofdm.seed_rng(20260928);
% Near-full CP support: strongest path is 31 samples after first arrival.
score=1e-5*ones(193,1); score(100)=1; score(69)=0.65^2;
[first,info]=cofdm.choose_fft_window(score,1,100,c);
assert(first>=68 && first<=69 && info.offsetFromPeak<=-31);
% Flat channel should stay inside its CP, without choosing the peak too late.
score=1e-5*ones(193,1); score(100)=1;
first=cofdm.choose_fft_window(score,1,100,c);
assert(first>=68 && first<=100);
fprintf('PASS CP window bounds for known path-energy fixtures\n');
% FIR has deterministic smoothing bias: verify its analytical interior
% response, including the worst CP endpoints; do not pretend it is unbiased.
interior=abs(c.active)>=4 & abs(c.active)<=97;
for delay=[0 16 31]
    H=exp(-1j*2*pi*c.active*delay/c.nfft);
    [estimate,variance]=cofdm.estimate_channel(H,0,c);
    gain=cos(pi*(delay-c.smoothingCenterDelay)/c.nfft)^6;
    assert(max(abs(estimate(interior)-gain*H(interior)))<1e-12);
    assert(all(isfinite(estimate)) && all(variance>=0));
end
fprintf('PASS FIR analytical response, DC and guard handling\n');
% Monte Carlo independently checks stated noise propagation at DC/edges too.
sumError=zeros(numel(c.active),1); nv=0.1;
for k=1:300
    raw=sqrt(nv/2)*(randn(numel(c.active),1)+1j*randn(numel(c.active),1));
    [estimate,variance]=cofdm.estimate_channel(raw,nv,c);
    sumError=sumError+abs(estimate).^2;
end
assert(abs(sum(sumError/300)/sum(variance)-1)<0.08);
fprintf('PASS FIR noise variance: empirical/predicted %.3f\n',sum(sumError/300)/sum(variance));
H=ones(numel(c.active),1);
for phase=[-3.05 3.05]
    for slope=[-0.008 0 0.006]
        Y=H.*exp(1j*(phase+slope*c.active));
        Y(c.pilotInActive)=Y(c.pilotInActive).*cofdm.pilot_values(c,1);
        [~,a,b]=cofdm.track_pilots(Y,H,1e-5,zeros(size(H)),c,1);
        assert(abs(angle(exp(1j*(a-phase))))<0.02 && abs(b-slope)<8e-4);
    end
end
fprintf('PASS nine-candidate circular tracking across phase branch\n');
channels={struct('delays',0,'gains',1,'snrDb',Inf,'cfoHz',0,'offset',0), ...
    struct('delays',[0 10 23],'gains',[0.25 1 0.3j],'snrDb',24,'cfoHz',135e3,'offset',37), ...
    struct('delays',[0 31],'gains',[0.65 1],'snrDb',24,'cfoHz',-220e3,'offset',83), ...
    struct('delays',[0 2 5 9 14 18 23 28],'gains',[0.5 0.2j -0.35 0.25 1 0.3j -0.2 0.25], ...
        'snrDb',24,'cfoHz',65e3,'offset',11)};
for q=[false true]
    c.quantizedDecoder=q;
    for k=1:numel(channels)
        payload=uint8(randi([0 255],c.payloadBytes,1));
        wave=cofdm.tx(payload,k,c,code);
        [y,truth]=cofdm.channel(wave,c,channels{k}); r=cofdm.rx(y,c,code);
        assert(r.ok && isequal(payload,r.payload));
        offset=r.sync.ltfUsefulStart-(truth.frameStart+c.stfPeriod*c.stfRepeats+c.ncp);
        assert(offset>=max(channels{k}.delays)-c.ncp && offset<=min(channels{k}.delays));
        fprintf('PASS compact channel %d quantized=%d FFT offset=%d\n',k,q,offset);
    end
end
for y={zeros(c.slotSamples,1),randn(c.slotSamples,1)+1j*randn(c.slotSamples,1), ...
        exp(1j*2*pi*0.031*(0:c.slotSamples-1).'),zeros(100,1)}
    s=cofdm.synchronize(y{1},c); assert(~s.ok);
end
fprintf('PASS compact silence/noise/tone/truncation rejection\n');
fprintf('All compact receiver tests passed.\n');
end
