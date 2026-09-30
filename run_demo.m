function results = run_demo(mode)
% RUN_DEMO Run in MATLAB or GNU Octave with this directory on the path.
if nargin<1, mode='baseline'; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.receiver_config(cofdm.config(),mode);
code=cofdm.ldpc_code(); cofdm.seed_rng(c.seed);
payload=uint8(randi([0 255],c.payloadBytes,1));
[wave,meta]=cofdm.tx(payload,7,c,code);
p=struct('snrDb',22,'cfoHz',135e3,'offset',37, ...
    'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
[y,truth]=cofdm.channel(wave,c,p);
r=cofdm.rx(y,c,code);
results=struct('receiverMode',mode,'config',c,'channel',p,'tx',meta,'rx',r);
fprintf('Receiver mode: %s\n',mode);
fprintf('Fs %.2f MHz, FFT %d, CP %d, active/data/pilot %d/%d/%d\n', ...
    c.fs/1e6,c.nfft,c.ncp,numel(c.active),numel(c.data),numel(c.pilots));
fprintf('Payload %d bytes, slot %.3f us, ideal net %.3f Mbit/s\n', ...
    c.payloadBytes,c.slotSamples/c.fs*1e6,c.netRate/1e6);
fprintf('Discrete-sample PAPR %.2f dB (not oversampled RF PAPR)\n',meta.paprDb);
fprintf('RX success %d; %s\n',r.ok,r.reason);
if r.sync.ok
    fprintf('Start true/estimated %d/%d; CFO true/estimated %.1f/%.1f Hz\n', ...
        truth.frameStart,r.sync.frameStart,p.cfoHz,r.sync.cfoHz);
end
assert(r.ok && isequal(r.payload,payload),'Demo did not recover payload');
fprintf('CRC and payload match; mean/max LDPC iterations %.2f/%d\n', ...
    mean(r.iterations),max(r.iterations));
end
