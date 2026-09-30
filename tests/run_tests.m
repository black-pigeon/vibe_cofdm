function summary = run_tests()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
c=cofdm.config(); code=cofdm.ldpc_code(); cofdm.seed_rng(c.seed);
n=0;
assert(c.fs/c.nfft==60e3 && c.ncp/c.fs>2e-6);
assert(numel(c.data)==192 && numel(unique(c.interleaver))==384);
assert(c.nDataSymbols==27 && c.frameSamples==10528 && c.slotSamples==10560);
assert(c.payloadBytes==644 && code.edges==2376);
n=n+1;
b=cofdm.prbs(254,93); assert(isequal(b(1:127),b(128:254)) && any(b));
x=uint8([0;1;127;128;255]); assert(isequal(cofdm.bits_to_bytes(cofdm.bytes_to_bits(x)),x));
for w=[16 32]
    bits=logical(randi([0 1],123,1)); a=cofdm.crc(bits,w);
    assert(cofdm.crc(a,w,true)); a(9)=~a(9); assert(~cofdm.crc(a,w,true));
end
n=n+1;
% Encoder is also checked against an independent GF(2) parity solver.
u=logical(randi([0 1],code.k,1)); cw=cofdm.ldpc_encode(u,code);
rhs=mod(code.H(:,1:code.k)*double(u),2);
p=gf2_solve(full(code.H(:,code.k+1:end)),rhs);
assert(isequal(logical(p),cw(code.k+1:end)));
for k=1:10
    u=logical(randi([0 1],code.k,1)); cw=cofdm.ldpc_encode(u,code);
    llr=8*(1-2*double(cw));
    ix=randperm(code.n,5); llr(ix)=-llr(ix)*0.12;
    [uhat,ok]=cofdm.ldpc_decode(llr,code,c);
    assert(ok && isequal(u,uhat));
end
qc=c; qc.quantizedDecoder=true;
[uhat,ok,~,post]=cofdm.ldpc_decode(100*(1-2*double(cw)),code,qc);
assert(ok && isequal(u,uhat) && max(abs(post))<=63.75);
assert(max(abs(post*4-round(post*4)))<1e-12);
n=n+1;
t=cofdm.training(c);
assert(max(abs(t.stf(1:end-16)-t.stf(17:end)))<1e-12);
assert(abs(sum(conj(t.ltf(:,1)).*t.ltf(:,2)))/numel(c.active)<0.2);
n=n+1;
scenarios={...
    struct('name','noiseless','snrDb',Inf,'cfoHz',0,'offset',0,'delays',0,'gains',1), ...
    struct('name','AWGN+CFO','snrDb',20,'cfoHz',135e3,'offset',37,'delays',0,'gains',1), ...
    struct('name','multipath negative CFO','snrDb',22,'cfoHz',-220e3,'offset',83, ...
      'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]), ...
    struct('name','quantized decoder','snrDb',20,'cfoHz',65e3,'offset',11,'delays',0,'gains',1)};
for j=1:numel(scenarios)
    p=scenarios{j}; c.quantizedDecoder=(j==4);
    payload=uint8(randi([0 255],c.payloadBytes,1));
    [wave,meta]=cofdm.tx(payload,j,c,code);
    assert(numel(wave)==c.slotSamples && numel(meta.codedBits)==10368);
    [y,truth]=cofdm.channel(wave,c,p); r=cofdm.rx(y,c,code);
    assert(r.ok,['RX failed: ' p.name ': ' r.reason]);
    assert(isequal(payload,r.payload) && r.sequence==j);
    assert(abs(r.sync.cfoHz-p.cfoHz)<1500);
    assert(abs(r.sync.frameStart-truth.frameStart)<=1);
    fprintf('PASS %s CFO error %.1f Hz\n',p.name,r.sync.cfoHz-p.cfoHz);
    n=n+1;
end
% Negative acquisitions: silence, fixed seeded noise and truncated captures.
s=cofdm.synchronize(zeros(c.slotSamples,1),c); assert(~s.ok);
z=(randn(c.slotSamples,1)+1j*randn(c.slotSamples,1));
s=cofdm.synchronize(z,c); assert(~s.ok);
s=cofdm.synchronize(zeros(100,1),c); assert(~s.ok);
s=cofdm.synchronize(exp(1j*2*pi*0.031*(0:c.slotSamples-1).'),c); assert(~s.ok);
% Destroy header OFDM symbols, preserve acquisition training.
c.quantizedDecoder=false;
wave=cofdm.tx(payload,99,c,code);
firstHeader=c.stfPeriod*c.stfRepeats+2*(c.nfft+c.ncp)+1;
wave(firstHeader:firstHeader+c.nHeaderSymbols*(c.nfft+c.ncp)-1)=0;
r=cofdm.rx(wave,c,code); assert(~r.ok && r.sync.ok && isempty(r.payload));
n=n+1;
summary=struct('groupsPassed',n,'seed',c.seed);
fprintf('All %d test groups passed. This is functional validation, not a link qualification.\n',n);
end
function x=gf2_solve(A,b)
% Independent full Gaussian elimination, only used in the test oracle.
A=logical([A b]); N=size(A,1);
for k=1:N
    j=find(A(k:end,k),1)+k-1; assert(~isempty(j),'Parity matrix not full rank');
    A([k j],:)=A([j k],:);
    ix=find(A(:,k)); ix(ix==k)=[];
    A(ix,:)=xor(A(ix,:),repmat(A(k,:),numel(ix),1));
end
x=A(:,end);
end
