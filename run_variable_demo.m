function results = run_variable_demo(payloadBytes)
% Opaque variable PHY service unit: MAC/IP interpretation belongs above PHY.
if nargin<1, payloadBytes=1500; end
root=fileparts(mfilename('fullpath')); addpath(root);
txConfig=cofdm.config_v2('compact'); code=cofdm.ldpc_code();
cofdm.seed_rng(20261007);
payload=uint8(randi([0 255],payloadBytes,1));
[wave,meta]=cofdm.tx(payload,0,txConfig,code);
p=struct('snrDb',20,'cfoHz',135e3,'offset',37, ...
    'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
y=cofdm.channel(wave,txConfig,p);
% This receiver has no copy of the TX payload length, seed or MID setting.
rxConfig=cofdm.config_v2('compact'); r=cofdm.rx(y,rxConfig,code);
assert(r.ok && isequal(payload,r.payload));
results=struct('tx',meta,'rx',r,'channel',p);
c=meta.config;
fprintf('v2: %d bytes, 1 BPSK header, %d LDPC words, %d data + %d MID\n', ...
    c.payloadBytes,c.nCodewords,c.nDataSymbols,c.nMidambles);
fprintf('Slot %.3f us, ideal PHY goodput %.3f Mbps, CRC/payload matched\n', ...
    c.slotSamples/c.fs*1e6,c.netRate/1e6);
end
