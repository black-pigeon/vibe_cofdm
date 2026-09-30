function run_variable_tests()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
c=cofdm.config_v2('compact'); code=cofdm.ldpc_code(); cofdm.seed_rng(20261008);
% Independent known impulse convention for (171,133), newest bit at MSB.
expected=logical([1 1 1 0 1 1 1 1 0 0 0 1 1 1].');
assert(isequal(cofdm.header_conv_encode(true),expected));
for k=1:30
    bits=logical(randi([0 1],48,1)); cw=cofdm.header_conv_encode(bits);
    soft=6*(1-2*double(cw)); weak=randperm(108,3); soft(weak)=-0.1*soft(weak);
    [decoded,ok]=cofdm.header_viterbi(soft); assert(ok && isequal(bits,decoded));
end
fprintf('PASS header trellis impulse and 30 soft-error Viterbi cases\n');
for mid=0:2
    for seed=[1 93 127]
        t=c; t.midambleCode=mid; t.scramblerSeed=seed;
        bits=cofdm.header_v2('encode',1500,t);
        out=cofdm.header_v2('decode',10*(1-2*double(bits)),c);
        assert(out.ok && out.config.payloadBytes==1500 && out.config.scramblerSeed==seed);
        assert(out.config.midambleCode==mid);
    end
end
% All illegal combinations below have a VALID CRC and convolutional code.
fields=[2 0 1500 93 0 0]; invalids=[1 1;2 1;3 0;3 2049;3 4095;4 0;5 3;6 1];
for k=1:size(invalids,1)
    bad=fields; bad(invalids(k,1))=invalids(k,2);
    out=cofdm.header_v2('decode',field_llr(bad,c,false),c);
    assert(~out.ok && contains(out.reason,'unsupported'));
end
out=cofdm.header_v2('decode',field_llr(fields,c,true),c); assert(~out.ok);
out=cofdm.header_v2('decode',zeros(192,1),c); assert(~out.ok);
out=cofdm.header_v2('decode',NaN(192,1),c); assert(~out.ok);
out=cofdm.header_v2('decode',zeros(191,1),c); assert(~out.ok);
restricted=c; restricted.maxPayloadBytes=512;
out=cofdm.header_v2('decode',field_llr(fields,c,false),restricted); assert(~out.ok);
fprintf('PASS header CRC and bounded version/MCS/length/seed/MID/reserved rejection\n');
% Exhaustive layout accounting, including all padding boundaries.
for n=1:2048
    f=cofdm.frame_layout(c,n);
    assert(f.infoPadBits>=0 && f.infoPadBits<324 && f.codedPadBits>=0 && f.codedPadBits<384);
    assert(f.nCodewords*324==8*n+32+f.infoPadBits);
    assert(f.nDataSymbols*384==f.nCodewords*648+f.codedPadBits);
end
for n=[0 2049 -1 1.5 NaN Inf]
    rejected=false;
    try
        cofdm.frame_layout(c,n);
    catch
        rejected=true;
    end
    assert(rejected);
end
fprintf('PASS all 2048 legal lengths and invalid layout rejection\n');
lengths=[1 36 37 76 77 80 81 319 320 644 645 1499 1500 1514 1518 1536 2048];
for k=1:numel(lengths)
    n=lengths(k); t=c; t.midambleCode=mod(k,3); t.scramblerSeed=mod(17*k,127)+1;
    payload=uint8(randi([0 255],n,1)); [wave,meta]=cofdm.tx(payload,0,t,code);
    p=struct('snrDb',24,'cfoHz',(-1)^k*135e3,'offset',37, ...
        'delays',[0 3 9],'gains',[1 0.25j -0.12]);
    y=cofdm.channel(wave,t,p);
    % Reuse a pristine RX config for every arbitrary-sized frame.
    rc=c; rc.quantizedDecoder=mod(k,2)==0;
    r=cofdm.rx(y,rc,code);
    assert(r.ok && isequal(payload,r.payload),sprintf('v2 failed at %d bytes: %s',n,r.reason));
    assert(numel(wave)==meta.config.slotSamples && r.frameConfig.payloadBytes==n);
    assert(r.frameConfig.scramblerSeed==t.scramblerSeed && r.frameConfig.midambleCode==t.midambleCode);
    assert(numel(r.codedLLR)==meta.config.nCodewords*648);
    fprintf('PASS variable %4d bytes words=%2d data=%2d MID=%2d\n', ...
        n,meta.config.nCodewords,meta.config.nDataSymbols,meta.config.nMidambles);
end
% Damage only data after a valid header; acquisition and header still pass.
t=c; payload=uint8(randi([0 255],1500,1)); wave=cofdm.tx(payload,0,t,code);
r=cofdm.rx(wave(1:end-128),c,code);
assert(~r.ok && r.sync.ok && r.header.ok && strcmp(r.reason,'v2 payload truncated'));
headerStart=160+2*288+1; corrupt=wave; corrupt(headerStart:headerStart+287)=0;
r=cofdm.rx(corrupt,c,code); assert(~r.ok && isempty(r.payload));
corrupt=wave; corrupt(1025:end)=0;
r=cofdm.rx(corrupt,c,code); assert(~r.ok && r.sync.ok && r.header.ok);
% Validly encoded forged oversized header must not reach payload allocation.
corrupt=wave; active=zeros(200,1); active(c.pilotInActive)=cofdm.pilot_values(c,1);
bad=fields; bad(3)=4095; active(c.dataInActive)=sign(field_llr(bad,c,false));
corrupt(headerStart:headerStart+287)=cofdm.ofdm_symbol(c,active);
r=cofdm.rx(corrupt,c,code); assert(~r.ok && r.sync.ok && ~r.header.ok && isempty(r.payload));
fprintf('PASS truncation, destroyed header/data and forged length end-to-end rejection\n');
fprintf('All variable-length PHY tests passed. v2 is experimental, not a MAC/IP implementation.\n');
end
function llr=field_llr(fields,c,breakCrc)
widths=[4 4 12 7 2 3]; bits=false(0,1);
for k=1:6
    % Explicit division-based field packing independent of header_v2 encoder.
    x=fields(k); part=false(widths(k),1);
    for j=widths(k):-1:1, part(j)=mod(x,2); x=floor(x/2); end
    bits=[bits;part]; %#ok<AGROW>
end
bits=cofdm.crc(bits,16); if breakCrc, bits(48)=~bits(48); end
cw=cofdm.header_conv_encode(bits);
mapped=xor([cw;false(84,1)],cofdm.prbs(192,c.headerScramblerSeed));
llr=10*(1-2*double(mapped));
end
