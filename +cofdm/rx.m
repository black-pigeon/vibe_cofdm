function r = rx(y,c,code)
r=struct('ok',false,'reason','','payload',uint8([]),'channelSaturations',0);
s=cofdm.synchronize(y,c); r.sync=s;
if ~s.ok, r.reason=s.reason; return; end
v=s.corrected; t=cofdm.training(c); span=c.nfft+c.ncp;
Y1=get_fft(v,s.ltfUsefulStart,c); Y2=get_fft(v,s.ltfUsefulStart+span,c);
H1=Y1./t.ltf(:,1); H2=Y2./t.ltf(:,2);
% Residual CFO estimated from these same LTFs can bias noise low slightly.
nv=max(mean(abs(H1-H2).^2)/2,1e-9);
[H,channelVariance,diag]=cofdm.estimate_channel((H1+H2)/2,nv/2,c);
r.channelSaturations=diag.saturations;
r.noiseVariance=nv; r.channelInitial=H; r.phase=[]; r.phaseSlope=[];
r.channelVarianceInitial=channelVariance;
pilotState=[]; r.fusionFastUpdates=0; r.fusionUpdates=0;
pos=s.ltfUsefulStart+2*span; symbolIndex=0;
headerLLR=zeros(c.nHeaderSymbols*numel(c.data),1);
for k=1:c.nHeaderSymbols
    symbolIndex=symbolIndex+1; Y=get_fft(v,pos,c); pos=pos+span;
    [Y,phi,slope,pilotState]=cofdm.track_pilots(Y,H,nv,channelVariance,c,symbolIndex,pilotState);
    r.phase(end+1)=phi; r.phaseSlope(end+1)=slope;
    hd=H(c.dataInActive); yd=Y(c.dataInActive);
    effectiveNoise=nv+c.channelErrorAwareLLR*channelVariance(c.dataInActive);
    headerLLR((k-1)*numel(c.data)+(1:numel(c.data)))=c.llrScale*4*real(conj(hd).*yd)./effectiveNoise;
end
if c.variablePayload
    header=cofdm.header_v2('decode',headerLLR,c); r.header=header;
    if ~header.ok, r.reason=header.reason; return; end
    c=header.config; r.frameConfig=c;
    % Bound the complete sample interval before allocating payload buffers.
    last=s.ltfUsefulStart+(2+c.nHeaderSymbols+c.nDataSymbols+c.nMidambles-1)*span+c.nfft-1;
    if last>numel(v), r.reason='v2 payload truncated'; return; end
else
headerLLR=headerLLR.*(1-2*double(cofdm.prbs(numel(headerLLR),c.headerScramblerSeed)));
[hb,r.headerSyndromeOk,r.headerIterations]=cofdm.ldpc_decode(headerLLR(1:code.n),code,c);
if ~r.headerSyndromeOk || ~cofdm.crc(hb(1:80),16,true)
    r.reason='header LDPC/CRC failure'; return;
end
h=cofdm.bits_to_bytes(hb(1:64));
r.sequence=double(h(5))*256+double(h(6));
if h(1)~=c.version || h(2)~=c.profile || ...
        double(h(3))*256+double(h(4))~=c.payloadBytes || ...
        h(7)~=c.nCodewords || h(8)~=0 || any(hb(81:end))
    r.reason='unsupported header profile/length/flags/padding'; return;
end
end
llr=zeros(c.bitsPerSymbol,c.nDataSymbols);
r.equalized=zeros(numel(c.data),c.nDataSymbols);
for k=1:c.nDataSymbols
    symbolIndex=symbolIndex+1; Y=get_fft(v,pos,c); pos=pos+span;
    [Y,phi,slope,pilotState]=cofdm.track_pilots(Y,H,nv,channelVariance,c,symbolIndex,pilotState);
    r.phase(end+1)=phi; r.phaseSlope(end+1)=slope;
    hd=H(c.dataInActive); yd=Y(c.dataInActive);
    matched=conj(hd).*yd;
    effectiveNoise=nv+c.channelErrorAwareLLR*channelVariance(c.dataInActive);
    r.equalized(:,k)=matched./(abs(hd).^2+effectiveNoise);
    % Equivalent unbiased QPSK LLR in matched-filter domain, no deep-fade divide.
    z=zeros(c.bitsPerSymbol,1);
    z(1:2:end)=c.llrScale*2*sqrt(2)*real(matched)./effectiveNoise;
    z(2:2:end)=c.llrScale*2*sqrt(2)*imag(matched)./effectiveNoise;
    llr(c.interleaver,k)=z;
    if mod(k,c.midambleEvery)==0 && k<c.nDataSymbols
        symbolIndex=symbolIndex+1;
        raw=get_fft(v,pos,c)./t.ltf(:,1); pos=pos+span;
        [fresh,freshVariance,diag]=cofdm.estimate_channel(raw,nv,c);
        r.channelSaturations=r.channelSaturations+diag.saturations;
        if c.channelFusion
            [H,channelVariance,fusion]=cofdm.fuse_channel(H,channelVariance,fresh,freshVariance,c,c.pilotInActive);
            r.fusionUpdates=r.fusionUpdates+1;
            r.fusionFastUpdates=r.fusionFastUpdates+fusion.fast;
            r.channelSaturations=r.channelSaturations+fusion.saturations;
        else
            H=fresh; channelVariance=freshVariance;
        end
    end
end
r.codedLLR=llr(:); r.codedLLR=r.codedLLR(1:c.nCodewords*code.n);
blocks=reshape(r.codedLLR,code.n,[]);
u=false(code.k,c.nCodewords); r.iterations=zeros(c.nCodewords,1);
r.syndromeOk=false(c.nCodewords,1);
for k=1:c.nCodewords
    [u(:,k),r.syndromeOk(k),r.iterations(k)]=cofdm.ldpc_decode(blocks(:,k),code,c);
end
b=xor(u(:),cofdm.prbs(numel(u),c.scramblerSeed));
paddingOk=true;
if c.variablePayload
    used=8*c.payloadBytes+32; paddingOk=~any(b(used+1:end));
    b=b(1:used); r.paddingOk=paddingOk;
end
r.crcOk=cofdm.crc(b,32,true);
r.payload=cofdm.bits_to_bytes(b(1:end-32));
r.ok=r.crcOk && all(r.syndromeOk) && paddingOk;
if ~r.ok, r.reason='payload LDPC/CRC failure'; end
end
function Y=get_fft(v,p,c)
f=fft(v(p:p+c.nfft-1))/sqrt(c.nfft); Y=f(c.activeBins);
end
